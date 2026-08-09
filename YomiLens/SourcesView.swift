import SwiftUI

struct SourcesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Dictionary") {
                    LabeledContent(
                        "Release",
                        value: DictionaryService.sourceDescription
                            ?? "Database unavailable"
                    )

                    Text(DictionaryService.attribution)

                    Link(
                        DictionaryService.licenseName,
                        destination: DictionaryService.licenseURL
                    )
                }

                Section("Runtime") {
                    Text("Japanese OCR uses Apple Vision. Tokenization, readings, and lemmas use MeCab with IPADic.")
                }
            }
            .navigationTitle("Sources")
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
