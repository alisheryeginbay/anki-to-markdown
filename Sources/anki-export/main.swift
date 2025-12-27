import Foundation
import AnkiToMarkdown

@main
struct AnkiExport {
    static func main() async throws {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            print("Usage: anki-export <input.colpkg> [output-directory]")
            exit(1)
        }

        let inputPath = args[1]
        let outputPath = args.count >= 3 ? args[2] : "export"

        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            print("Error: File not found: \(inputPath)")
            exit(1)
        }

        print("Importing \(inputPath)...")

        let importer = AnkiImporter()
        let collection = try await importer.importCollection(from: inputURL) { progress in
            switch progress {
            case .extracting:
                print("  Extracting archive...")
            case .readingDecks:
                print("  Reading decks...")
            case .readingCards(let current, let total):
                print("  Reading cards: \(current)/\(total)", terminator: "\r")
                fflush(stdout)
            case .parsingMedia:
                print("\n  Parsing media...")
            }
        }

        print("Found \(collection.deckCount) decks, \(collection.cardCount) cards, \(collection.mediaCount) media files")
        print("Exporting to \(outputPath)...")

        try collection.export(to: outputURL)

        print("Done! Exported to \(outputPath)/")
    }
}
