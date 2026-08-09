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

                    if let entry {
                        entryDetails(entry)
                    } else {
                        ContentUnavailableView(
                            "Not in the preview dictionary",
                            systemImage: "books.vertical",
                            description: Text("The tokenization worked, but this tiny starter lexicon does not contain this word yet.")
                        )
                    }

                    Text("This preview uses a small built-in lexicon. A full JMdict index will replace it after the interaction is validated.")
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
