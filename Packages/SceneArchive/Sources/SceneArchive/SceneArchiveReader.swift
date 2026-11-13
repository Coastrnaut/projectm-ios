// SceneArchiveReader.swift — archive bytes → scene + media, or one refusal (FILE-001-R6 to R9, R14;
// contract §4, §6).
//
// Order: size → PortableArchive (ZIP checks, manifest header, every file's length and SHA-256,
// unlisted files) → the manifest's `scene` and `assets` (types, unique keys, at most one photo and
// one video, exact `assets/<key>.<ext>` paths) → files (scene present, every asset file listed,
// nothing else) → SCN-001 decode and validation (errors refuse; no store availability here) →
// records against the scene's photo/video assets → each asset's content check. Nothing is
// written; the caller stages the media through its stores.
import Foundation
import LocalPortability
import ParameterGraph
import SceneFormat

public struct SceneArchiveContents: Sendable {
    public let document: SceneDocument
    /// In key order.
    public let media: [SceneArchiveMedia]
    /// SCN-001 decode and validation warnings (missing-asset warnings are not checked here).
    public let warnings: [SceneIssue]
}

public enum SceneArchiveReader {
    public static func read(_ data: Data, registry: ParameterRegistry,
                            limits: SceneArchiveLimits = .standard) throws(SceneArchiveError) -> SceneArchiveContents {
        guard data.count <= limits.maxArchiveBytes else { throw .archiveTooLarge(limit: limits.maxArchiveBytes) }
        let contents: PortableArchiveContents
        do {
            contents = try PortableArchive.read(data, format: SceneArchiveFormat.formatName,
                                                supportedVersion: SceneArchiveFormat.currentVersion, limits: limits.portable)
        } catch let error as PortableArchiveError {
            throw .archive(error)
        } catch {
            throw .archive(.malformedManifest)
        }

        // Manifest: scene and asset records.
        guard let manifest = try? JSONDecoder().decode(SceneArchiveManifest.self, from: contents.manifest) else {
            throw .malformedManifest("scene or assets missing")
        }
        guard manifest.scene == SceneArchiveFormat.scenePath else { throw .malformedManifest("scene is not \(SceneArchiveFormat.scenePath)") }
        var records: [String: (type: SceneArchiveAssetType, ext: String, path: String)] = [:]
        var counts: [SceneArchiveAssetType: Int] = [:]
        for record in manifest.assets {
            guard let type = SceneArchiveAssetType(rawValue: record.type) else { throw .malformedManifest("unknown asset type \"\(record.type)\"") }
            guard SceneDocument.isValidAssetKey(record.key) else { throw .malformedManifest("invalid asset key") }
            guard records[record.key] == nil else { throw .malformedManifest("asset \"\(record.key)\" listed twice") }
            guard let ext = SceneArchiveFormat.allowedExtensions(for: type).first(where: { (e: String) -> Bool in
                record.path == SceneArchiveFormat.assetPath(key: record.key, fileExtension: e)
            }) else { throw .malformedManifest("asset \"\(record.key)\" has the path \(record.path)") }
            counts[type, default: 0] += 1
            if counts[type, default: 0] > 1 { throw .tooManyMedia(type) }
            records[record.key] = (type, ext, record.path)
        }

        // Files: the scene, the asset files, nothing else.
        guard let sceneData = contents.files[SceneArchiveFormat.scenePath] else { throw .missingScene }
        let assetPaths = Set(records.values.map(\.path))
        for record in contents.records where record.path != SceneArchiveFormat.scenePath && !assetPaths.contains(record.path) {
            throw .unexpectedFile(record.path)
        }
        for key in records.keys.sorted() where contents.files[records[key]!.path] == nil {
            throw .missingAssetFile(records[key]!.path)
        }

        // Scene (SCN-001).
        let decoded: SceneDecodeResult
        do {
            decoded = try SceneDocument.decode([UInt8](sceneData))
        } catch {
            throw .sceneRefused(error)
        }
        let document = decoded.document
        let issues = document.validate(registry: registry)
        let errors = issues.filter(\.isError)
        guard errors.isEmpty else { throw .sceneInvalid(errors) }

        // Records against the scene's photo/video assets, both ways.
        let assets = document.mediaAssets
        for asset in assets {
            guard let record = records[asset.key], record.type == asset.type else { throw .mismatch(key: asset.key) }
        }
        for key in records.keys.sorted() where !assets.contains(where: { (a: (key: String, type: SceneArchiveAssetType, storeID: String)) -> Bool in a.key == key }) {
            throw .mismatch(key: key)
        }

        // Content of each asset.
        var media: [SceneArchiveMedia] = []
        for asset in assets {
            guard let record = records[asset.key], let bytes = contents.files[record.path] else { throw .mismatch(key: asset.key) }
            try SceneArchiveContentCheck.check(bytes, path: record.path, type: record.type, fileExtension: record.ext, limits: limits)
            media.append(SceneArchiveMedia(key: asset.key, type: record.type, fileExtension: record.ext, data: bytes))
        }
        return SceneArchiveContents(document: document, media: media, warnings: decoded.warnings + issues)
    }
}
