import SwiftUI

@main
struct YomiLensApp: App {
    @StateObject private var vocabularyStore = SavedVocabularyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vocabularyStore)
        }
    }
}
