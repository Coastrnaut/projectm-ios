// SceneArchiveWriter.swift — scene + media bytes → archive (FILE-001-R1 to R4, R15; contract §5).
//
// Refuses before writing anything: a scene with validation errors, more than one photo or video
// asset, a photo/video asset without media, media without such an asset, and media that would not
// pass the import's own content check. Writes `scene.json` (canonical), the assets in key order,
// then `manifest.json` (PortableArchive puts every file's length and SHA-256 in it).
import Foundation
import LocalPortability
import ParameterGraph
import SceneFormat

/// One media file packed or read.
public struct SceneArchiveMedia: Sendable, Equatable {
    public var key: String
    public var type: SceneArchiveAssetType
    /// `png`, `jpg` or `mov`.
    public var fileExtension: String
    public var data: Data

    public init(key: String, type: SceneArchiveAssetType, fileExtension: String, data: Data) {
        self.key = key
        self.type = type
        self.fileExtension = fileExtension
        self.data = data
    }

    public var path: String { SceneArchiveFormat.assetPath(key: key, fileExtension: fileExtension) }
}

public enum SceneArchiveWriter {
    /// Streams the archive to `sink` (a file handle in the app, a buffer in tests).
    public static func write(document: SceneDocument, media: [SceneArchiveMedia], registry: ParameterRegistry,
                             modified: Date, limits: SceneArchiveLimits = .standard,
                             sink: @escaping (Data) throws -> Void) throws(SceneArchiveError) {
        let errors = document.validate(registry: registry).filter(\.isError)
        guard errors.isEmpty else { throw .sceneInvalid(errors) }
        let assets = document.mediaAssets
        for type in SceneArchiveAssetType.allCases where assets.filter({ (a: (key: String, type: SceneArchiveAssetType, storeID: String)) -> Bool in a.type == type }).count > 1 {
            throw .tooManyMedia(type)
        }
        var byKey: [String: SceneArchiveMedia] = [:]
        for item in media {
            guard assets.contains(where: { (a: (key: String, type: SceneArchiveAssetType, storeID: String)) -> Bool in a.key == item.key && a.type == item.type }),
                  byKey[item.key] == nil else { throw .mismatch(key: item.key) }
            guard SceneArchiveFormat.allowedExtensions(for: item.type).contains(item.fileExtension) else { throw .wrongContent(item.path) }
            try SceneArchiveContentCheck.check(item.data, path: item.path, type: item.type, fileExtension: item.fileExtension, limits: limits)
            byKey[item.key] = item
        }
        for asset in assets where byKey[asset.key] == nil { throw .missingMedia(key: asset.key) }

        let writer = PortableArchiveWriter(modified: modified, sink: sink)
        do {
            var files = [try writer.add(path: SceneArchiveFormat.scenePath, data: Data(document.encoded()))]
            var records: [SceneArchiveAssetRecord] = []
            for asset in assets {
                guard let item = byKey[asset.key] else { continue }
                files.append(try writer.add(path: item.path, data: item.data))
                records.append(SceneArchiveAssetRecord(key: item.key, type: item.type.rawValue, path: item.path))
            }
            try writer.finish(manifest: try SceneArchiveManifest(files: files, assets: records).encoded())
        } catch {
            throw .writeFailed
        }
    }

    /// The archive as bytes (tests and small scenes).
    public static func data(document: SceneDocument, media: [SceneArchiveMedia], registry: ParameterRegistry,
                            modified: Date, limits: SceneArchiveLimits = .standard) throws(SceneArchiveError) -> Data {
        var out = Data()
        try write(document: document, media: media, registry: registry, modified: modified, limits: limits) { (chunk: Data) in
            out.append(chunk)
        }
        return out
    }
}
