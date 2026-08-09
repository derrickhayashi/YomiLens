import Foundation

struct DictionaryEntry: Identifiable, Hashable {
    let id: String
    let headword: String
    let reading: String
    let partOfSpeech: String
    let meanings: [String]
}

enum DictionaryService {
    // This intentionally tiny lexicon proves the lookup experience before the
    // preview takes on a full JMdict database and its build pipeline.
    private static let previewEntries: [DictionaryEntry] = [
        entry("先", "さき", "noun", "ahead; beyond", "destination; future"),
        entry("強大", "きょうだい", "adjective", "mighty; powerful"),
        entry("魔物", "まもの", "noun", "monster; evil spirit"),
        entry("潜む", "ひそむ", "verb", "to lurk; to lie hidden"),
        entry("いる", "いる", "verb", "to exist; to be (for animate things)"),
        entry("らしい", "らしい", "auxiliary adjective", "apparently; it seems", "typical of; like"),
        entry("行く", "いく", "verb", "to go"),
        entry("来る", "くる", "verb", "to come"),
        entry("見る", "みる", "verb", "to see; to look; to watch"),
        entry("食べる", "たべる", "verb", "to eat"),
        entry("分かる", "わかる", "verb", "to understand; to know"),
        entry("思う", "おもう", "verb", "to think; to feel"),
        entry("言う", "いう", "verb", "to say; to call"),
        entry("敵", "てき", "noun", "enemy; opponent"),
        entry("仲間", "なかま", "noun", "companion; comrade; ally"),
        entry("魔法", "まほう", "noun", "magic; sorcery"),
        entry("世界", "せかい", "noun", "world"),
        entry("力", "ちから", "noun", "power; strength; ability"),
        entry("必要", "ひつよう", "noun; adjective", "necessary; needed", "necessity"),
        entry("大丈夫", "だいじょうぶ", "adjective", "all right; okay; safe"),
        entry("本当", "ほんとう", "noun; adjective", "truth; reality", "true; real"),
        entry("今日", "きょう", "noun", "today"),
        entry("明日", "あした", "noun", "tomorrow"),
        entry("何", "なに", "pronoun", "what"),
        entry("誰", "だれ", "pronoun", "who")
    ]

    static func lookup(_ token: JapaneseToken) -> DictionaryEntry? {
        let candidates = [token.dictionaryForm, token.surface].compactMap { $0 }

        for candidate in candidates {
            let matches = previewEntries.filter { $0.headword == candidate }

            if matches.count == 1 {
                return matches[0]
            }

            if let reading = token.reading,
               let exactReadingMatch = matches.first(where: { $0.reading == reading }) {
                return exactReadingMatch
            }
        }

        return nil
    }

    private static func entry(
        _ headword: String,
        _ reading: String,
        _ partOfSpeech: String,
        _ meanings: String...
    ) -> DictionaryEntry {
        DictionaryEntry(
            id: "\(headword)|\(reading)",
            headword: headword,
            reading: reading,
            partOfSpeech: partOfSpeech,
            meanings: meanings
        )
    }
}
