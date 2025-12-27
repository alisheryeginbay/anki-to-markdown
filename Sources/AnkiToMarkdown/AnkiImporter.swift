import Foundation
import SQLite3
import SWCompression
import zstd

// MARK: - Models

public struct AnkiDeck: Identifiable, Sendable, Codable {
    public let id: Int64
    public let name: String

    /// Returns the full path components (e.g., ["Parent", "Child", "Grandchild"])
    public var pathComponents: [String] {
        name.components(separatedBy: "::")
    }

    /// Returns just the deck's own name without parent path
    public var shortName: String {
        pathComponents.last ?? name
    }

    /// Returns the parent deck path, or nil if this is a root deck
    public var parentPath: String? {
        let components = pathComponents
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "::")
    }

    /// Returns true if this is a subdeck
    public var isSubdeck: Bool {
        name.contains("::")
    }
}

public struct AnkiCard: Identifiable, Sendable, Codable {
    public let id: Int64
    public let noteId: Int64
    public let deckId: Int64
    public let fields: [String]
    public let tags: [String]

    public var front: String { fields.first ?? "" }
    public var back: String { fields.count > 1 ? fields[1] : "" }

    public var mediaReferences: [String] {
        var refs: [String] = []
        let allContent = fields.joined(separator: " ")

        // Images: src="filename"
        if let regex = try? NSRegularExpression(pattern: #"src="([^"]+)""#) {
            let range = NSRange(allContent.startIndex..., in: allContent)
            for match in regex.matches(in: allContent, range: range) {
                if let r = Range(match.range(at: 1), in: allContent) {
                    refs.append(String(allContent[r]))
                }
            }
        }

        // Audio: [sound:filename]
        if let regex = try? NSRegularExpression(pattern: #"\[sound:([^\]]+)\]"#) {
            let range = NSRange(allContent.startIndex..., in: allContent)
            for match in regex.matches(in: allContent, range: range) {
                if let r = Range(match.range(at: 1), in: allContent) {
                    refs.append(String(allContent[r]))
                }
            }
        }

        return refs
    }
}

public struct AnkiCollection: Sendable {
    public let decks: [AnkiDeck]
    public let cards: [AnkiCard]
    public let mediaFiles: [String: Data]

    public var deckCount: Int { decks.count }
    public var cardCount: Int { cards.count }
    public var mediaCount: Int { mediaFiles.count }

    /// Returns cards grouped by deck ID
    public var cardsByDeck: [Int64: [AnkiCard]] {
        Dictionary(grouping: cards, by: { $0.deckId })
    }

    /// Returns deck by ID
    public func deck(withId id: Int64) -> AnkiDeck? {
        decks.first { $0.id == id }
    }

    /// Returns root decks (no parent)
    public var rootDecks: [AnkiDeck] {
        decks.filter { !$0.isSubdeck }
    }

    /// Returns subdecks of a given deck
    public func subdecks(of deck: AnkiDeck) -> [AnkiDeck] {
        let prefix = deck.name + "::"
        return decks.filter { $0.name.hasPrefix(prefix) && !$0.name.dropFirst(prefix.count).contains("::") }
    }
}

// MARK: - Importer

public final class AnkiImporter: Sendable {
    
    public enum ImportError: LocalizedError {
        case fileNotFound
        case invalidArchive
        case databaseNotFound
        case decompressionFailed(String)
        case sqliteError(String)
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound: "Anki file not found"
            case .invalidArchive: "Invalid or corrupted archive"
            case .databaseNotFound: "Could not find Anki database in archive"
            case .decompressionFailed(let reason): "Decompression failed: \(reason)"
            case .sqliteError(let reason): "Database error: \(reason)"
            }
        }
    }
    
    public init() {}
    
    public func importCollection(from url: URL) throws -> AnkiCollection {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try unzip(url, to: tempDir)

        let dbData = try extractDatabase(tempDir: tempDir)
        let dbPath = tempDir.appendingPathComponent("collection.sqlite")
        try dbData.write(to: dbPath)

        let decks = try readDecks(from: dbPath)
        let cards = try readCards(from: dbPath)
        let mediaFiles = try extractMedia(tempDir: tempDir)

        return AnkiCollection(decks: decks, cards: cards, mediaFiles: mediaFiles)
    }
    
    public func importCollection(from data: Data) throws -> AnkiCollection {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".anki")
        try data.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        return try importCollection(from: tempFile)
    }
    
    // MARK: - Private
    
    private func unzip(_ archiveURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: archiveURL)
        let entries = try ZipContainer.open(container: data)
        
        for entry in entries {
            guard let entryData = entry.data else { continue }
            let filePath = destination.appendingPathComponent(entry.info.name)
            let parentDir = filePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try entryData.write(to: filePath)
        }
    }
    
    private func extractDatabase(tempDir: URL) throws -> Data {
        let dbNames = ["collection.anki21b", "collection.anki21", "collection.anki2"]
        
        for name in dbNames {
            let dbPath = tempDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dbPath.path) {
                let data = try Data(contentsOf: dbPath)

                // Check if already a valid SQLite database
                if isSQLiteDatabase(data) {
                    return data
                }

                // Try Zstd decompression if it looks compressed
                if isZstdCompressed(data) {
                    if let decompressed = try? decompressZstd(data), isSQLiteDatabase(decompressed) {
                        return decompressed
                    }
                }
            }
        }
        
        throw ImportError.databaseNotFound
    }
    
    private func isZstdCompressed(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x28 && data[1] == 0xB5 && data[2] == 0x2F && data[3] == 0xFD
    }
    
    private func isSQLiteDatabase(_ data: Data) -> Bool {
        guard data.count >= 16 else { return false }
        return String(decoding: data.prefix(6), as: UTF8.self) == "SQLite"
    }
    
    private func decompressZstd(_ data: Data) throws -> Data {
        // Use streaming decompression - handles frames without content size
        let inputStream = InputStream(data: data)
        let outputStream = OutputStream(toMemory: ())

        do {
            try ZStd.decompress(src: inputStream, dst: outputStream)
            guard let decompressed = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
                throw ImportError.decompressionFailed("Failed to read decompressed data")
            }
            return decompressed
        } catch {
            throw ImportError.decompressionFailed(error.localizedDescription)
        }
    }
    
    private func readDecks(from dbPath: URL) throws -> [AnkiDeck] {
        var db: OpaquePointer?

        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw ImportError.sqliteError("Failed to open database")
        }
        defer { sqlite3_close(db) }

        var decks: [AnkiDeck] = []

        // Try new schema first (decks table)
        // Note: New Anki format uses \x1f (unit separator) for hierarchy instead of ::
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT id, name FROM decks", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                var name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                // Convert \x1f separator to :: for consistency with Anki's display format
                name = name.replacingOccurrences(of: "\u{1f}", with: "::")
                decks.append(AnkiDeck(id: id, name: name))
            }
            sqlite3_finalize(stmt)
        }

        // Fallback: old schema (decks stored as JSON in col table)
        if decks.isEmpty {
            if sqlite3_prepare_v2(db, "SELECT decks FROM col", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let decksJson = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                       let data = decksJson.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        for (idStr, deckData) in json {
                            if let id = Int64(idStr),
                               let deckDict = deckData as? [String: Any],
                               let name = deckDict["name"] as? String {
                                decks.append(AnkiDeck(id: id, name: name))
                            }
                        }
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        return decks.sorted { $0.name < $1.name }
    }

    private func readCards(from dbPath: URL) throws -> [AnkiCard] {
        var db: OpaquePointer?

        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw ImportError.sqliteError("Failed to open database")
        }
        defer { sqlite3_close(db) }

        // Build note lookup: noteId -> (fields, tags)
        var notesMap: [Int64: (fields: [String], tags: [String])] = [:]
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, "SELECT id, flds, tags FROM notes", -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let noteId = sqlite3_column_int64(stmt, 0)
            let flds = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let tagsStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            notesMap[noteId] = (
                fields: flds.components(separatedBy: "\u{1f}"),
                tags: tagsStr.split(separator: " ").map(String.init)
            )
        }
        sqlite3_finalize(stmt)

        // Read cards with deck association
        var cards: [AnkiCard] = []
        guard sqlite3_prepare_v2(db, "SELECT id, nid, did FROM cards", -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let cardId = sqlite3_column_int64(stmt, 0)
            let noteId = sqlite3_column_int64(stmt, 1)
            let deckId = sqlite3_column_int64(stmt, 2)

            if let note = notesMap[noteId] {
                cards.append(AnkiCard(
                    id: cardId,
                    noteId: noteId,
                    deckId: deckId,
                    fields: note.fields,
                    tags: note.tags
                ))
            }
        }
        sqlite3_finalize(stmt)

        return cards
    }
    
    private func extractMedia(tempDir: URL) throws -> [String: Data] {
        var mediaFiles: [String: Data] = [:]
        let mediaMap = try parseMediaMapping(tempDir: tempDir)
        
        for (index, filename) in mediaMap {
            let filePath = tempDir.appendingPathComponent(index)
            if FileManager.default.fileExists(atPath: filePath.path) {
                mediaFiles[filename] = try Data(contentsOf: filePath)
            }
        }
        
        return mediaFiles
    }
    
    private func parseMediaMapping(tempDir: URL) throws -> [String: String] {
        let mediaPath = tempDir.appendingPathComponent("media")
        guard FileManager.default.fileExists(atPath: mediaPath.path) else { return [:] }
        
        var data = try Data(contentsOf: mediaPath)
        
        if isZstdCompressed(data), let decompressed = try? decompressZstd(data) {
            data = decompressed
        }

        // Try JSON first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return json
        }
        
        // Parse protobuf format
        return parseProtobufMediaMap(data)
    }
    
    private func parseProtobufMediaMap(_ data: Data) -> [String: String] {
        var mapping: [String: String] = [:]
        let text = String(decoding: data, as: UTF8.self)
        
        guard let regex = try? NSRegularExpression(
            pattern: #"([a-zA-Z0-9_\-\. ]+\.(mp3|png|jpg|jpeg|gif|webp|wav|ogg|mp4|webm|svg))"#
        ) else { return [:] }
        
        let range = NSRange(text.startIndex..., in: text)
        var index = 0
        
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 1), in: text) {
                mapping[String(index)] = String(text[r])
                index += 1
            }
        }
        
        return mapping
    }
}
