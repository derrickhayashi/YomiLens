import SwiftUI

struct AnkiExportView: View {
    let item: SavedVocabularyItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var noteType: String
    @State private var deck: String
    @State private var selectedMeaning = ""
    @State private var errorMessage: String?

    init(item: SavedVocabularyItem) {
        self.item = item
        _noteType = State(
            initialValue: AnkiSettings.configuredNoteType()
        )
        _deck = State(
            initialValue: AnkiSettings.configuredDeck()
        )
    }

    private var exportContent: AnkiExportContent {
        AnkiExportService.content(
            for: item,
            meaning: selectedMeaning.isEmpty ? nil : selectedMeaning
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Note type", text: $noteType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Deck", text: $deck)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anki destination")
                } footer: {
                    Text("Pre-filled from Settings. Changes here apply only to this export.")
                }

                Section("Card") {
                    LabeledContent("Word", value: exportContent.word)
                    LabeledContent("Reading", value: exportContent.reading)

                    if item.meanings.count > 1 {
                        Picker("Meaning", selection: $selectedMeaning) {
                            ForEach(item.meanings, id: \.self) { meaning in
                                Text(meaning).tag(meaning)
                            }
                        }
                    } else {
                        LabeledContent("Meaning", value: exportContent.meaning)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Example")
                            .foregroundStyle(.secondary)
                        Text(attributedExample)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        addToAnki()
                    } label: {
                        Label("Open in Anki", systemImage: "rectangle.stack.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(
                        noteType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || deck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .navigationTitle("Add to Anki")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if selectedMeaning.isEmpty {
                    selectedMeaning = item.meanings.first ?? ""
                }
            }
        }
    }

    private var attributedExample: AttributedString {
        AnkiExportService.attributedSentenceExample(for: item)
    }

    private func addToAnki() {
        errorMessage = nil
        guard let url = AnkiExportService.addNoteURL(
            for: item,
            noteType: noteType.trimmingCharacters(in: .whitespacesAndNewlines),
            deck: deck.trimmingCharacters(in: .whitespacesAndNewlines),
            meaning: selectedMeaning
        ) else {
            errorMessage = "YomiLens could not create the Anki export."
            return
        }

        openURL(url) { accepted in
            if !accepted {
                errorMessage = "AnkiMobile could not be opened. Make sure it is installed on this iPhone."
            }
        }
    }
}
