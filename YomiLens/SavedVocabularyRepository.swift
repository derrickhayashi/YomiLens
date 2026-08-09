import Foundation

struct SavedVocabularyArchiveV1: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let items: [SavedVocabularyItem]

    init(items: [SavedVocabularyItem]) {
        schemaVersion = Self.currentSchemaVersion
        self.items = items
    }
}

struct SavedVocabularySnapshot: Sendable {
    let revision: Int
    let items: [SavedVocabularyItem]
}

enum SavedVocabularyRepositoryError: LocalizedError, Sendable {
    case archiveUnreadable
    case legacyArchiveUnreadable
    case unsupportedSchemaVersion(Int)
    case migrationVerificationFailed
    case archiveWriteFailed

    var errorDescription: String? {
        switch self {
        case .archiveUnreadable:
            "The saved vocabulary file could not be read. It was preserved and will not be overwritten."
        case .legacyArchiveUnreadable:
            "Existing saved vocabulary could not be migrated. The original data was preserved."
        case .unsupportedSchemaVersion(let version):
            "Saved vocabulary uses unsupported schema version \(version). The file was preserved."
        case .migrationVerificationFailed:
            "Saved vocabulary migration could not be verified. The original data was preserved."
        case .archiveWriteFailed:
            "Saved vocabulary could not be updated. Existing data was preserved."
        }
    }
}

actor SavedVocabularyRepository {
    static let legacyStorageKey = "savedVocabulary.v1"

    private enum StorageLocation: Sendable {
        case applicationSupport
        case custom(URL)
    }

    private struct ArchiveHeader: Decodable {
        let schemaVersion: Int
    }

    private let storageLocation: StorageLocation
    private let legacyDefaults: UserDefaults
    private let legacyStorageKey: String
    private let fileManager: FileManager
    private var cachedItems: [SavedVocabularyItem]?
    private var revision = 0

    init(
        fileURL: URL? = nil,
        legacyDefaults: UserDefaults = .standard,
        legacyStorageKey: String = SavedVocabularyRepository.legacyStorageKey,
        fileManager: FileManager = .default
    ) {
        storageLocation = fileURL.map(StorageLocation.custom)
            ?? .applicationSupport
        self.legacyDefaults = legacyDefaults
        self.legacyStorageKey = legacyStorageKey
        self.fileManager = fileManager
    }

    func load() throws -> SavedVocabularySnapshot {
        let items = try loadedItems()
        return snapshot(items)
    }

    func add(_ item: SavedVocabularyItem) throws -> SavedVocabularySnapshot {
        let currentItems = try loadedItems()
        guard !currentItems.contains(where: { $0.id == item.id }) else {
            return snapshot(currentItems)
        }

        var updatedItems = currentItems
        updatedItems.insert(item, at: 0)
        try persist(updatedItems)
        cachedItems = updatedItems
        revision += 1
        return snapshot(updatedItems)
    }

    func remove(_ itemIDs: Set<String>) throws -> SavedVocabularySnapshot {
        let currentItems = try loadedItems()
        let updatedItems = currentItems.filter { !itemIDs.contains($0.id) }
        guard updatedItems != currentItems else {
            return snapshot(currentItems)
        }

        try persist(updatedItems)
        cachedItems = updatedItems
        revision += 1
        return snapshot(updatedItems)
    }

    private func loadedItems() throws -> [SavedVocabularyItem] {
        if let cachedItems {
            return cachedItems
        }

        let fileURL = try resolvedFileURL()
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let archive = try decodeArchive(Data(contentsOf: fileURL))
                let items = sorted(archive.items)
                cachedItems = items
                return items
            } catch let error as SavedVocabularyRepositoryError {
                throw error
            } catch {
                throw SavedVocabularyRepositoryError.archiveUnreadable
            }
        }

        guard let legacyData = legacyDefaults.data(forKey: legacyStorageKey) else {
            cachedItems = []
            return []
        }

        let legacyItems: [SavedVocabularyItem]
        do {
            legacyItems = try JSONDecoder().decode(
                [SavedVocabularyItem].self,
                from: legacyData
            )
        } catch {
            throw SavedVocabularyRepositoryError.legacyArchiveUnreadable
        }

        let items = sorted(legacyItems)
        try persist(items)
        do {
            let verifiedArchive = try decodeArchive(Data(contentsOf: fileURL))
            guard sorted(verifiedArchive.items) == items else {
                throw SavedVocabularyRepositoryError.migrationVerificationFailed
            }
        } catch {
            throw SavedVocabularyRepositoryError.migrationVerificationFailed
        }

        legacyDefaults.removeObject(forKey: legacyStorageKey)
        cachedItems = items
        return items
    }

    private func persist(_ items: [SavedVocabularyItem]) throws {
        do {
            let fileURL = try resolvedFileURL()
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(SavedVocabularyArchiveV1(items: items))

            var options: Data.WritingOptions = [.atomic]
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            options.insert(.completeFileProtection)
#endif
            try data.write(to: fileURL, options: options)
        } catch {
            throw SavedVocabularyRepositoryError.archiveWriteFailed
        }
    }

    private func decodeArchive(_ data: Data) throws -> SavedVocabularyArchiveV1 {
        let decoder = JSONDecoder()
        let header: ArchiveHeader
        do {
            header = try decoder.decode(ArchiveHeader.self, from: data)
        } catch {
            throw SavedVocabularyRepositoryError.archiveUnreadable
        }

        guard header.schemaVersion
                == SavedVocabularyArchiveV1.currentSchemaVersion else {
            throw SavedVocabularyRepositoryError.unsupportedSchemaVersion(
                header.schemaVersion
            )
        }

        do {
            return try decoder.decode(SavedVocabularyArchiveV1.self, from: data)
        } catch {
            throw SavedVocabularyRepositoryError.archiveUnreadable
        }
    }

    private func resolvedFileURL() throws -> URL {
        switch storageLocation {
        case .custom(let url):
            return url
        case .applicationSupport:
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return applicationSupport
                .appendingPathComponent("YomiLens", isDirectory: true)
                .appendingPathComponent("saved-vocabulary.json")
        }
    }

    private func sorted(
        _ items: [SavedVocabularyItem]
    ) -> [SavedVocabularyItem] {
        items.sorted { $0.savedAt > $1.savedAt }
    }

    private func snapshot(
        _ items: [SavedVocabularyItem]
    ) -> SavedVocabularySnapshot {
        SavedVocabularySnapshot(revision: revision, items: items)
    }
}
