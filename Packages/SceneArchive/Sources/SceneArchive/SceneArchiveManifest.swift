// SceneArchiveManifest.swift — `manifest.json` of a scene archive (FILE-001-R2, R14; data-model
// "SceneArchiveManifest", "SceneArchiveAssetRecord"; contract §2).
//
// The generic header (`format`, `formatVersion`, `files` with SHA-256 and length) is PortableArchive's
// and checked by it; this layer adds `scene` and `assets`.
import Foundation
import LocalPortability

public struct SceneArchiveAssetRecord: Codable, Sendable, Equatable {
    public var key: String
    /// `photo` or `video`; kept as text so an unknown type is reported, not a decode failure.
    public var type: String
    public var path: String

    public init(key: String, type: String, path: String) {
        self.key = key
        self.type = type
        self.path = path
    }
}

public struct SceneArchiveManifest: Codable, Sendable, Equatable {
    public var format: String
    public var formatVersion: Int
    public var files: [PortableFileRecord]
    public var scene: String
    public var assets: [SceneArchiveAssetRecord]

    public init(files: [PortableFileRecord], assets: [SceneArchiveAssetRecord]) {
        format = SceneArchiveFormat.formatName
        formatVersion = SceneArchiveFormat.currentVersion
        self.files = files
        scene = SceneArchiveFormat.scenePath
        self.assets = assets
    }

    /// Sorted keys, no white space, `/` unescaped.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
