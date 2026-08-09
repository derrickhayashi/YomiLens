import Foundation
import SQLite3

struct DictionaryEntry: Hashable, Identifiable, Sendable {
    let id: String
    let headword: String
    let reading: String
    let partOfSpeech: String
    let meanings: [String]
}

enum DictionaryService {
    private static let database = DictionaryDatabase()

    static var isAvailable: Bool {
        database != nil
    }

    static var sourceDescription: String? {
        guard let created = database?.metadata("source_created") else {
            return nil
        }
        return "JMdict NG \(created)"
    }

    static var attribution: String {
        database?.metadata("source_attribution")
            ?? "This product uses the JMdict dictionary files."
    }

    static var licenseName: String {
        database?.metadata("source_license")
            ?? "Creative Commons Attribution-ShareAlike 4.0"
    }

    static var licenseURL: URL {
        let fallback = "https://www.edrdg.org/edrdg/licence.html"
        return URL(
            string: database?.metadata("source_license_url") ?? fallback
        )!
    }

    static func lookup(_ token: JapaneseToken) -> DictionaryEntry? {
        database?.lookup(token)
    }

    static func lookupExpression(
        surface: String,
        reading: String?,
        dictionaryForm: String?
    ) -> DictionaryEntry? {
        database?.lookup(
            surface: surface,
            reading: reading,
            dictionaryForm: dictionaryForm,
            partOfSpeech: nil,
            includeReadingCandidate: false
        )
    }
}

private enum MatchKind {
    case lemma
    case surface
    case reading

    var baseScore: Int {
        switch self {
        case .lemma: 400
        case .surface: 350
        case .reading: 250
        }
    }
}

private struct LookupCandidate {
    let term: String
    let normalizedTerm: String
    let kind: MatchKind
}

private struct EntryMatch {
    let entryID: Int64
    let matchedTerm: String
    let termType: String
    let score: Int
}

private struct ReadingRecord {
    let value: String
    let normalizedValue: String
}

private struct SenseRecord {
    let order: Int
    let partsOfSpeech: [String]
    let glosses: [String]
}

final class DictionaryDatabase {
    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private var connection: OpaquePointer?

    convenience init?() {
        guard let databaseURL = Bundle.main.url(
            forResource: "JMdict",
            withExtension: "sqlite3"
        ) else {
            return nil
        }

        self.init(databaseURL: databaseURL)
    }

    init?(databaseURL: URL) {
        let result = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK,
              metadata("schema_version") == "2" else {
            if let connection {
                sqlite3_close(connection)
            }
            return nil
        }
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    func metadata(_ key: String) -> String? {
        querySingleText(
            "SELECT value FROM metadata WHERE key = ? LIMIT 1",
            bindings: [key]
        )
    }

    func lookup(_ token: JapaneseToken) -> DictionaryEntry? {
        lookup(
            surface: token.surface,
            reading: token.reading,
            dictionaryForm: token.dictionaryForm,
            partOfSpeech: token.partOfSpeech,
            includeReadingCandidate: true
        )
    }

    func lookup(
        surface: String,
        reading: String?,
        dictionaryForm: String?,
        partOfSpeech tokenPartOfSpeech: String?,
        includeReadingCandidate: Bool = true
    ) -> DictionaryEntry? {
        let candidates = lookupCandidates(
            surface: surface,
            reading: reading,
            dictionaryForm: dictionaryForm,
            includeReading: includeReadingCandidate
        )
        let preferredReading = reading.map(normalizeReading)
        var bestMatches: [Int64: EntryMatch] = [:]
        var partsOfSpeechCache: [Int64: [String]] = [:]

        for candidate in candidates {
            for row in lookupRows(for: candidate) {
                var score = candidate.kind.baseScore
                score += row.isExact ? 60 : 20

                let expectedType = candidate.kind == .reading
                    ? "reading"
                    : "spelling"
                if row.termType == expectedType {
                    score += 25
                }
                if row.isCommon {
                    score += 35
                }
                if let preferredReading,
                   entry(
                    row.entryID,
                    hasNormalizedReading: preferredReading,
                    allowedSpelling: row.termType == "spelling"
                        ? row.term
                        : nil
                   ) {
                    score += 45
                }

                let partsOfSpeech = partsOfSpeechCache[row.entryID]
                    ?? entryPartsOfSpeech(row.entryID)
                partsOfSpeechCache[row.entryID] = partsOfSpeech
                if partsOfSpeech.contains(where: {
                    partOfSpeech($0, matches: tokenPartOfSpeech)
                }) {
                    score += 45
                }

                score += max(0, 10 - min(row.sortOrder, 10))
                let match = EntryMatch(
                    entryID: row.entryID,
                    matchedTerm: row.term,
                    termType: row.termType,
                    score: score
                )
                if score > bestMatches[row.entryID]?.score ?? Int.min {
                    bestMatches[row.entryID] = match
                }
            }
        }

        for match in bestMatches.values.sorted(by: matchSort) {
            if let result = dictionaryEntry(
                for: match,
                preferredReading: preferredReading,
                tokenPartOfSpeech: tokenPartOfSpeech
            ) {
                return result
            }
        }

        return nil
    }

    private func lookupCandidates(
        surface: String,
        reading: String?,
        dictionaryForm: String?,
        includeReading: Bool
    ) -> [LookupCandidate] {
        var candidates: [LookupCandidate] = []
        var seen = Set<String>()

        func append(_ value: String?, kind: MatchKind, reading: Bool = false) {
            guard let value else { return }
            let term = normalizeSpelling(value)
            guard !term.isEmpty else { return }
            let normalized = reading ? normalizeReading(term) : term
            let key = "\(kind)-\(term)-\(normalized)"
            guard seen.insert(key).inserted else { return }
            candidates.append(
                LookupCandidate(
                    term: term,
                    normalizedTerm: normalized,
                    kind: kind
                )
            )
        }

        append(dictionaryForm, kind: .lemma)
        append(surface, kind: .surface)
        if includeReading {
            append(reading, kind: .reading, reading: true)
        }
        return candidates
    }

    private func lookupRows(for candidate: LookupCandidate) -> [(
        entryID: Int64,
        term: String,
        termType: String,
        sortOrder: Int,
        isExact: Bool,
        isCommon: Bool
    )] {
        let sql = """
            SELECT
                l.entry_id,
                l.term,
                l.term_type,
                l.sort_order,
                CASE WHEN l.term = ? THEN 1 ELSE 0 END,
                CASE
                    WHEN l.term_type = 'spelling' AND EXISTS (
                        SELECT 1 FROM spelling_priorities sp
                        WHERE sp.entry_id = l.entry_id
                          AND sp.spelling = l.term
                          AND sp.priority IN ('ichi1', 'news1', 'spec1', 'gai1')
                    ) THEN 1
                    WHEN l.term_type = 'reading' AND EXISTS (
                        SELECT 1 FROM reading_priorities rp
                        WHERE rp.entry_id = l.entry_id
                          AND rp.reading = l.term
                          AND rp.priority IN ('ichi1', 'news1', 'spec1', 'gai1')
                    ) THEN 1
                    ELSE 0
                END
            FROM lookup_terms l
            WHERE l.term = ? OR l.normalized_term = ?
            ORDER BY 5 DESC, 6 DESC, l.sort_order, l.entry_id
            LIMIT 40
            """

        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(
            [candidate.term, candidate.term, candidate.normalizedTerm],
            in: statement
        )

        var rows: [(
            entryID: Int64,
            term: String,
            termType: String,
            sortOrder: Int,
            isExact: Bool,
            isCommon: Bool
        )] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let term = columnText(statement, 1),
              let termType = columnText(statement, 2) {
            rows.append((
                entryID: sqlite3_column_int64(statement, 0),
                term: term,
                termType: termType,
                sortOrder: Int(sqlite3_column_int(statement, 3)),
                isExact: sqlite3_column_int(statement, 4) == 1,
                isCommon: sqlite3_column_int(statement, 5) == 1
            ))
        }
        return rows
    }

    private func dictionaryEntry(
        for match: EntryMatch,
        preferredReading: String?,
        tokenPartOfSpeech: String?
    ) -> DictionaryEntry? {
        let matchedSpelling = match.termType == "spelling"
            ? match.matchedTerm
            : nil
        let matchedReading = match.termType == "reading"
            ? normalizeReading(match.matchedTerm)
            : nil
        guard let reading = preferredReadingRecord(
            entryID: match.entryID,
            preferredReading: preferredReading ?? matchedReading,
            matchedSpelling: matchedSpelling
        ) else {
            return nil
        }

        let spelling = preferredSpelling(
            entryID: match.entryID,
            matchedSpelling: matchedSpelling,
            reading: reading.value
        )
        let headword = spelling ?? reading.value

        let senses = senses(
            entryID: match.entryID,
            spelling: spelling,
            reading: reading.value
        ).sorted { first, second in
            let firstMatches = first.partsOfSpeech.contains {
                partOfSpeech($0, matches: tokenPartOfSpeech)
            }
            let secondMatches = second.partsOfSpeech.contains {
                partOfSpeech($0, matches: tokenPartOfSpeech)
            }
            if firstMatches != secondMatches {
                return firstMatches
            }
            return first.order < second.order
        }

        guard let primarySense = senses.first else { return nil }
        let primaryPartOfSpeech = primarySense.partsOfSpeech.first {
            partOfSpeech($0, matches: tokenPartOfSpeech)
        } ?? primarySense.partsOfSpeech.first ?? "Unclassified"
        var seenMeanings = Set<String>()
        let meanings = senses
            .flatMap(\.glosses)
            .filter { seenMeanings.insert($0).inserted }
            .prefix(3)
        guard !meanings.isEmpty else { return nil }

        return DictionaryEntry(
            id: String(match.entryID),
            headword: headword,
            reading: reading.value,
            partOfSpeech: primaryPartOfSpeech,
            meanings: Array(meanings)
        )
    }

    private func preferredReadingRecord(
        entryID: Int64,
        preferredReading: String?,
        matchedSpelling: String?
    ) -> ReadingRecord? {
        let sql = """
            SELECT reading
            FROM readings
            WHERE entry_id = ?
            ORDER BY sort_order
            """
        guard let statement = prepare(sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        bind([entryID], in: statement)

        var records: [ReadingRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let value = columnText(statement, 0) {
            if reading(
                value,
                entryID: entryID,
                allowsSpelling: matchedSpelling
            ) {
                records.append(ReadingRecord(
                    value: value,
                    normalizedValue: normalizeReading(value)
                ))
            }
        }
        return records.first {
            $0.normalizedValue == preferredReading
        } ?? records.first
    }

    private func preferredSpelling(
        entryID: Int64,
        matchedSpelling: String?,
        reading: String
    ) -> String? {
        let spellings = queryTexts(
            """
            SELECT spelling FROM spellings
            WHERE entry_id = ?
            ORDER BY CASE WHEN spelling = ? THEN 0 ELSE 1 END, sort_order
            """,
            bindings: [entryID, matchedSpelling]
        )
        return spellings.first {
            self.reading(reading, entryID: entryID, allowsSpelling: $0)
        }
    }

    private func reading(
        _ reading: String,
        entryID: Int64,
        allowsSpelling spelling: String?
    ) -> Bool {
        let restrictionCount = querySingleInt(
            """
            SELECT COUNT(*) FROM reading_restrictions
            WHERE entry_id = ? AND reading = ?
            """,
            bindings: [entryID, reading]
        ) ?? 0
        guard restrictionCount > 0 else { return true }
        guard let spelling else { return true }
        return querySingleInt(
            """
            SELECT COUNT(*) FROM reading_restrictions
            WHERE entry_id = ? AND reading = ? AND spelling = ?
            """,
            bindings: [entryID, reading, spelling]
        ) ?? 0 > 0
    }

    private func senses(
        entryID: Int64,
        spelling: String?,
        reading: String
    ) -> [SenseRecord] {
        let orders = queryInts(
            "SELECT sense_order FROM senses WHERE entry_id = ? ORDER BY sense_order",
            bindings: [entryID]
        )
        return orders.compactMap { order in
            guard sense(
                order,
                entryID: entryID,
                allowsSpelling: spelling,
                reading: reading
            ) else {
                return nil
            }
            let partsOfSpeech = queryTexts(
                """
                SELECT part_of_speech FROM sense_parts_of_speech
                WHERE entry_id = ? AND sense_order = ?
                ORDER BY sort_order
                """,
                bindings: [entryID, Int64(order)]
            )
            let glosses = queryTexts(
                """
                SELECT gloss FROM sense_glosses
                WHERE entry_id = ? AND sense_order = ?
                ORDER BY sort_order
                """,
                bindings: [entryID, Int64(order)]
            )
            guard !glosses.isEmpty else { return nil }
            return SenseRecord(
                order: order,
                partsOfSpeech: partsOfSpeech,
                glosses: glosses
            )
        }
    }

    private func sense(
        _ senseOrder: Int,
        entryID: Int64,
        allowsSpelling spelling: String?,
        reading: String
    ) -> Bool {
        let spellingRestrictions = querySingleInt(
            """
            SELECT COUNT(*) FROM sense_spelling_restrictions
            WHERE entry_id = ? AND sense_order = ?
            """,
            bindings: [entryID, Int64(senseOrder)]
        ) ?? 0
        if spellingRestrictions > 0 {
            guard let spelling,
                  querySingleInt(
                    """
                    SELECT COUNT(*) FROM sense_spelling_restrictions
                    WHERE entry_id = ? AND sense_order = ? AND spelling = ?
                    """,
                    bindings: [entryID, Int64(senseOrder), spelling]
                  ) ?? 0 > 0 else {
                return false
            }
        }

        let readingRestrictions = querySingleInt(
            """
            SELECT COUNT(*) FROM sense_reading_restrictions
            WHERE entry_id = ? AND sense_order = ?
            """,
            bindings: [entryID, Int64(senseOrder)]
        ) ?? 0
        if readingRestrictions > 0,
           querySingleInt(
            """
            SELECT COUNT(*) FROM sense_reading_restrictions
            WHERE entry_id = ? AND sense_order = ? AND reading = ?
            """,
            bindings: [entryID, Int64(senseOrder), reading]
           ) ?? 0 == 0 {
            return false
        }
        return true
    }

    private func entry(
        _ entryID: Int64,
        hasNormalizedReading reading: String,
        allowedSpelling spelling: String?
    ) -> Bool {
        queryTexts(
            "SELECT reading FROM readings WHERE entry_id = ?",
            bindings: [entryID]
        ).contains {
            normalizeReading($0) == reading
                && self.reading(
                    $0,
                    entryID: entryID,
                    allowsSpelling: spelling
                )
        }
    }

    private func entryPartsOfSpeech(_ entryID: Int64) -> [String] {
        queryTexts(
            """
            SELECT DISTINCT part_of_speech FROM sense_parts_of_speech
            WHERE entry_id = ? ORDER BY sense_order, sort_order
            """,
            bindings: [entryID]
        )
    }

    private func partOfSpeech(
        _ dictionaryPartOfSpeech: String,
        matches tokenPartOfSpeech: String?
    ) -> Bool {
        guard let tokenPartOfSpeech else { return false }
        let token = tokenPartOfSpeech.lowercased()
        let dictionary = dictionaryPartOfSpeech.lowercased()

        if token.contains("verb") { return dictionary.contains("verb") }
        if token.contains("noun") {
            return dictionary.contains("noun")
                || dictionary.contains("pronoun")
                || dictionary.contains("numeric")
                || dictionary.contains("counter")
        }
        if token.contains("adjective") {
            return dictionary.contains("adjective")
                || dictionary.contains("adjectival")
        }
        if token.contains("adverb") { return dictionary.contains("adverb") }
        if token.contains("auxiliary") {
            return dictionary.contains("auxiliary")
        }
        if token.contains("conjunction") {
            return dictionary.contains("conjunction")
        }
        if token.contains("interjection") {
            return dictionary.contains("interjection")
        }
        if token.contains("prefix") { return dictionary.contains("prefix") }
        if token.contains("suffix") { return dictionary.contains("suffix") }
        return false
    }

    private func matchSort(_ first: EntryMatch, _ second: EntryMatch) -> Bool {
        if first.score != second.score { return first.score > second.score }
        return first.entryID < second.entryID
    }

    private func normalizeSpelling(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeReading(_ value: String) -> String {
        let normalized = normalizeSpelling(value)
        return normalized.applyingTransform(
            .hiraganaToKatakana,
            reverse: true
        ) ?? normalized
    }

    private func querySingleText(
        _ sql: String,
        bindings: [Any?]
    ) -> String? {
        guard let statement = prepare(sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(bindings, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return columnText(statement, 0)
    }

    private func querySingleInt(
        _ sql: String,
        bindings: [Any?]
    ) -> Int? {
        guard let statement = prepare(sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(bindings, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func queryInts(
        _ sql: String,
        bindings: [Any?]
    ) -> [Int] {
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(bindings, in: statement)
        var values: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            values.append(Int(sqlite3_column_int64(statement, 0)))
        }
        return values
    }

    private func queryTexts(
        _ sql: String,
        bindings: [Any?]
    ) -> [String] {
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(bindings, in: statement)
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let value = columnText(statement, 0) {
            values.append(value)
        }
        return values
    }

    private func columnText(
        _ statement: OpaquePointer?,
        _ column: Int32
    ) -> String? {
        guard let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: text)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let connection else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            connection,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            return nil
        }
        return statement
    }

    private func bind(_ values: [Any?], in statement: OpaquePointer?) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case let value as String:
                bind(value, to: index, in: statement)
            case let value as Int64:
                sqlite3_bind_int64(statement, index, value)
            case let value as Int:
                sqlite3_bind_int64(statement, index, Int64(value))
            case nil:
                sqlite3_bind_null(statement, index)
            default:
                assertionFailure("Unsupported SQLite binding")
            }
        }
    }

    private func bind(
        _ value: String?,
        to index: Int32,
        in statement: OpaquePointer?
    ) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(
            statement,
            index,
            value,
            -1,
            Self.sqliteTransient
        )
    }
}
