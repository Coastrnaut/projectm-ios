// GoldenManifest.swift — one platform class's golden list (QA-002-R6; data-model "GoldenManifest").
// Canonical JSON (sorted keys, pretty printed, trailing newline) so a re-record that changes nothing
// rewrites identical bytes.
import Foundation

public struct GoldenManifestEntry: Sendable, Equatable, Codable {
    public var scene: String
    public var frame: Int
    public var width: Int
    public var height: Int
    public var file: String
    /// SHA-256 of the RGBA pixels (what is compared).
    public var pixelSHA256: String
    /// SHA-256 of the PNG file (what the integrity check reads without decoding).
    public var fileSHA256: String
    public var osSensitive: Bool

    public init(scene: String, frame: Int, width: Int, height: Int, file: String, pixelSHA256: String, fileSHA256: String,
                osSensitive: Bool) {
        self.scene = scene
        self.frame = frame
        self.width = width
        self.height = height
        self.file = file
        self.pixelSHA256 = pixelSHA256
        self.fileSHA256 = fileSHA256
        self.osSensitive = osSensitive
    }
}

public struct GoldenManifest: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1
    public static let fileName = "manifest.json"

    public var formatVersion: Int
    public var platform: String
    /// "major.minor" of the OS the goldens were last recorded on (text scenes compare only there).
    public var recordedOS: String
    /// Informational: the GPU of the last recording.
    public var recordedGPU: String
    public var entries: [GoldenManifestEntry]

    public init(platform: String, recordedOS: String, recordedGPU: String, entries: [GoldenManifestEntry] = []) {
        formatVersion = Self.currentFormatVersion
        self.platform = platform
        self.recordedOS = recordedOS
        self.recordedGPU = recordedGPU
        self.entries = entries
    }

    public func entry(scene: String, width: Int, frame: Int) -> GoldenManifestEntry? {
        entries.first { (e: GoldenManifestEntry) -> Bool in e.scene == scene && e.width == width && e.frame == frame }
    }

    /// Inserts or replaces the entry with the same scene, width and frame; keeps canonical order.
    public mutating func upsert(_ entry: GoldenManifestEntry) {
        entries.removeAll { (e: GoldenManifestEntry) -> Bool in e.scene == entry.scene && e.width == entry.width && e.frame == entry.frame }
        entries.append(entry)
        sortEntries()
    }

    /// Canonical order: scene, then width, then frame.
    public mutating func sortEntries() {
        entries.sort { (a: GoldenManifestEntry, b: GoldenManifestEntry) -> Bool in
            if a.scene != b.scene { return a.scene < b.scene }
            if a.width != b.width { return a.width < b.width }
            return a.frame < b.frame
        }
    }

    public func encoded() throws -> Data {
        var copy = self
        copy.sortEntries()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(copy)
        data.append(0x0A)
        return data
    }

    public static func decode(_ data: Data) throws -> GoldenManifest {
        try JSONDecoder().decode(GoldenManifest.self, from: data)
    }
}
