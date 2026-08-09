import Combine
import Foundation

enum SavedVocabularyKind: String, Codable, Sendable {
    case word
    case expression

    var label: String {
        switch self {
        case .word: "Word"
        case .expression: "Expression"
        }
    }
}

struct SavedVocabularyItem: Codable, Hashable, Identifiable, Sendable {
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
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var items: [SavedVocabularyItem] = []
    @Published private(set) var state: State = .loading
    @Published private(set) var errorMessage: String?

    private let repository: SavedVocabularyRepository
    private var appliedRevision = -1

    init(repository: SavedVocabularyRepository = SavedVocabularyRepository()) {
        self.repository = repository
    }

    func contains(_ itemID: String) -> Bool {
        items.contains { $0.id == itemID }
    }

    var isReady: Bool {
        state == .ready
    }

    func load() async {
        errorMessage = nil
        state = .loading
        do {
            apply(try await repository.load())
            state = .ready
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            errorMessage = message
        }
    }

    func add(_ item: SavedVocabularyItem) async {
        guard isReady else { return }
        do {
            apply(try await repository.add(item))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ itemID: String) async {
        await remove([itemID])
    }

    func remove(_ itemIDs: Set<String>) async {
        guard isReady else { return }
        do {
            apply(try await repository.remove(itemIDs))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func apply(_ snapshot: SavedVocabularySnapshot) {
        guard snapshot.revision >= appliedRevision else { return }
        appliedRevision = snapshot.revision
        items = snapshot.items
    }
}
