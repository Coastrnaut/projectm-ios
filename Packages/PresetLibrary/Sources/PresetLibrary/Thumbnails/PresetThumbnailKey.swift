// PresetThumbnailKey.swift — roadmap PRE-001: the stable ID of a thumbnail (research PRE-001-D3).
// The preset ID, the preset's content hash and the renderer version together name one picture; the
// same three always give the same ID and file, and a changed preset or renderer gives a new one
// (PRE-002 invalidates the old entry by preset ID).
import Foundation
import LocalPortability

public struct PresetThumbnailKey: Sendable, Hashable {
    public let presetID: String
    public let contentHash: String
    public let rendererVersion: Int

    public init(presetID: String, contentHash: String, rendererVersion: Int) {
        self.presetID = presetID
        self.contentHash = contentHash
        self.rendererVersion = rendererVersion
    }

    public init(preset: IndexedPreset, spec: PresetThumbnailSpec = .standard) {
        self.init(presetID: preset.id, contentHash: preset.hash, rendererVersion: spec.rendererVersion)
    }

    /// The first 32 hex digits of SHA-256 over "<presetID>\n<contentHash>\n<rendererVersion>".
    public var stableID: String {
        let text = presetID + "\n" + contentHash + "\n" + String(rendererVersion)
        return String(PortableSHA256.hex(Data(text.utf8)).prefix(32))
    }

    public var fileName: String { stableID + "." + PresetThumbnailIndex.fileExtension }
}
