import SwiftUI

struct DictionaryEntrySheet: View {
    let token: JapaneseToken
    @Binding var learnedEntryIDs: Set<String>

    @Environment(\.dismiss) private var dismiss

    private var entry: DictionaryEntry? {
        DictionaryService.lookup(token)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tokenSummary

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
            .navigationTitle("Word details")
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

    private var tokenSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(token.surface)
                .font(.largeTitle)
                .fontWeight(.semibold)

            if let reading = token.reading {
                Text(reading)
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            if let dictionaryForm = token.dictionaryForm {
                LabeledContent("Dictionary form", value: dictionaryForm)
            }
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
