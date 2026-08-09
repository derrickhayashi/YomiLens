import Foundation
import IPADic
import Mecab_Swift
import NaturalLanguage

struct JapaneseToken: Hashable, Identifiable, Sendable {
    let id: Int
    let order: Int
    let sentenceGroup: Int
    let textRange: NSRange
    let surface: String
    let reading: String?
    let dictionaryForm: String?
    let partOfSpeech: String?
}

struct FuriganaSpan: Sendable {
    let reading: String
    let range: NSRange
}

struct JapaneseExpression: Hashable, Identifiable, Sendable {
    let id: String
    let tokenIDs: [Int]
    let textRange: NSRange
    let surface: String
    let dictionaryForm: String?
    let entry: DictionaryEntry
}

struct JapaneseTokenization: Sendable {
    enum Source: Sendable {
        case mecabIPADic
        case appleNaturalLanguageFallback

        var label: String {
            switch self {
            case .mecabIPADic:
                "MeCab + IPADic"
            case .appleNaturalLanguageFallback:
                "Apple Natural Language fallback"
            }
        }
    }

    let tokens: [JapaneseToken]
    let furiganaSpans: [FuriganaSpan]
    let expressions: [JapaneseExpression]
    let source: Source

    static let empty = JapaneseTokenization(
        tokens: [],
        furiganaSpans: [],
        expressions: [],
        source: .mecabIPADic
    )
}

enum JapaneseTokenizer {
    private static let mecabTokenizer = try? Tokenizer(dictionary: IPADic())

    static func tokenize(_ text: String) -> JapaneseTokenization {
        guard !text.isEmpty else {
            return .empty
        }

        guard let mecabTokenizer else {
            return tokenizeWithAppleNaturalLanguage(text)
        }

        let annotations = mecabTokenizer.tokenize(
            text: text,
            transliteration: .hiragana
        )
        let lemmaAnnotations = mecabTokenizer.tokenize(
            text: text,
            // The package also transliterates dictionaryForm in hiragana
            // mode, so a second fast pass preserves the original kanji.
            transliteration: .katakana
        )

        let furiganaSpans = annotations.compactMap { annotation -> FuriganaSpan? in
            guard let furigana = annotation.furiganaAnnotation(
                options: [.kanjiOnly],
                for: text
            ) else {
                return nil
            }

            return FuriganaSpan(
                reading: furigana.reading,
                range: NSRange(furigana.range, in: text)
            )
        }

        var sentenceGroup = 0
        var previousUpperBound = text.startIndex
        var shouldStartNewSentence = false

        let tokens = annotations.enumerated().map { index, annotation in
            let gap = text[previousUpperBound..<annotation.range.lowerBound]

            if index > 0 && (shouldStartNewSentence || gap.contains("\n")) {
                sentenceGroup += 1
            }

            let preservedDictionaryForm: String
            if lemmaAnnotations.indices.contains(index),
               lemmaAnnotations[index].range == annotation.range {
                preservedDictionaryForm = lemmaAnnotations[index].dictionaryForm
            } else {
                preservedDictionaryForm = annotation.dictionaryForm
            }
            let dictionaryForm = normalizedDictionaryForm(
                preservedDictionaryForm,
                surface: annotation.base
            )

            previousUpperBound = annotation.range.upperBound
            shouldStartNewSentence = endsSentence(annotation.base)

            return JapaneseToken(
                id: index + 1,
                order: index + 1,
                sentenceGroup: sentenceGroup,
                textRange: NSRange(annotation.range, in: text),
                surface: annotation.base,
                reading: annotation.containsKanji ? annotation.reading : nil,
                dictionaryForm: dictionaryForm,
                partOfSpeech: annotation.partOfSpeech.description
            )
        }

        return JapaneseTokenization(
            tokens: tokens,
            furiganaSpans: furiganaSpans,
            expressions: findExpressions(in: tokens),
            source: .mecabIPADic
        )
    }

    private static func normalizedDictionaryForm(
        _ dictionaryForm: String,
        surface: String
    ) -> String? {
        guard dictionaryForm != "*", dictionaryForm != surface else {
            return nil
        }

        return dictionaryForm
    }

    private static func endsSentence(_ surface: String) -> Bool {
        guard let lastCharacter = surface.last else {
            return false
        }

        return "。！？!?".contains(lastCharacter)
    }

    private static func tokenizeWithAppleNaturalLanguage(
        _ text: String
    ) -> JapaneseTokenization {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.japanese)

        var tokens: [JapaneseToken] = []
        var sentenceGroup = 0
        var previousUpperBound = text.startIndex
        var shouldStartNewSentence = false

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let order = tokens.count + 1
            let gap = text[previousUpperBound..<range.lowerBound]

            if !tokens.isEmpty && (shouldStartNewSentence || gap.contains("\n")) {
                sentenceGroup += 1
            }

            let surface = String(text[range])

            tokens.append(JapaneseToken(
                id: order,
                order: order,
                sentenceGroup: sentenceGroup,
                textRange: NSRange(range, in: text),
                surface: surface,
                reading: nil,
                dictionaryForm: nil,
                partOfSpeech: nil
            ))

            previousUpperBound = range.upperBound
            shouldStartNewSentence = endsSentence(surface)

            return true
        }

        return JapaneseTokenization(
            tokens: tokens,
            furiganaSpans: [],
            expressions: findExpressions(in: tokens),
            source: .appleNaturalLanguageFallback
        )
    }

    private static func findExpressions(
        in tokens: [JapaneseToken]
    ) -> [JapaneseExpression] {
        let maximumTokenCount = 8
        let sentences = Dictionary(grouping: tokens, by: \.sentenceGroup)
            .sorted { $0.key < $1.key }
            .map { pair in pair.value.sorted { $0.order < $1.order } }
        var expressions: [JapaneseExpression] = []

        for sentence in sentences {
            var start = 0
            while start < sentence.count - 1 {
                let maximumEnd = min(
                    sentence.count - 1,
                    start + maximumTokenCount - 1
                )
                var match: JapaneseExpression?

                for end in stride(from: maximumEnd, through: start + 1, by: -1) {
                    let span = Array(sentence[start...end])
                    guard !span.contains(where: { $0.partOfSpeech == "symbol" }) else {
                        continue
                    }

                    let surface = span.map(\.surface).joined()
                    let reading = span.map { $0.reading ?? $0.surface }.joined()
                    for dictionaryForm in expressionDictionaryForms(for: span) {
                        guard let entry = DictionaryService.lookupExpression(
                            surface: surface,
                            reading: reading,
                            dictionaryForm: dictionaryForm
                        ) else {
                            continue
                        }

                        let firstRange = span[0].textRange
                        let lastRange = span[span.count - 1].textRange
                        match = JapaneseExpression(
                            id: "\(span[0].id)-\(span[span.count - 1].id)-\(entry.id)",
                            tokenIDs: span.map(\.id),
                            textRange: NSRange(
                                location: firstRange.location,
                                length: NSMaxRange(lastRange) - firstRange.location
                            ),
                            surface: surface,
                            dictionaryForm: dictionaryForm == surface
                                ? nil
                                : dictionaryForm,
                            entry: entry
                        )
                        break
                    }

                    if match != nil { break }
                }

                if let match {
                    expressions.append(match)
                    start += match.tokenIDs.count
                } else {
                    start += 1
                }
            }
        }

        return expressions
    }

    private static func expressionDictionaryForms(
        for tokens: [JapaneseToken]
    ) -> [String] {
        let surface = tokens.map(\.surface).joined()
        var forms = [surface]

        for index in tokens.indices.reversed() {
            guard let lemma = tokens[index].dictionaryForm,
                  tokens[(index + 1)...].allSatisfy({ token in
                      let partOfSpeech = token.partOfSpeech?.lowercased() ?? ""
                      return partOfSpeech.contains("auxiliary")
                          || partOfSpeech == "particle"
                  }) else {
                continue
            }

            let form = tokens[..<index].map(\.surface).joined() + lemma
            if !forms.contains(form) {
                forms.append(form)
            }
        }

        return forms
    }
}
