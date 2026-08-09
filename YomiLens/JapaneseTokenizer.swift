import IPADic
import Mecab_Swift
import NaturalLanguage

struct JapaneseToken: Identifiable {
    let id: Int
    let order: Int
    let sentenceGroup: Int
    let textRange: NSRange
    let surface: String
    let reading: String?
    let dictionaryForm: String?
    let partOfSpeech: String?
}

struct FuriganaSpan {
    let reading: String
    let range: NSRange
}

struct JapaneseTokenization {
    enum Source {
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
    let source: Source

    static let empty = JapaneseTokenization(
        tokens: [],
        furiganaSpans: [],
        source: .mecabIPADic
    )
}

@MainActor
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

            let dictionaryForm = normalizedDictionaryForm(
                annotation.dictionaryForm,
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
            source: .appleNaturalLanguageFallback
        )
    }
}
