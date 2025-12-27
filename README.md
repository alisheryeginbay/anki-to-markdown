# AnkiToMarkdown

Swift package to import Anki flashcard decks (.apkg, .colpkg) and export to Markdown.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/alisheryeginbay/AnkiToMarkdown.git", from: "1.0.0"),
]
```

Or in Xcode: File → Add Package Dependencies → paste the URL.

## Usage

```swift
import AnkiToMarkdown

let importer = AnkiImporter()

// Import from file
let url = URL(fileURLWithPath: "/path/to/deck.apkg")
let collection = try importer.importCollection(from: url)

// Access decks (with subdeck hierarchy)
for deck in collection.decks {
    print(deck.name)           // "Parent::Child::Grandchild"
    print(deck.shortName)      // "Grandchild"
    print(deck.isSubdeck)      // true
    print(deck.pathComponents) // ["Parent", "Child", "Grandchild"]
    print(deck.parentPath)     // "Parent::Child" (nil for root decks)
}

// Get root decks and their subdecks
for rootDeck in collection.rootDecks {
    print("Deck: \(rootDeck.name)")
    for subdeck in collection.subdecks(of: rootDeck) {
        print("  - \(subdeck.shortName)")
    }
}

// Access cards grouped by deck
for (deckId, cards) in collection.cardsByDeck {
    if let deck = collection.deck(withId: deckId) {
        print("\(deck.name): \(cards.count) cards")
    }
}

// Access individual cards
for card in collection.cards {
    print(card.front)
    print(card.back)
    print(card.tags)
    print(card.deckId)  // ID of the deck this card belongs to
    print(card.mediaReferences)
}

// Export to directory
try collection.export(to: URL(fileURLWithPath: "/output"))

// Or get markdown string
let markdown = collection.toMarkdown()

// Or get JSON data
let json = try collection.toJSON()

// Access media files
for (filename, data) in collection.mediaFiles {
    // save or process media
}
```

## API

### AnkiImporter

```swift
// Import from file URL
func importCollection(from url: URL) throws -> AnkiCollection

// Import from Data
func importCollection(from data: Data) throws -> AnkiCollection
```

### AnkiCollection

```swift
let decks: [AnkiDeck]
let cards: [AnkiCard]
let mediaFiles: [String: Data]

var deckCount: Int
var cardCount: Int
var mediaCount: Int

// Deck helpers
var cardsByDeck: [Int64: [AnkiCard]]  // Cards grouped by deck ID
var rootDecks: [AnkiDeck]             // Top-level decks (no parent)
func deck(withId id: Int64) -> AnkiDeck?
func subdecks(of deck: AnkiDeck) -> [AnkiDeck]

// Export
func toMarkdown(mediaFolder: String = "media") -> String
func toJSON() throws -> Data
func export(to directory: URL, mediaFolder: String = "media") throws
```

### AnkiDeck

```swift
let id: Int64
let name: String       // Full name like "Parent::Child::Grandchild"

var shortName: String           // Just "Grandchild"
var pathComponents: [String]    // ["Parent", "Child", "Grandchild"]
var parentPath: String?         // "Parent::Child" (nil for root decks)
var isSubdeck: Bool             // true if has "::" in name
```

### AnkiCard

```swift
let id: Int64
let noteId: Int64
let deckId: Int64      // ID of the deck this card belongs to
let fields: [String]
let tags: [String]

var front: String      // First field
var back: String       // Second field
var mediaReferences: [String]  // All referenced media filenames
```

## Output Format

### Markdown

```markdown
## Card

**나**, **저**(polite)

I, me

[🔊 Day 1-01.mp3](media/Day 1-01.mp3)

*Tags: korean, vocabulary*

---
```

### JSON

```json
[
  {
    "id": 1234567890,
    "fields": ["나, 저(polite)", "I, me", "[sound:Day 1-01.mp3]"],
    "tags": ["korean", "vocabulary"]
  }
]
```

## Supported Formats

- `.apkg` - Anki deck package
- `.colpkg` - Anki collection package (full backup)
- Handles zstd compression (Anki 2.1.50+)
- Extracts all media (images, audio, video)

## Requirements

- macOS 14+ / iOS 17+
- Swift 5.9+
