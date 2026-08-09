import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isRecognizing = false
    @State private var capturedImage: UIImage?
    @State private var recognizedRegions: [OCRRegion] = []
    @State private var recognizedText = ""
    @State private var tokenization = JapaneseTokenization.empty
    @State private var dictionarySelection: DictionarySelection?
    @State private var learnedEntryIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var isShowingMyList = false
    @State private var isShowingAbout = false
    @State private var passageRenderGeneration = 0

    var body: some View {
        NavigationStack {
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
                                dictionarySelection = selection
                            }
                            .id(passageRenderGeneration)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(recognizedText)

                            Divider()
                                .padding(.vertical, 4)

                            Text("Word breakdown")
                                .font(.headline)

                            TokenListView(
                                tokens: tokenization.tokens,
                                expressions: tokenization.expressions
                            ) { selection in
                                dictionarySelection = selection
                            }

                            Text("\(tokenization.source.label). Blue dashed underlines mark recognized expressions; dotted underlines mark individual words. Particles and punctuation are omitted from the word cards.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !learnedEntryIDs.isEmpty {
                                Label(
                                    "\(learnedEntryIDs.count) word\(learnedEntryIDs.count == 1 ? "" : "s") selected to learn",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.green)
                            }

                            if case .appleNaturalLanguageFallback = tokenization.source {
                                Text("The dictionary failed to load, so readings and parts of speech are unavailable.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                .padding()
            }
            .navigationTitle("YomiLens")
            .onChange(of: recognizedText) { _, newText in
                tokenization = JapaneseTokenizer.tokenize(newText)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }

                // Recreate the Core Text-backed view after suspension so
                // SwiftUI measures it from the same fresh layout it draws.
                passageRenderGeneration += 1
            }
            .sheet(item: $dictionarySelection) { selection in
                DictionaryEntrySheet(
                    selection: selection,
                    learnedEntryIDs: $learnedEntryIDs
                )
            }
            .sheet(isPresented: $isShowingMyList) {
                MyListView(selectedWordCount: learnedEntryIDs.count)
            }
            .sheet(isPresented: $isShowingAbout) {
                SourcesView()
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker(
                    onImagePicked: { image in
                        isShowingCamera = false
                        Task {
                            await recognizeText(in: image)
                        }
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomMenuBar
            }
        }
    }

    private var bottomMenuBar: some View {
        HStack(alignment: .bottom) {
            menuButton(
                title: "My List",
                systemImage: "bookmark"
            ) {
                isShowingMyList = true
            }

            Spacer(minLength: 12)

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
                .frame(width: 96)
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

            Spacer(minLength: 12)

            menuButton(
                title: "About",
                systemImage: "info.circle"
            ) {
                isShowingAbout = true
            }
        }
        .padding(.horizontal, 24)
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
            .frame(width: 88, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openCamera() {
        errorMessage = nil

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            isShowingPhotoLibrary = true
            return
        }

        isShowingCamera = true
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
                return
            }

            await recognizeText(in: image)
        } catch {
            isRecognizing = false
            errorMessage = "Loading the photo failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func recognizeText(in image: UIImage) async {
        capturedImage = image
        recognizedRegions = []
        recognizedText = ""
        tokenization = .empty
        isRecognizing = true
        errorMessage = nil

        defer {
            isRecognizing = false
        }

        do {
            let result = try await OCRService.recognizeJapanese(in: image)
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
    let selectedWordCount: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("My List", systemImage: "bookmark")
            } description: {
                Text("Saved vocabulary will appear here when persistent word lists are added.")
            } actions: {
                if selectedWordCount > 0 {
                    Text("\(selectedWordCount) selected in this session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("My List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
