import Foundation

struct DictionaryEntry {
    let id: String
    let headword: String
    let reading: String
    let partOfSpeech: String
    let meanings: [String]
}

@main
struct SavedVocabularyHarness {
    @MainActor
    static func main() {
        let suiteName = "YomiLensSavedVocabularyTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            exit(2)
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let item = SavedVocabularyItem(
            id: "1327230|手に入れる|てにいれる",
            dictionaryEntryID: "1327230",
            kind: .expression,
            primaryForm: "手に入れる",
            headword: "手に入れる",
            surfaceForm: "手に入れた",
            dictionaryForm: "手に入れる",
            reading: "てにいれる",
            partOfSpeech: "expression",
            meanings: ["to obtain"],
            sourceText: "鍵を手に入れた。",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let store = SavedVocabularyStore(defaults: defaults)
        store.add(item)
        store.add(item)
        guard store.items == [item] else { exit(3) }

        let reloadedStore = SavedVocabularyStore(defaults: defaults)
        guard reloadedStore.items == [item],
              reloadedStore.items[0].dictionaryEntry.headword == "手に入れる" else {
            exit(4)
        }

        reloadedStore.remove(item.id)
        guard SavedVocabularyStore(defaults: defaults).items.isEmpty else {
            exit(5)
        }

        print("saved vocabulary persistence ok")
    }
}
