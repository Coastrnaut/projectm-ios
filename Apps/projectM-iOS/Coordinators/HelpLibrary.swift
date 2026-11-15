// HelpLibrary.swift — UIX-014 (specs/302-uix-014-offline-help-browser; contract contracts/help-content.md).
//
// The offline help: an index (Resources/Help/index.json) and short Markdown articles, read from the app bundle only.
// * `HelpLibrary`: the index, search over titles and keywords (case- and accent-insensitive, UIX-014-D5), and
//   `article(for:)`, which reads and parses one bundled file (nil when it is missing, UIX-014-R9).
// * `HelpMarkdown`: a line parser for the fixed subset (headings 1-3, paragraphs, "- " bullets, "N. " items,
//   UIX-014-D2). Inline **bold** / *italic* stay in the text and are rendered with inline-only Markdown parsing.
// * `HelpContentRules`: the content rules the tests apply to every article (no links or addresses, no unsupported
//   syntax, no named music services, at most 400 words; UIX-014-R5, R8, S4).
// No networking and no web view (FR-068, UIX-014-R6); nothing is stored (UIX-014-R10).
import Foundation

struct HelpEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let file: String
    let keywords: [String]
}

enum HelpBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(Int, String)
}

struct HelpArticle: Hashable, Sendable {
    let entry: HelpEntry
    let blocks: [HelpBlock]
}

struct HelpLibrary: Sendable {
    static let folder = "Help"

    private struct Index: Decodable {
        let version: Int
        let articles: [HelpEntry]
    }

    let entries: [HelpEntry]
    private let directory: URL

    /// The bundled index, or nil when it is missing, unreadable or empty (UIX-014-R9: "Help is not available.").
    static func bundled(_ bundle: Bundle = .main) -> HelpLibrary? {
        guard let url = bundle.url(forResource: "index", withExtension: "json", subdirectory: folder),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data),
              !index.articles.isEmpty else { return nil }
        return HelpLibrary(entries: index.articles, directory: url.deletingLastPathComponent())
    }

    /// Entries whose title or a keyword contains the trimmed query; all entries, in index order, for an empty query.
    func search(_ query: String) -> [HelpEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entries.filter { (entry: HelpEntry) -> Bool in
            if entry.title.range(of: needle, options: options) != nil { return true }
            return entry.keywords.contains { (keyword: String) -> Bool in keyword.range(of: needle, options: options) != nil }
        }
    }

    func entry(id: String) -> HelpEntry? {
        entries.first { $0.id == id }
    }

    /// The article's raw text from the bundle; nil when the file is missing.
    func text(for entry: HelpEntry) -> String? {
        let url = directory.appendingPathComponent(entry.file)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The parsed article; nil when the file is missing or has no content (UIX-014-R9).
    func article(for entry: HelpEntry) -> HelpArticle? {
        guard let text = text(for: entry) else { return nil }
        let blocks = HelpMarkdown.parse(text)
        return blocks.isEmpty ? nil : HelpArticle(entry: entry, blocks: blocks)
    }
}

enum HelpMarkdown {
    /// Parses the help subset. Consecutive paragraph lines join with a space; a blank line ends a block.
    static func parse(_ text: String) -> [HelpBlock] {
        var blocks: [HelpBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let heading = heading(line) { flush(); blocks.append(heading); continue }
            if line.hasPrefix("- ") { flush(); blocks.append(.bullet(String(line.dropFirst(2)))); continue }
            if let item = numbered(line) { flush(); blocks.append(item); continue }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    private static func heading(_ line: String) -> HelpBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func numbered(_ line: String) -> HelpBlock? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 2, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return .numbered(number, String(rest.dropFirst(2)))
    }

    /// Inline-only Markdown (bold, italic); the plain text when it does not parse.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

enum HelpContentRules {
    static let maximumWords = 400
    /// Addresses, links and syntax the browser does not render (UIX-014-R5, D3; contract rule 4).
    static let forbiddenFragments = ["http://", "https://", "www.", "mailto:", "](", "![", "```", "<"]
    /// No compatibility claims about named music apps or services (UIX-014-R8, CLAUDE.md, FR-031).
    static let forbiddenNames = ["Spotify", "Apple Music", "YouTube", "SoundCloud", "Tidal", "Deezer", "Pandora",
                                 "Amazon Music"]

    /// Every rule an article breaks, as readable messages; empty when it passes.
    static func violations(in text: String, title: String) -> [String] {
        var found: [String] = []
        let lower = text.lowercased()
        for fragment in forbiddenFragments where lower.contains(fragment) { found.append("contains \"\(fragment)\"") }
        for name in forbiddenNames where text.range(of: name, options: .caseInsensitive) != nil { found.append("names \(name)") }
        if text.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }) {
            found.append("has a table row")
        }
        let words = text.split { $0.isWhitespace }.count
        if words > maximumWords { found.append("has \(words) words (at most \(maximumWords))") }
        let blocks = HelpMarkdown.parse(text)
        if blocks.first != .heading(level: 1, text: title) { found.append("does not start with \"# \(title)\"") }
        let topHeadings = blocks.filter { (block: HelpBlock) -> Bool in
            if case .heading(level: 1, text: _) = block { return true }
            return false
        }
        if topHeadings.count != 1 { found.append("has \(topHeadings.count) level-1 headings") }
        if blocks.count < 2 { found.append("has no body") }
        return found
    }
}
