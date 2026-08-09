import Foundation

actor JapaneseAnalysisService {
    static let shared = JapaneseAnalysisService()

    func analyze(_ text: String) -> JapaneseTokenization {
        JapaneseTokenizer.tokenize(text)
    }

    func lookup(_ token: JapaneseToken) -> DictionaryEntry? {
        DictionaryService.lookup(token)
    }
}
