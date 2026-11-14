// SceneArchiveReader.swift — archive bytes → scene + media, or one refusal (FILE-001-R6 to R9, R14;
// contract §4, §6).
//
// Order: size → PortableArchive (ZIP checks, the manifest's shape against
// `SceneArchiveFormat.manifestSchema` before any decoding (FILE-007), manifest header, every file's length and SHA-256,
// unlisted files) → the manifest's `scene` and `assets` (types, unique keys, at most one photo and
// one video, exact `assets/<key>.<ext>` paths) → files (scene present, every asset file listed,
// nothing else) → SCN-001 decode and validation (errors refuse; no store availability here) →
// records against the scene's photo/video assets → each asset's content check. The scene is migrated in
// memory by SCN-013's chain (`migrator`); the archive is never rewritten. Nothing is
// written; the caller stages the media through its stores.
// SCN-014: optional `slides` records (the photo asset's slideshow pictures) are checked for exact paths,
// one picture per slideshow position, and the photo content check.
import Foundation
import LocalPortability
import ParameterGraph
import SceneFormat

public struct SceneArchiveContents: Sendable {
    public let document: SceneDocument
    /// In key order.
    public let media: [SceneArchiveMedia]
    /// SCN-014: the photo asset's slideshow pictures, in key then index order (empty without slides).
    public var slides: [SceneArchiveSlide] = []
    /// SCN-001 decode and validation warnings (missing-asset warnings are not checked here).
    public let warnings: [SceneIssue]
}

public enum SceneArchiveReader {
    /// `migrator` is the app's chain; tests pass synthetic chains (QA-004 migration matrix, as ShowStore and
    /// the autosave store do for SCN-013).
    public static func read(_ data: Data, registry: ParameterRegistry,
                            limits: SceneArchiveLimits = .standard,
                            migrator: SceneMigrator = .standard) throws(SceneArchiveError) -> SceneArchiveContents {
        guard data.count <= limits.maxArchiveBytes else { throw .archiveTooLarge(limit: limits.maxArchiveBytes) }
        let contents: PortableArchiveContents
        do {
            contents = try PortableArchive.read(data, schema: SceneArchiveFormat.manifestSchema.capped(atBytes: limits.maxManifestBytes),
                                                limits: limits.portable)
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

        // SCN-014: slide records (key, 1-based index, exact path); checked against the scene below.
        let slideRecords = try slideRecords(manifest.slides ?? [])

        // Files: the scene, the asset files, the slides, nothing else.
        guard let sceneData = contents.files[SceneArchiveFormat.scenePath] else { throw .missingScene }
        let assetPaths = Set(records.values.map(\.path)).union(slideRecords.map(\.path))
        for record in contents.records where record.path != SceneArchiveFormat.scenePath && !assetPaths.contains(record.path) {
            throw .unexpectedFile(record.path)
        }
        for key in records.keys.sorted() where contents.files[records[key]!.path] == nil {
            throw .missingAssetFile(records[key]!.path)
        }
        for record in slideRecords where contents.files[record.path] == nil { throw .missingAssetFile(record.path) }

        // Scene (SCN-001).
        let decoded: SceneDecodeResult
        do {
            decoded = try SceneDocument.decode([UInt8](sceneData), migrator: migrator)
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
        // SCN-014: every slideshow position of the scene has exactly one picture, and nothing else.
        var expected: [String: Int] = [:]
        for entry in document.slideStoreIDs { expected[entry.key] = entry.storeIDs.count }
        var found: [String: Int] = [:]
        for record in slideRecords { found[record.key, default: 0] += 1 }
        for key in Set(expected.keys).union(found.keys).sorted() where expected[key] != found[key] {
            throw .slideMismatch(key: key)
        }
        var slides: [SceneArchiveSlide] = []
        for record in slideRecords {
            guard let bytes = contents.files[record.path] else { throw .missingAssetFile(record.path) }
            guard record.index <= (expected[record.key] ?? 0) else { throw .slideMismatch(key: record.key) }
            try SceneArchiveContentCheck.check(bytes, path: record.path, type: .photo, fileExtension: record.ext, limits: limits)
            slides.append(SceneArchiveSlide(key: record.key, index: record.index, fileExtension: record.ext, data: bytes))
        }
        var result = SceneArchiveContents(document: document, media: media, warnings: decoded.warnings + issues)
        result.slides = slides
        return result
    }

    /// SCN-014-R4: valid keys, indexes 1…20 once per key, the exact path for PNG or JPEG; key then index order.
    static func slideRecords(_ list: [SceneArchiveSlideRecord]) throws(SceneArchiveError) -> [(key: String, index: Int, ext: String, path: String)] {
        guard list.count <= SceneArchiveFormat.maximumSlides else { throw .malformedManifest("more than \(SceneArchiveFormat.maximumSlides) slides") }
        var result: [(key: String, index: Int, ext: String, path: String)] = []
        var seen: Set<String> = []
        for record in list {
            guard SceneDocument.isValidAssetKey(record.key) else { throw .malformedManifest("invalid slide key") }
            guard record.index >= 1, record.index <= SceneArchiveFormat.maximumSlides,
                  seen.insert(record.key + "#" + String(record.index)).inserted else { throw .malformedManifest("slide \(record.index) of \"\(record.key)\"") }
            guard let ext = SceneArchiveFormat.allowedExtensions(for: .photo).first(where: { (e: String) -> Bool in
                record.path == SceneArchiveFormat.slidePath(key: record.key, index: record.index, fileExtension: e)
            }) else { throw .malformedManifest("slide \(record.index) of \"\(record.key)\" has the path \(record.path)") }
            result.append((record.key, record.index, ext, record.path))
        }
        return result.sorted { (a: (key: String, index: Int, ext: String, path: String), b: (key: String, index: Int, ext: String, path: String)) -> Bool in
            a.key == b.key ? a.index < b.index : a.key < b.key
        }
    }
}
