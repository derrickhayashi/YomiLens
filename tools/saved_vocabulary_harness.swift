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

        let passage = "最初の文に従い進む。山の掟に従い生きる。最後の文。"
        let passageNSString = passage as NSString
        let firstOccurrence = passageNSString.range(of: "従い")
        let secondOccurrence = passageNSString.range(
            of: "従い",
            options: [],
            range: NSRange(
                location: NSMaxRange(firstOccurrence),
                length: passageNSString.length - NSMaxRange(firstOccurrence)
            )
        )
        let exportItem = SavedVocabularyItem(
            id: "1352500|従う|したがう",
            dictionaryEntryID: "1352500",
            kind: .word,
            primaryForm: "従う",
            headword: "従う",
            surfaceForm: "従い",
            dictionaryForm: "従う",
            reading: "したがう",
            partOfSpeech: "verb",
            meanings: ["to follow", "to obey"],
            sourceText: passage,
            sourceLocation: secondOccurrence.location,
            sourceLength: secondOccurrence.length,
            savedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let export = AnkiExportService.content(for: exportItem)
        guard export.word == "従う",
              export.reading == "したがう",
              export.meaning == "to follow",
              export.exampleHTML == "山の掟に<b>従い</b>生きる。" else {
            exit(6)
        }

        guard let url = AnkiExportService.addNoteURL(
            for: exportItem,
            noteType: "Japanese",
            deck: "Vocabulary",
            meaning: "to obey"
        ),
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.scheme == "anki",
        components.queryItems?.first(where: { $0.name == "fldWord" })?.value == "従う",
        components.queryItems?.first(where: { $0.name == "fldMeaning" })?.value == "to obey",
        components.queryItems?.first(where: { $0.name == "fldExample" })?.value == "山の掟に<b>従い</b>生きる。" else {
            exit(7)
        }

        let quotedItem = SavedVocabularyItem(
            id: exportItem.id,
            dictionaryEntryID: exportItem.dictionaryEntryID,
            kind: exportItem.kind,
            primaryForm: exportItem.primaryForm,
            headword: exportItem.headword,
            surfaceForm: exportItem.surfaceForm,
            dictionaryForm: exportItem.dictionaryForm,
            reading: exportItem.reading,
            partOfSpeech: exportItem.partOfSpeech,
            meanings: exportItem.meanings,
            sourceText: "「前の文。」山の掟に従い生きる。",
            savedAt: exportItem.savedAt
        )
        guard AnkiExportService.sentenceExampleHTML(for: quotedItem)
            == "山の掟に<b>従い</b>生きる。" else {
            exit(8)
        }

        reloadedStore.remove(item.id)
        guard SavedVocabularyStore(defaults: defaults).items.isEmpty else {
            exit(5)
        }

        print("saved vocabulary persistence ok")
    }
}
