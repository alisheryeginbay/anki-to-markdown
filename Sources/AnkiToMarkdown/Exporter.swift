import Foundation

// MARK: - Markdown Export

extension AnkiCollection {
    
    public func toMarkdown(mediaFolder: String = "media") -> String {
        var output = ""
        
        for card in cards {
            output += "## Card\n\n"
            
            for field in card.fields where !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var content = field
                content = content.htmlToMarkdown()
                content = content.convertMediaReferences(mediaFolder: mediaFolder)
                output += content + "\n\n"
            }
            
            if !card.tags.isEmpty {
                output += "*Tags: \(card.tags.joined(separator: ", "))*\n\n"
            }
            
            output += "---\n\n"
        }
        
        return output
    }
    
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(cards)
    }
    
    public func export(to directory: URL, mediaFolder: String = "media") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Markdown
        let markdown = toMarkdown(mediaFolder: mediaFolder)
        try markdown.write(to: directory.appendingPathComponent("cards.md"), atomically: true, encoding: .utf8)
        
        // JSON
        let json = try toJSON()
        try json.write(to: directory.appendingPathComponent("cards.json"))
        
        // Media
        if !mediaFiles.isEmpty {
            let mediaDir = directory.appendingPathComponent(mediaFolder)
            try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
            
            for (filename, data) in mediaFiles {
                try data.write(to: mediaDir.appendingPathComponent(filename))
            }
        }
    }
}

// MARK: - String Helpers

extension String {
    
    func htmlToMarkdown() -> String {
        var text = self
        
        // Bold
        text = text.replacingOccurrences(of: #"<b>([^<]*)</b>"#, with: "**$1**", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<strong>([^<]*)</strong>"#, with: "**$1**", options: .regularExpression)
        
        // Italic
        text = text.replacingOccurrences(of: #"<i>([^<]*)</i>"#, with: "*$1*", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<em>([^<]*)</em>"#, with: "*$1*", options: .regularExpression)
        
        // Line breaks
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        
        // Entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        
        // Strip remaining tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        
        return text
    }
    
    func convertMediaReferences(mediaFolder: String) -> String {
        var text = self
        
        // Images
        text = text.replacingOccurrences(
            of: #"<img[^>]*src="([^"]*)"[^>]*>"#,
            with: "![](\(mediaFolder)/$1)",
            options: .regularExpression
        )
        
        // Audio
        text = text.replacingOccurrences(
            of: #"\[sound:([^\]]*)\]"#,
            with: "[🔊 $1](\(mediaFolder)/$1)",
            options: .regularExpression
        )
        
        return text
    }
}
