import SwiftUI

enum AnkiSettings {
    static let noteTypeKey = "anki.noteType"
    static let deckKey = "anki.deck"
    static let defaultNoteType = "Japanese"
    static let defaultDeck = ""

    static func configuredNoteType(
        defaults: UserDefaults = .standard
    ) -> String {
        configuredValue(
            forKey: noteTypeKey,
            fallback: defaultNoteType,
            defaults: defaults
        )
    }

    static func configuredDeck(
        defaults: UserDefaults = .standard
    ) -> String {
        configuredValue(
            forKey: deckKey,
            fallback: defaultDeck,
            defaults: defaults
        )
    }

    private static func configuredValue(
        forKey key: String,
        fallback: String,
        defaults: UserDefaults
    ) -> String {
        guard let value = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return fallback
        }
        return value
    }
}

struct SettingsView: View {
    @AppStorage(AnkiSettings.noteTypeKey)
    private var noteType = AnkiSettings.defaultNoteType
    @AppStorage(AnkiSettings.deckKey)
    private var deck = AnkiSettings.defaultDeck
    @State private var isShowingAbout = false

    var body: some View {
        Form {
            Section {
                TextField("Note type", text: $noteType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Deck", text: $deck)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Anki")
            } footer: {
                Text("Use the exact names shown in Anki. The note type must have fields named Word, Reading, Meaning, and Example.")
            }

            Section("App") {
                Button {
                    isShowingAbout = true
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAbout) {
            SourcesView()
        }
    }
}
