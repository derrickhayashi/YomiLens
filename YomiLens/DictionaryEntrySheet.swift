import SwiftUI

enum DictionarySelection: Identifiable {
    case token(JapaneseToken)
    case expression(JapaneseExpression)

    var id: String {
        switch self {
        case .token(let token):
            "token-\(token.id)"
        case .expression(let expression):
            "expression-\(expression.id)"
        }
    }
}

struct DictionaryEntrySheet: View {
    let selection: DictionarySelection
    @Binding var learnedEntryIDs: Set<String>

    @Environment(\.dismiss) private var dismiss

    private var entry: DictionaryEntry? {
        switch selection {
        case .token(let token):
            DictionaryService.lookup(token)
        case .expression(let expression):
            expression.entry
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    selectionSummary

                    if !DictionaryService.isAvailable {
                        ContentUnavailableView(
                            "Dictionary unavailable",
                            systemImage: "externaldrive.badge.exclamationmark",
                            description: Text("Generate the bundled database with `python3 tools/build_jmdict.py`, then rebuild the app.")
                        )
                    } else if let entry {
                        entryDetails(entry)
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
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(surface)
                .font(.largeTitle)
                .fontWeight(.semibold)

            if let reading {
                Text(reading)
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            if let dictionaryForm {
                LabeledContent("Dictionary form", value: dictionaryForm)
            }
        }
    }

    private var surface: String {
        switch selection {
        case .token(let token): token.surface
        case .expression(let expression): expression.surface
        }
    }

    private var reading: String? {
        switch selection {
        case .token(let token): token.reading
        case .expression(let expression): expression.entry.reading
        }
    }

    private var dictionaryForm: String? {
        switch selection {
        case .token(let token): token.dictionaryForm
        case .expression(let expression): expression.dictionaryForm
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

            Button {
                toggleLearned(entry)
            } label: {
                Label(
                    learnedEntryIDs.contains(entry.id) ? "Added to learning list" : "Learn this word",
                    systemImage: learnedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "plus.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(learnedEntryIDs.contains(entry.id) ? .green : .blue)
            .padding(.top, 8)
        }
    }

    private func toggleLearned(_ entry: DictionaryEntry) {
        if learnedEntryIDs.contains(entry.id) {
            learnedEntryIDs.remove(entry.id)
        } else {
            learnedEntryIDs.insert(entry.id)
        }
    }
}
