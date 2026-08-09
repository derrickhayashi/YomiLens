import SwiftUI
import UIKit

struct ContentView: View {
    @State private var isShowingCamera = false
    @State private var isRecognizing = false
    @State private var capturedImage: UIImage?
    @State private var recognizedRegions: [OCRRegion] = []
    @State private var recognizedText = ""
    @State private var tokenization = JapaneseTokenization.empty
    @State private var selectedToken: JapaneseToken?
    @State private var learnedEntryIDs: Set<String> = []
    @State private var errorMessage: String?

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
                                tokens: tokenization.tokens
                            ) { token in
                                selectedToken = token
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(recognizedText)

                            Divider()
                                .padding(.vertical, 4)

                            Text("Word breakdown")
                                .font(.headline)

                            TokenListView(tokens: tokenization.tokens) { token in
                                selectedToken = token
                            }

                            Text("\(tokenization.source.label). Tap a dotted word in the passage or a card below for dictionary details. Particles and punctuation are omitted from the word breakdown.")
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

                    Button {
                        openCamera()
                    } label: {
                        Label("Scan Game Text", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRecognizing)
                }
                .padding()
            }
            .navigationTitle("YomiLens")
            .onChange(of: recognizedText) { _, newText in
                tokenization = JapaneseTokenizer.tokenize(newText)
            }
            .sheet(item: $selectedToken) { token in
                DictionaryEntrySheet(
                    token: token,
                    learnedEntryIDs: $learnedEntryIDs
                )
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
        }
    }

    private func openCamera() {
        errorMessage = nil

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "A camera is not available. Run this preview on a physical iPhone."
            return
        }

        isShowingCamera = true
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
