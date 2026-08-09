import SwiftUI

struct TokenListView: View {
    let tokens: [JapaneseToken]
    let onSelect: (JapaneseToken) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 88), spacing: 8, alignment: .top)
    ]

    private var sentenceGroups: [[JapaneseToken]] {
        let visibleTokens = tokens.filter {
            $0.partOfSpeech != "particle" && $0.partOfSpeech != "symbol"
        }

        return Dictionary(grouping: visibleTokens, by: \.sentenceGroup)
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(sentenceGroups.enumerated()), id: \.offset) { _, sentenceTokens in
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(sentenceTokens) { token in
                        Button {
                            onSelect(token)
                        } label: {
                            VStack(spacing: 2) {
                                Text(token.reading ?? " ")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)

                                Text(token.surface)
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                if let dictionaryForm = token.dictionaryForm {
                                    Text("→ \(dictionaryForm)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                if let partOfSpeech = token.partOfSpeech {
                                    Text(partOfSpeech)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: token))
                        .accessibilityHint("Opens dictionary details")
                    }
                }
            }
        }
    }

    private func accessibilityLabel(for token: JapaneseToken) -> String {
        var components = ["Token \(token.order): \(token.surface)"]

        if let reading = token.reading {
            components.append("reading: \(reading)")
        }
        if let dictionaryForm = token.dictionaryForm {
            components.append("dictionary form: \(dictionaryForm)")
        }
        if let partOfSpeech = token.partOfSpeech {
            components.append(partOfSpeech)
        }

        return components.joined(separator: ", ")
    }
}
