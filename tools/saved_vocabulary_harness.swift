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
    static func main() async throws {
        let suiteName = "YomiLensSavedVocabularyTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            exit(2)
        }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: temporaryDirectory)
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

        let legacyData = try JSONEncoder().encode([item])
        defaults.set(
            legacyData,
            forKey: SavedVocabularyRepository.legacyStorageKey
        )
        let archiveURL = temporaryDirectory
            .appendingPathComponent("saved-vocabulary.json")
        let store = SavedVocabularyStore(
            repository: SavedVocabularyRepository(
                fileURL: archiveURL,
                legacyDefaults: defaults
            )
        )
        await store.load()
        guard store.items == [item] else { exit(3) }
        guard FileManager.default.fileExists(atPath: archiveURL.path),
              defaults.data(
                forKey: SavedVocabularyRepository.legacyStorageKey
              ) == nil else {
            exit(9)
        }

        await store.add(item)
        guard store.items == [item] else { exit(10) }

        let reloadedStore = SavedVocabularyStore(
            repository: SavedVocabularyRepository(
                fileURL: archiveURL,
                legacyDefaults: defaults
            )
        )
        await reloadedStore.load()
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

        await reloadedStore.remove(item.id)
        let emptyReloadedStore = SavedVocabularyStore(
            repository: SavedVocabularyRepository(
                fileURL: archiveURL,
                legacyDefaults: defaults
            )
        )
        await emptyReloadedStore.load()
        guard emptyReloadedStore.items.isEmpty else {
            exit(5)
        }

        let corruptSuiteName = "\(suiteName)-corrupt"
        guard let corruptDefaults = UserDefaults(suiteName: corruptSuiteName) else {
            exit(11)
        }
        defer {
            corruptDefaults.removePersistentDomain(forName: corruptSuiteName)
        }
        corruptDefaults.set(
            legacyData,
            forKey: SavedVocabularyRepository.legacyStorageKey
        )
        let corruptArchiveURL = temporaryDirectory
            .appendingPathComponent("corrupt-vocabulary.json")
        let corruptData = Data("not valid JSON".utf8)
        try corruptData.write(to: corruptArchiveURL)
        let corruptStore = SavedVocabularyStore(
            repository: SavedVocabularyRepository(
                fileURL: corruptArchiveURL,
                legacyDefaults: corruptDefaults
            )
        )
        await corruptStore.load()
        guard case .failed = corruptStore.state,
              corruptStore.items.isEmpty,
              try Data(contentsOf: corruptArchiveURL) == corruptData,
              corruptDefaults.data(
                forKey: SavedVocabularyRepository.legacyStorageKey
              ) == legacyData else {
            exit(12)
        }

        await corruptStore.add(item)
        guard try Data(contentsOf: corruptArchiveURL) == corruptData else {
            exit(13)
        }

        let unsupportedArchiveURL = temporaryDirectory
            .appendingPathComponent("unsupported-vocabulary.json")
        let unsupportedData = Data(
            "{\"schemaVersion\":999,\"items\":[]}".utf8
        )
        try unsupportedData.write(to: unsupportedArchiveURL)
        let unsupportedStore = SavedVocabularyStore(
            repository: SavedVocabularyRepository(
                fileURL: unsupportedArchiveURL,
                legacyDefaults: defaults
            )
        )
        await unsupportedStore.load()
        guard case .failed(let unsupportedMessage) = unsupportedStore.state,
              unsupportedMessage.contains("unsupported schema version 999"),
              try Data(contentsOf: unsupportedArchiveURL) == unsupportedData else {
            exit(14)
        }

        let failedMigrationSuiteName = "\(suiteName)-failed-migration"
        guard let failedMigrationDefaults = UserDefaults(
            suiteName: failedMigrationSuiteName
        ) else {
            exit(15)
        }
        defer {
            failedMigrationDefaults.removePersistentDomain(
                forName: failedMigrationSuiteName
            )
        }
        failedMigrationDefaults.set(
            legacyData,
            forKey: SavedVocabularyRepository.legacyStorageKey
        )
        let blockedParentURL = temporaryDirectory
            .appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blockedParentURL)
        let failedMigrationStore = SavedVocabularyStore(
            repository: SavedVocabularyRepository(
                fileURL: blockedParentURL
                    .appendingPathComponent("saved-vocabulary.json"),
                legacyDefaults: failedMigrationDefaults
            )
        )
        await failedMigrationStore.load()
        guard case .failed = failedMigrationStore.state,
              failedMigrationDefaults.data(
                forKey: SavedVocabularyRepository.legacyStorageKey
              ) == legacyData else {
            exit(16)
        }

        print("saved vocabulary persistence ok")
    }
}
