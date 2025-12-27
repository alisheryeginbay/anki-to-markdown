import Foundation
import SQLite3
import SWCompression
import zstd

// MARK: - Models

public struct AnkiCard: Identifiable, Sendable, Codable {
    public let id: Int64
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
    public let cards: [AnkiCard]
    public let mediaFiles: [String: Data]
    
    public var cardCount: Int { cards.count }
    public var mediaCount: Int { mediaFiles.count }
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
        
        let cards = try readCards(from: dbPath)
        let mediaFiles = try extractMedia(tempDir: tempDir)
        
        return AnkiCollection(cards: cards, mediaFiles: mediaFiles)
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
        do {
            return try ZStd.decompress(data)
        } catch {
            throw ImportError.decompressionFailed(error.localizedDescription)
        }
    }
    
    private func readCards(from dbPath: URL) throws -> [AnkiCard] {
        var db: OpaquePointer?
        
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            throw ImportError.sqliteError("Failed to open database")
        }
        defer { sqlite3_close(db) }
        
        var cards: [AnkiCard] = []
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, "SELECT id, flds, tags FROM notes", -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.sqliteError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let flds = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let tagsStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            
            cards.append(AnkiCard(
                id: id,
                fields: flds.components(separatedBy: "\u{1f}"),
                tags: tagsStr.split(separator: " ").map(String.init)
            ))
        }
        
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
        
        if isZstdCompressed(data) {
            data = try decompressZstd(data)
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
