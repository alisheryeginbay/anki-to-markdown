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

// Access cards
for card in collection.cards {
    print(card.front)
    print(card.back)
    print(card.tags)
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
let cards: [AnkiCard]
let mediaFiles: [String: Data]

var cardCount: Int
var mediaCount: Int

// Export
func toMarkdown(mediaFolder: String = "media") -> String
func toJSON() throws -> Data
func export(to directory: URL, mediaFolder: String = "media") throws
```

### AnkiCard

```swift
let id: Int64
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

- macOS 13+ / iOS 16+
- Swift 5.9+
