import Foundation

// The production matcher only needs these four properties. This lightweight
// stand-in lets the Python regression suite compile DictionaryService.swift as
// a macOS command-line executable without importing the iOS tokenizer.
struct JapaneseToken {
    let surface: String
    let reading: String?
    let dictionaryForm: String?
    let partOfSpeech: String?
}

@main
struct DictionaryMatchingHarness {
    static func main() {
        guard CommandLine.arguments.count == 6,
              let database = DictionaryDatabase(
                databaseURL: URL(fileURLWithPath: CommandLine.arguments[1])
              ) else {
            exit(2)
        }

        func optionalArgument(_ index: Int) -> String? {
            let value = CommandLine.arguments[index]
            return value == "-" ? nil : value
        }

        let token = JapaneseToken(
            surface: CommandLine.arguments[2],
            reading: optionalArgument(3),
            dictionaryForm: optionalArgument(4),
            partOfSpeech: optionalArgument(5)
        )
        guard let entry = database.lookup(token) else {
            print("NO_MATCH")
            return
        }

        print([
            entry.id,
            entry.headword,
            entry.reading,
            entry.partOfSpeech,
            entry.meanings.first ?? ""
        ].joined(separator: "\t"))
    }
}
