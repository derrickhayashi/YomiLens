import PhotosUI
import SwiftUI
import UIKit

private enum AppPage: Hashable {
    case myList
    case settings
    case dictionaryDetails(DictionarySelection, sourceText: String)
}

private enum PageScrollTarget: Hashable {
    case readPassage
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var vocabularyStore: SavedVocabularyStore

    @State private var isShowingCamera = false
    @State private var pendingCameraImage: UIImage?
    @State private var isShowingPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var capturedImage: UIImage?
    @State private var recognizedRegions: [OCRRegion] = []
    @State private var recognizedText = ""
    @State private var tokenization = JapaneseTokenization.empty
    @State private var analysisScheduler =
        DebouncedAnalysisScheduler<JapaneseTokenization>()
    @State private var errorMessage: String?
    @State private var navigationPath: [AppPage] = []
    @State private var isWordBreakdownExpanded = false
    @State private var passageRenderGeneration = 0
    @State private var shouldScrollToPassageAfterAnalysis = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 20) {
                    if isRecognizing {
                        ProgressView("Recognizing Japanese…")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let capturedImage {
                        OCRDebugImageView(
                            image: capturedImage,
                            regions: recognizedRegions
                        )

                        Text("Numbers show the order Vision returned the text regions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    TextEditor(text: $recognizedText)
                        .frame(minHeight: 180)
                        .font(.title3)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            if recognizedText.isEmpty && !isRecognizing {
                                Text("Recognized Japanese will appear here.")
                                    .foregroundStyle(.secondary)
                                    .allowsHitTesting(false)
                            }
                        }

                    if !tokenization.tokens.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Read the passage")
                                .font(.headline)

                            FuriganaPassageView(
                                text: recognizedText,
                                spans: tokenization.furiganaSpans,
                                tokens: tokenization.tokens,
                                expressions: tokenization.expressions
                            ) { selection in
                                showDictionaryDetails(selection)
                            }
                            .id(passageRenderGeneration)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(recognizedText)

                            Divider()
                                .padding(.vertical, 4)

                            DisclosureGroup(
                                isExpanded: $isWordBreakdownExpanded
                            ) {
                                TokenListView(
                                    tokens: tokenization.tokens,
                                    expressions: tokenization.expressions
                                ) { selection in
                                    showDictionaryDetails(selection)
                                }

                                Text("\(tokenization.source.label). Blue dashed underlines mark recognized expressions; dotted underlines mark individual words. Particles and punctuation are omitted from the word cards.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            } label: {
                                Text("Word breakdown")
                                    .font(.headline)
                            }

                            if !vocabularyStore.items.isEmpty {
                                Label(
                                    "\(vocabularyStore.items.count) item\(vocabularyStore.items.count == 1 ? "" : "s") saved in My List",
                                    systemImage: "bookmark.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.blue)
                            }

                            if case .appleNaturalLanguageFallback = tokenization.source {
                                Text("The dictionary failed to load, so readings and parts of speech are unavailable.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(PageScrollTarget.readPassage)
                    }

                    }
                    .padding()
                }
            .navigationTitle("YomiLens")
            .onChange(of: recognizedText) { _, newText in
                scheduleAnalysis(for: newText)
            }
            .onChange(of: tokenization.tokens.isEmpty) { _, isEmpty in
                guard !isEmpty,
                      shouldScrollToPassageAfterAnalysis else { return }

                shouldScrollToPassageAfterAnalysis = false
                withAnimation {
                    scrollProxy.scrollTo(
                        PageScrollTarget.readPassage,
                        anchor: .top
                    )
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }

                // Recreate the Core Text-backed view after suspension so
                // SwiftUI measures it from the same fresh layout it draws.
                passageRenderGeneration += 1
            }
            .fullScreenCover(
                isPresented: $isShowingCamera,
                onDismiss: processPendingCameraImage
            ) {
                CameraPicker(
                    onImagePicked: { image in
                        pendingCameraImage = image
                        isShowingCamera = false
                    },
                    onCancel: {
                        isShowingCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $isShowingPhotoLibrary,
                selection: $selectedPhotoItem,
                matching: .images,
                preferredItemEncoding: .automatic
            )
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }

                Task {
                    await loadPhoto(item)
                    selectedPhotoItem = nil
                }
            }
            .navigationDestination(for: AppPage.self) { page in
                switch page {
                case .myList:
                    MyListView { item in
                        navigationPath.append(
                            .dictionaryDetails(
                                .saved(item),
                                sourceText: item.sourceText
                            )
                        )
                    }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            bottomMenuBar
                        }
                case .settings:
                    SettingsView()
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            bottomMenuBar
                        }
                case .dictionaryDetails(let selection, let sourceText):
                    DictionaryEntryView(
                        selection: selection,
                        sourceText: sourceText
                    )
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomMenuBar
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomMenuBar
            }
            }
        }
        .alert(
            "Vocabulary Storage Error",
            isPresented: Binding(
                get: { vocabularyStore.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        vocabularyStore.clearError()
                    }
                }
            )
        ) {
            Button("OK") {
                vocabularyStore.clearError()
            }
        } message: {
            Text(vocabularyStore.errorMessage ?? "Saved vocabulary could not be accessed.")
        }
    }

    private var bottomMenuBar: some View {
        HStack(alignment: .bottom, spacing: 4) {
            menuButton(
                title: "My List",
                systemImage: "bookmark"
            ) {
                navigationPath = [.myList]
            }

            Button {
                openCamera()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.tint, in: Circle())

                    Text("Scan Text")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isRecognizing)
            .opacity(isRecognizing ? 0.5 : 1)
            .contextMenu {
                Button("Choose from Library", systemImage: "photo.on.rectangle") {
                    errorMessage = nil
                    isShowingPhotoLibrary = true
                }
            }


            menuButton(
                title: "Settings",
                systemImage: "gearshape"
            ) {
                navigationPath = [.settings]
            }

        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func menuButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3)

                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openCamera() {
        errorMessage = nil
        pendingCameraImage = nil

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            isShowingPhotoLibrary = true
            return
        }

        isShowingCamera = true
    }

    private func processPendingCameraImage() {
        guard let image = pendingCameraImage else { return }
        pendingCameraImage = nil

        Task {
            await recognizeText(in: image)
        }
    }

    private func showDictionaryDetails(
        _ selection: DictionarySelection
    ) {
        navigationPath.append(
            .dictionaryDetails(
                selection,
                sourceText: recognizedText
            )
        )
    }

    private func scheduleAnalysis(for text: String) {
        guard !text.isEmpty else {
            analysisScheduler.cancel()
            tokenization = .empty
            return
        }

        // Do not leave tappable ranges from the previous text on screen while
        // the user is editing and the next analysis is being debounced.
        tokenization = .empty

        analysisScheduler.schedule(
            text: text,
            delayNanoseconds: 300_000_000,
            analyze: { text in
                await JapaneseAnalysisService.shared.analyze(text)
            },
            receive: { analyzedText, result in
                guard recognizedText == analyzedText else { return }
                tokenization = result
            }
        )
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isRecognizing = true
        errorMessage = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "The selected photo could not be loaded."
                isRecognizing = false
                navigationPath = []
                return
            }

            await recognizeText(in: image)
        } catch {
            isRecognizing = false
            errorMessage = "Loading the photo failed: \(error.localizedDescription)"
            navigationPath = []
        }
    }

    @MainActor
    private func recognizeText(in image: UIImage) async {
        capturedImage = image
        recognizedRegions = []
        recognizedText = ""
        tokenization = .empty
        isWordBreakdownExpanded = false
        shouldScrollToPassageAfterAnalysis = false
        isRecognizing = true
        errorMessage = nil

        defer {
            isRecognizing = false
            // Return after the picker has dismissed and OCR has completed.
            // Popping while presenting the camera can be ignored by SwiftUI.
            navigationPath = []
        }

        do {
            let result = try await OCRService.recognizeJapanese(in: image)
            shouldScrollToPassageAfterAnalysis = !result.text.isEmpty
            recognizedText = result.text
            recognizedRegions = result.regions

            if recognizedText.isEmpty {
                errorMessage = "Vision did not find any text in that photo."
            }
        } catch {
            errorMessage = "OCR failed: \(error.localizedDescription)"
        }
    }
}

private struct MyListView: View {
    @EnvironmentObject private var vocabularyStore: SavedVocabularyStore
    let onSelect: (SavedVocabularyItem) -> Void

    var body: some View {
        Group {
            switch vocabularyStore.state {
            case .loading:
                ProgressView("Loading saved vocabulary…")

            case .failed(let message):
                ContentUnavailableView {
                    Label(
                        "Saved Vocabulary Unavailable",
                        systemImage: "externaldrive.badge.exclamationmark"
                    )
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task {
                            await vocabularyStore.load()
                        }
                    }
                }

            case .ready where vocabularyStore.items.isEmpty:
                ContentUnavailableView {
                    Label("No Saved Vocabulary", systemImage: "bookmark")
                } description: {
                    Text("Tap an underlined word or expression, then save it to My List.")
                }

            case .ready:
                List {
                    ForEach(vocabularyStore.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            savedVocabularyRow(item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task {
                                    await vocabularyStore.remove(item.id)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let itemIDs = offsets.map {
                            vocabularyStore.items[$0].id
                        }
                        Task {
                            await vocabularyStore.remove(Set(itemIDs))
                        }
                    }
                }
            }
        }
        .navigationTitle("My List")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func savedVocabularyRow(
        _ item: SavedVocabularyItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.primaryForm)
                    .font(.headline)

                Spacer()

                Text(item.kind.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(item.reading)
                .font(.subheadline)
                .foregroundStyle(.blue)

            if let meaning = item.meanings.first {
                Text(meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.sourceText.isEmpty {
                Text(item.sourceText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
