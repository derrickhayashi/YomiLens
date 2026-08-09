import Foundation
import SQLite3

struct DictionaryEntry: Identifiable, Hashable {
    let id: String
    let headword: String
    let reading: String
    let partOfSpeech: String
    let meanings: [String]
}

@MainActor
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
}

private final class DictionaryDatabase {
    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private var connection: OpaquePointer?

    init?() {
        guard let databaseURL = Bundle.main.url(
            forResource: "JMdict",
            withExtension: "sqlite3"
        ) else {
            return nil
        }

        let result = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK else {
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
        var seen = Set<String>()
        let candidates = [token.dictionaryForm, token.surface]
            .compactMap { $0 }
            .filter { seen.insert($0).inserted }

        for candidate in candidates {
            let preferredReading = candidate == token.surface
                ? token.reading
                : nil
            guard let entryID = bestEntryID(
                for: candidate,
                preferredReading: preferredReading
            ) else {
                continue
            }

            return entry(
                id: entryID,
                matchedTerm: candidate,
                preferredReading: preferredReading
            )
        }

        return nil
    }

    private func bestEntryID(
        for term: String,
        preferredReading: String?
    ) -> Int64? {
        let sql = """
            SELECT l.entry_id
            FROM lookup_terms l
            WHERE l.term = ?
            GROUP BY l.entry_id
            ORDER BY
                CASE
                    WHEN ? IS NOT NULL AND EXISTS (
                        SELECT 1 FROM readings r
                        WHERE r.entry_id = l.entry_id AND r.reading = ?
                    ) THEN 0 ELSE 1
                END,
                CASE
                    WHEN EXISTS (
                        SELECT 1 FROM spelling_priorities sp
                        WHERE sp.entry_id = l.entry_id
                          AND sp.priority IN ('ichi1', 'news1', 'spec1', 'gai1')
                    ) OR EXISTS (
                        SELECT 1 FROM reading_priorities rp
                        WHERE rp.entry_id = l.entry_id
                          AND rp.priority IN ('ichi1', 'news1', 'spec1', 'gai1')
                    ) THEN 0 ELSE 1
                END,
                MIN(CASE WHEN l.term_type = 'spelling' THEN 0 ELSE 1 END),
                MIN(l.sort_order),
                l.entry_id
            LIMIT 1
            """

        guard let statement = prepare(sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bind(term, to: 1, in: statement)
        bind(preferredReading, to: 2, in: statement)
        bind(preferredReading, to: 3, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func entry(
        id entryID: Int64,
        matchedTerm: String,
        preferredReading: String?
    ) -> DictionaryEntry? {
        let headword = querySingleText(
            """
            SELECT spelling FROM spellings
            WHERE entry_id = ?
            ORDER BY CASE WHEN spelling = ? THEN 0 ELSE 1 END, sort_order
            LIMIT 1
            """,
            bindings: [entryID, matchedTerm]
        ) ?? querySingleText(
            "SELECT reading FROM readings WHERE entry_id = ? ORDER BY sort_order LIMIT 1",
            bindings: [entryID]
        )

        guard let headword else {
            return nil
        }

        let reading = querySingleText(
            """
            SELECT reading FROM readings
            WHERE entry_id = ?
            ORDER BY CASE WHEN reading = ? THEN 0 ELSE 1 END, sort_order
            LIMIT 1
            """,
            bindings: [entryID, preferredReading]
        ) ?? ""

        let partOfSpeech = querySingleText(
            """
            SELECT part_of_speech FROM sense_parts_of_speech
            WHERE entry_id = ?
            ORDER BY sense_order, sort_order
            LIMIT 1
            """,
            bindings: [entryID]
        ) ?? "Unclassified"

        let meanings = queryTexts(
            """
            SELECT gloss FROM sense_glosses
            WHERE entry_id = ?
            ORDER BY sense_order, sort_order
            """,
            bindings: [entryID],
            uniqueLimit: 3
        )

        guard !meanings.isEmpty else {
            return nil
        }

        return DictionaryEntry(
            id: String(entryID),
            headword: headword,
            reading: reading,
            partOfSpeech: partOfSpeech,
            meanings: meanings
        )
    }

    private func querySingleText(
        _ sql: String,
        bindings: [Any?]
    ) -> String? {
        guard let statement = prepare(sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        bind(bindings, in: statement)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    private func queryTexts(
        _ sql: String,
        bindings: [Any?],
        uniqueLimit: Int
    ) -> [String] {
        guard let statement = prepare(sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind(bindings, in: statement)

        var results: [String] = []
        var seen = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) {
            let value = String(cString: text)
            if seen.insert(value).inserted {
                results.append(value)
            }
            if results.count == uniqueLimit {
                break
            }
        }
        return results
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let connection else {
            return nil
        }
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
