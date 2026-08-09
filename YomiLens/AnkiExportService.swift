import Foundation

struct AnkiExportContent: Equatable {
    let word: String
    let reading: String
    let meaning: String
    let exampleHTML: String
}

enum AnkiExportService {
    private static let sentenceEndings = CharacterSet(
        charactersIn: "。！？!?"
    )
    private static let sentenceClosers = CharacterSet(
        charactersIn: "」』】）)]}”’"
    )

    static func content(
        for item: SavedVocabularyItem,
        meaning: String? = nil
    ) -> AnkiExportContent {
        AnkiExportContent(
            word: item.primaryForm,
            reading: item.reading,
            meaning: meaning ?? item.meanings.first ?? "",
            exampleHTML: sentenceExampleHTML(for: item)
        )
    }

    static func addNoteURL(
        for item: SavedVocabularyItem,
        noteType: String,
        deck: String,
        meaning: String? = nil
    ) -> URL? {
        let export = content(for: item, meaning: meaning)
        var components = URLComponents()
        components.scheme = "anki"
        components.host = "x-callback-url"
        components.path = "/addnote"
        components.queryItems = [
            URLQueryItem(name: "type", value: noteType),
            URLQueryItem(name: "deck", value: deck),
            URLQueryItem(name: "fldWord", value: htmlEscaped(export.word)),
            URLQueryItem(name: "fldReading", value: htmlEscaped(export.reading)),
            URLQueryItem(name: "fldMeaning", value: htmlEscaped(export.meaning)),
            URLQueryItem(name: "fldExample", value: export.exampleHTML)
        ]
        return components.url
    }

    static func sentenceExampleHTML(
        for item: SavedVocabularyItem
    ) -> String {
        let source = item.sourceText as NSString
        guard source.length > 0,
              let selectedRange = selectedRange(for: item, in: source) else {
            return htmlEscaped(item.sourceText)
        }

        var sentenceStart = 0
        if selectedRange.location > 0 {
            for index in stride(
                from: selectedRange.location - 1,
                through: 0,
                by: -1
            ) {
                if isMember(source.character(at: index), of: sentenceEndings) {
                    sentenceStart = index + 1
                    break
                }
            }
        }
        while sentenceStart < selectedRange.location,
              isMember(
                  source.character(at: sentenceStart),
                  of: sentenceClosers
              ) {
            sentenceStart += 1
        }

        var sentenceEnd = source.length
        if NSMaxRange(selectedRange) < source.length {
            for index in NSMaxRange(selectedRange)..<source.length {
                guard isMember(
                    source.character(at: index),
                    of: sentenceEndings
                ) else { continue }

                sentenceEnd = index + 1
                while sentenceEnd < source.length,
                      isMember(
                          source.character(at: sentenceEnd),
                          of: sentenceClosers
                      ) {
                    sentenceEnd += 1
                }
                break
            }
        }

        let sentenceRange = trimmedRange(
            NSRange(
                location: sentenceStart,
                length: sentenceEnd - sentenceStart
            ),
            in: source
        )
        guard sentenceRange.location <= selectedRange.location,
              NSMaxRange(sentenceRange) >= NSMaxRange(selectedRange) else {
            return htmlEscaped(source.substring(with: sentenceRange))
        }

        let relativeSelection = NSRange(
            location: selectedRange.location - sentenceRange.location,
            length: selectedRange.length
        )
        let sentence = source.substring(with: sentenceRange) as NSString
        let before = sentence.substring(
            with: NSRange(location: 0, length: relativeSelection.location)
        )
        let selected = sentence.substring(with: relativeSelection)
        let afterStart = NSMaxRange(relativeSelection)
        let after = sentence.substring(
            with: NSRange(
                location: afterStart,
                length: sentence.length - afterStart
            )
        )

        return htmlEscaped(before)
            + "<b>" + htmlEscaped(selected) + "</b>"
            + htmlEscaped(after)
    }

    static func attributedSentenceExample(
        for item: SavedVocabularyItem
    ) -> AttributedString {
        let markdown = sentenceExampleHTML(for: item)
            .replacingOccurrences(of: "<b>", with: "**")
            .replacingOccurrences(of: "</b>", with: "**")

        return (try? AttributedString(markdown: markdown))
            ?? AttributedString(item.sourceText)
    }

    private static func selectedRange(
        for item: SavedVocabularyItem,
        in source: NSString
    ) -> NSRange? {
        if let location = item.sourceLocation,
           let length = item.sourceLength {
            let storedRange = NSRange(location: location, length: length)
            if storedRange.location >= 0,
               NSMaxRange(storedRange) <= source.length,
               source.substring(with: storedRange) == item.surfaceForm {
                return storedRange
            }
        }

        let found = source.range(of: item.surfaceForm)
        return found.location == NSNotFound ? nil : found
    }

    private static func trimmedRange(
        _ range: NSRange,
        in source: NSString
    ) -> NSRange {
        var lowerBound = range.location
        var upperBound = NSMaxRange(range)
        let whitespace = CharacterSet.whitespacesAndNewlines

        while lowerBound < upperBound,
              isMember(source.character(at: lowerBound), of: whitespace) {
            lowerBound += 1
        }
        while upperBound > lowerBound,
              isMember(source.character(at: upperBound - 1), of: whitespace) {
            upperBound -= 1
        }

        return NSRange(
            location: lowerBound,
            length: upperBound - lowerBound
        )
    }

    private static func isMember(
        _ utf16CodeUnit: unichar,
        of characterSet: CharacterSet
    ) -> Bool {
        guard let scalar = UnicodeScalar(utf16CodeUnit) else { return false }
        return characterSet.contains(scalar)
    }

    private static func htmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
