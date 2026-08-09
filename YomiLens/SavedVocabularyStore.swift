import Combine
import Foundation

enum SavedVocabularyKind: String, Codable {
    case word
    case expression

    var label: String {
        switch self {
        case .word: "Word"
        case .expression: "Expression"
        }
    }
}

struct SavedVocabularyItem: Codable, Hashable, Identifiable {
    let id: String
    let dictionaryEntryID: String
    let kind: SavedVocabularyKind
    let primaryForm: String
    let headword: String
    let surfaceForm: String
    let dictionaryForm: String?
    let reading: String
    let partOfSpeech: String
    let meanings: [String]
    let sourceText: String
    let sourceLocation: Int?
    let sourceLength: Int?
    let savedAt: Date

    init(
        id: String,
        dictionaryEntryID: String,
        kind: SavedVocabularyKind,
        primaryForm: String,
        headword: String,
        surfaceForm: String,
        dictionaryForm: String?,
        reading: String,
        partOfSpeech: String,
        meanings: [String],
        sourceText: String,
        sourceLocation: Int? = nil,
        sourceLength: Int? = nil,
        savedAt: Date
    ) {
        self.id = id
        self.dictionaryEntryID = dictionaryEntryID
        self.kind = kind
        self.primaryForm = primaryForm
        self.headword = headword
        self.surfaceForm = surfaceForm
        self.dictionaryForm = dictionaryForm
        self.reading = reading
        self.partOfSpeech = partOfSpeech
        self.meanings = meanings
        self.sourceText = sourceText
        self.sourceLocation = sourceLocation
        self.sourceLength = sourceLength
        self.savedAt = savedAt
    }

    var dictionaryEntry: DictionaryEntry {
        DictionaryEntry(
            id: dictionaryEntryID,
            headword: headword,
            reading: reading,
            partOfSpeech: partOfSpeech,
            meanings: meanings
        )
    }
}

@MainActor
final class SavedVocabularyStore: ObservableObject {
    @Published private(set) var items: [SavedVocabularyItem]

    private let defaults: UserDefaults
    private let storageKey = "savedVocabulary.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        guard let data = defaults.data(forKey: storageKey),
              let savedItems = try? JSONDecoder().decode(
                [SavedVocabularyItem].self,
                from: data
              ) else {
            items = []
            return
        }

        items = savedItems.sorted { $0.savedAt > $1.savedAt }
    }

    func contains(_ itemID: String) -> Bool {
        items.contains { $0.id == itemID }
    }

    func add(_ item: SavedVocabularyItem) {
        guard !contains(item.id) else { return }
        items.insert(item, at: 0)
        persist()
    }

    func remove(_ itemID: String) {
        items.removeAll { $0.id == itemID }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
