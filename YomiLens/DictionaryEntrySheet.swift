import SwiftUI

enum DictionarySelection: Identifiable {
    case token(JapaneseToken)
    case expression(JapaneseExpression)
    case saved(SavedVocabularyItem)

    var id: String {
        switch self {
        case .token(let token):
            "token-\(token.id)"
        case .expression(let expression):
            "expression-\(expression.id)"
        case .saved(let item):
            "saved-\(item.id)"
        }
    }
}

struct DictionaryEntrySheet: View {
    let selection: DictionarySelection
    let sourceText: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vocabularyStore: SavedVocabularyStore

    init(selection: DictionarySelection, sourceText: String = "") {
        self.selection = selection
        self.sourceText = sourceText
    }

    private var entry: DictionaryEntry? {
        switch selection {
        case .token(let token):
            DictionaryService.lookup(token)
        case .expression(let expression):
            expression.entry
        case .saved(let item):
            item.dictionaryEntry
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    selectionSummary

                    if let entry {
                        entryDetails(entry)
                    } else if !DictionaryService.isAvailable {
                        ContentUnavailableView(
                            "Dictionary unavailable",
                            systemImage: "externaldrive.badge.exclamationmark",
                            description: Text("Generate the bundled database with `python3 tools/build_jmdict.py`, then rebuild the app.")
                        )
                    } else {
                        ContentUnavailableView(
                            "No JMdict entry found",
                            systemImage: "books.vertical",
                            description: Text("The tokenizer found this word, but the bundled JMdict release has no matching written form, reading, or lemma.")
                        )
                    }

                    Text(DictionaryService.sourceDescription.map { "Offline dictionary: \($0)." } ?? "The offline JMdict database is not bundled in this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var navigationTitle: String {
        switch selection {
        case .token:
            "Word details"
        case .expression:
            "Expression details"
        case .saved(let item):
            item.kind == .expression
                ? "Expression details"
                : "Word details"
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(primaryForm)
                .font(.largeTitle)
                .fontWeight(.semibold)

            if let reading {
                Text(reading)
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            if primaryForm != surface {
                LabeledContent("Form in passage", value: surface)
            }
        }
    }

    private var primaryForm: String {
        dictionaryForm ?? surface
    }

    private var surface: String {
        switch selection {
        case .token(let token): token.surface
        case .expression(let expression): expression.surface
        case .saved(let item): item.surfaceForm
        }
    }

    private var reading: String? {
        switch selection {
        case .token(let token): entry?.reading ?? token.reading
        case .expression(let expression): expression.entry.reading
        case .saved(let item): item.reading
        }
    }

    private var dictionaryForm: String? {
        switch selection {
        case .token(let token): token.dictionaryForm
        case .expression(let expression): expression.dictionaryForm
        case .saved(let item): item.dictionaryForm
        }
    }

    @ViewBuilder
    private func entryDetails(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            LabeledContent("Headword", value: entry.headword)
            LabeledContent("Reading", value: entry.reading)
            LabeledContent("Part of speech", value: entry.partOfSpeech)

            Text("Meanings")
                .font(.headline)
                .padding(.top, 4)

            ForEach(Array(entry.meanings.enumerated()), id: \.offset) { index, meaning in
                Text("\(index + 1). \(meaning)")
            }

            if let savedSourceText {
                Divider()
                    .padding(.top, 4)

                Text("Source passage")
                    .font(.headline)

                Text(savedSourceText)
                    .textSelection(.enabled)
            }

            if let savedItem {
                Button {
                    toggleSaved(savedItem)
                } label: {
                    Label(
                        vocabularyStore.contains(savedItem.id)
                            ? "Remove from My List"
                            : "Save to My List",
                        systemImage: vocabularyStore.contains(savedItem.id)
                            ? "bookmark.slash.fill"
                            : "bookmark.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(
                    vocabularyStore.contains(savedItem.id)
                        ? .red
                        : .blue
                )
                .padding(.top, 8)
            }
        }
    }

    private var savedItem: SavedVocabularyItem? {
        guard let entry else { return nil }

        if case .saved(let item) = selection {
            return item
        }

        let kind: SavedVocabularyKind
        switch selection {
        case .token:
            kind = .word
        case .expression:
            kind = .expression
        case .saved(let item):
            return item
        }

        return SavedVocabularyItem(
            id: [entry.id, entry.headword, entry.reading]
                .joined(separator: "|"),
            dictionaryEntryID: entry.id,
            kind: kind,
            primaryForm: primaryForm,
            headword: entry.headword,
            surfaceForm: surface,
            dictionaryForm: dictionaryForm,
            reading: entry.reading,
            partOfSpeech: entry.partOfSpeech,
            meanings: entry.meanings,
            sourceText: sourceText,
            savedAt: Date()
        )
    }

    private var savedSourceText: String? {
        guard case .saved(let item) = selection else { return nil }
        let text = item.sourceText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return text.isEmpty ? nil : text
    }

    private func toggleSaved(_ item: SavedVocabularyItem) {
        if vocabularyStore.contains(item.id) {
            vocabularyStore.remove(item.id)
        } else {
            vocabularyStore.add(item)
        }
    }
}
