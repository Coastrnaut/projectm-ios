// SceneArchiveWriter.swift — scene + media bytes → archive (FILE-001-R1 to R4, R15; contract §5).
//
// Refuses before writing anything: a scene with validation errors, more than one photo or video
// asset, a photo/video asset without media, media without such an asset, and media that would not
// pass the import's own content check. Writes `scene.json` (canonical), the assets in key order,
// then `manifest.json` (PortableArchive puts every file's length and SHA-256 in it).
// SCN-014: also the photo asset's slideshow pictures (after the assets, in index order; `slides` in the
// manifest only when there are any), and the path audit refuses a scene or manifest naming a disk location.
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
    public static func write(document: SceneDocument, media: [SceneArchiveMedia], slides: [SceneArchiveSlide] = [],
                             registry: ParameterRegistry, modified: Date, limits: SceneArchiveLimits = .standard,
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
        let orderedSlides = try checkedSlides(slides, document: document, limits: limits)   // SCN-014
        let sceneBytes = Data(document.encoded())
        if let leaked = SceneArchivePathAudit.findings(inJSON: sceneBytes).first { throw .absolutePath(leaked) }   // SCN-014-R2

        let writer = PortableArchiveWriter(modified: modified, sink: sink)
        let manifest: Data
        do {
            var files = [try writer.add(path: SceneArchiveFormat.scenePath, data: sceneBytes)]
            var records: [SceneArchiveAssetRecord] = []
            for asset in assets {
                guard let item = byKey[asset.key] else { continue }
                files.append(try writer.add(path: item.path, data: item.data))
                records.append(SceneArchiveAssetRecord(key: item.key, type: item.type.rawValue, path: item.path))
            }
            var slideRecords: [SceneArchiveSlideRecord] = []
            for slide in orderedSlides {
                files.append(try writer.add(path: slide.path, data: slide.data))
                slideRecords.append(SceneArchiveSlideRecord(key: slide.key, index: slide.index, path: slide.path))
            }
            manifest = try SceneArchiveManifest(files: files, assets: records, slides: slideRecords.isEmpty ? nil : slideRecords).encoded()
        } catch {
            throw .writeFailed
        }
        if let leaked = SceneArchivePathAudit.findings(inJSON: manifest).first { throw .absolutePath(leaked) }
        do {
            try writer.finish(manifest: manifest)
        } catch {
            throw .writeFailed
        }
    }

    /// SCN-014-R3: one picture per slideshow position of each photo asset, PNG or JPEG passing the photo
    /// check; returned in key, then index order.
    static func checkedSlides(_ slides: [SceneArchiveSlide], document: SceneDocument,
                              limits: SceneArchiveLimits) throws(SceneArchiveError) -> [SceneArchiveSlide] {
        var counts: [String: Int] = [:]
        for entry in document.slideStoreIDs { counts[entry.key] = entry.storeIDs.count }
        var seen: Set<String> = []
        for slide in slides {
            let position = slide.key + "#" + String(slide.index)
            guard let count = counts[slide.key], slide.index >= 1, slide.index <= count, !seen.contains(position),
                  SceneArchiveFormat.allowedExtensions(for: .photo).contains(slide.fileExtension) else { throw .slideMismatch(key: slide.key) }
            seen.insert(position)
            try SceneArchiveContentCheck.check(slide.data, path: slide.path, type: .photo, fileExtension: slide.fileExtension, limits: limits)
        }
        for key in counts.keys.sorted() {
            for index in 1...(counts[key] ?? 1) where !seen.contains(key + "#" + String(index)) { throw .missingMedia(key: key) }
        }
        return slides.sorted { (a: SceneArchiveSlide, b: SceneArchiveSlide) -> Bool in
            a.key == b.key ? a.index < b.index : a.key < b.key
        }
    }

    /// The archive as bytes (tests and small scenes).
    public static func data(document: SceneDocument, media: [SceneArchiveMedia], slides: [SceneArchiveSlide] = [],
                            registry: ParameterRegistry, modified: Date, limits: SceneArchiveLimits = .standard) throws(SceneArchiveError) -> Data {
        var out = Data()
        try write(document: document, media: media, slides: slides, registry: registry, modified: modified, limits: limits) { (chunk: Data) in
            out.append(chunk)
        }
        return out
    }
}
