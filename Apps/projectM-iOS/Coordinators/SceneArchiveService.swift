// SceneArchiveService.swift — exports a scene with its photo and video as a `.pmscene` archive and
// imports one into the stores, all or nothing (FILE-001-R4 to R12, R15; research FILE-001-D5, D7,
// D8; contracts/scene-archive.md §5-6).
//
// * Export: media come only from `PhotoStore`/`VideoStore` by the scene's store UUIDs (never a user
//   file outside the stores, never a path); the archive is written to
//   `tmp/SceneArchiveExport/projectM-iOS Scene <date>.pmscene`, which `cleanUpExport()` removes
//   (leftovers are cleared before each export). The screen that hands it to Files or Share is SCN-014.
// * Import: the picked file's size is checked, then it is copied once into a per-import staging
//   folder under its security scope and a coordinated read (the picked URL is not kept), read by
//   `SceneArchiveReader` (every refusal), its media staged through stores rooted in the staging
//   folder (the normal MED-001/MED-002/MED-014 import path), the scene's store IDs remapped and
//   validated against the staged copies; only then are the copies moved into the real stores and
//   the identifiers switched (previous copies deleted). Any failure before the switch leaves the
//   stores as they were; the staging folder is removed in every case.
// * Checksums (FILE-002): the reader verifies every entry's CRC-32, listed size and SHA-256 before
//   anything is staged; the optional `observer` sees `.verified` and then each store step, so tests
//   prove that a tampered archive runs no stage, adopt or make-current step (ADR-0029 amendment).
// No networking; nothing from an archive is executed. Runs off the main actor.
import Foundation
import ImageLayer
import ParameterGraph
import ProceduralMaterials
import SceneArchive
import SceneFormat
import VideoLayer
import VisualParameters

struct SceneArchiveImportResult: Sendable {
    /// The scene with its photo/video store IDs remapped to the copies now in the stores.
    let document: SceneDocument
    let photo: StoredPhoto?
    let video: StoredVideo?
    /// Whether a previous stored photo/video was replaced (FILE-003 shows this before confirming).
    let replacedPhoto: Bool
    let replacedVideo: Bool
    /// SCN-001 decode and validation warnings.
    let warnings: [SceneIssue]
    /// SCN-012-R11: the scene's repair report against the stores after the import (the SCN-014 import
    /// screen shows it before the scene opens).
    let repairReport: SceneRepairReport
}

/// One step of an import, in order (FILE-002-R5; contracts/archive-checksums.md C3). Only `.adopted`
/// and `.madeCurrent` touch the real stores; `.staged` writes into the per-import staging folder.
enum SceneArchiveImportStep: Sendable, Equatable {
    /// The reader accepted the archive: checksums, sizes, records, scene and content checks.
    case verified
    /// An archive media file went through a staging store's import (archive path).
    case staged(String)
    case adopted(SceneArchiveAssetType)
    case madeCurrent(SceneArchiveAssetType)
}

struct SceneArchiveExport: Sendable, Equatable {
    let url: URL
    var fileName: String { url.lastPathComponent }
}

enum SceneArchiveServiceError: Error, Sendable, Equatable {
    case archive(SceneArchiveError)
    /// The picked file could not be read.
    case unreadable
    /// The store's import refused an asset's bytes (MED-001/MED-002/MED-014), with its message.
    case media(path: String, message: String)
    /// A staging or commit write failed.
    case saveFailed
    /// After remapping, references still do not resolve (should not happen; kept as a guard).
    case unresolved([SceneIssue])

    var message: String {
        switch self {
        case let .archive(error): error.message
        case .unreadable: "The scene archive could not be read."
        case let .media(path, message): "\(path) in the archive was not imported: \(message)"
        case .saveFailed: "The scene's media could not be saved."
        case let .unresolved(issues): "The scene's media could not be linked: " + issues.map(\.message).joined(separator: " ")
        }
    }
}

/// Which photo and video identifiers exist (SCN-001 `SceneAssetAvailability`).
struct StoredMediaAvailability: SceneAssetAvailability {
    let photos: Set<String>
    let videos: Set<String>

    func containsPhoto(storeID: String) -> Bool { photos.contains(storeID) }
    func containsVideo(storeID: String) -> Bool { videos.contains(storeID) }
}

struct SceneArchiveService: Sendable {
    static let exportFolderName = "SceneArchiveExport"
    static let stagingFolderName = "SceneArchiveImport"

    let photos: PhotoStore
    let videos: VideoStore
    let registry: ParameterRegistry
    /// The temporary directory (tests pass their own).
    let temporaryRoot: URL
    let limits: SceneArchiveLimits
    /// Sees each import step (tests); nil in the app.
    let observer: (@Sendable (SceneArchiveImportStep) -> Void)?

    init(photos: PhotoStore, videos: VideoStore, registry: ParameterRegistry,
         temporaryRoot: URL = FileManager.default.temporaryDirectory, limits: SceneArchiveLimits = .standard,
         observer: (@Sendable (SceneArchiveImportStep) -> Void)? = nil) {
        self.photos = photos
        self.videos = videos
        self.registry = registry
        self.temporaryRoot = temporaryRoot
        self.limits = limits
        self.observer = observer
    }

    /// The visual catalog plus the material catalog, as scenes are validated (SCN-001).
    static func appRegistry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors)
    }

    /// "projectM-iOS Scene 2026-11-13.pmscene": the local date, no scene, device or user name.
    static func exportFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "projectM-iOS Scene \(formatter.string(from: date)).\(SceneArchiveFormat.fileExtension)"
    }

    var exportFolder: URL { temporaryRoot.appendingPathComponent(Self.exportFolderName, isDirectory: true) }

    // MARK: - Export

    func export(_ document: SceneDocument, modified: Date = Date()) throws(SceneArchiveServiceError) -> SceneArchiveExport {
        var media: [SceneArchiveMedia] = []
        for asset in document.mediaAssets {
            guard let id = UUID(uuidString: asset.storeID), id.uuidString == asset.storeID else {
                throw .archive(.missingMedia(key: asset.key))
            }
            let file: URL? = switch asset.type {
            case .photo: photos.existingFile(for: id)
            case .video: videos.existingFile(for: id)
            }
            guard let file, let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { throw .archive(.missingMedia(key: asset.key)) }
            media.append(SceneArchiveMedia(key: asset.key, type: asset.type, fileExtension: file.pathExtension, data: data))
        }
        cleanUpExport()
        let url = exportFolder.appendingPathComponent(Self.exportFileName(for: modified), isDirectory: false)
        let handle: FileHandle
        do {
            try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw SceneArchiveError.writeFailed }
            handle = try FileHandle(forWritingTo: url)
        } catch {
            cleanUpExport()
            throw .saveFailed
        }
        do throws(SceneArchiveError) {
            try SceneArchiveWriter.write(document: document, media: media, registry: registry, modified: modified, limits: limits) { (chunk: Data) in
                try handle.write(contentsOf: chunk)
            }
            try? handle.close()
        } catch {
            try? handle.close()
            cleanUpExport()
            throw .archive(error)
        }
        return SceneArchiveExport(url: url)
    }

    /// Removes the exported file (call when the hand-off ends, done or cancelled).
    func cleanUpExport() {
        try? FileManager.default.removeItem(at: exportFolder)
    }

    // MARK: - Import

    func importArchive(at source: URL) async throws(SceneArchiveServiceError) -> SceneArchiveImportResult {
        let staging = temporaryRoot.appendingPathComponent(Self.stagingFolderName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            throw .saveFailed
        }
        let copy = try copyPicked(source, into: staging)
        guard let data = try? Data(contentsOf: copy, options: .mappedIfSafe) else { throw .unreadable }
        let contents: SceneArchiveContents
        do {
            contents = try SceneArchiveReader.read(data, registry: registry, limits: limits)
        } catch {
            throw .archive(error)
        }
        observer?(.verified)

        // Stage every asset through the stores' own import path, in a store rooted in staging.
        let stagingPhotos = PhotoStore(directory: staging.appendingPathComponent("Photos", isDirectory: true), defaults: photos.defaults, limits: photos.limits)
        let stagingVideos = VideoStore(directory: staging.appendingPathComponent("Videos", isDirectory: true), defaults: videos.defaults, limits: videos.limits)
        let incoming = staging.appendingPathComponent("Incoming", isDirectory: true)
        var stagedPhoto: StoredPhoto?
        var stagedVideo: StoredVideo?
        var storeIDs: [String: String] = [:]
        for item in contents.media {
            let file = incoming.appendingPathComponent("\(item.key).\(item.fileExtension)", isDirectory: false)
            do {
                try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
                try item.data.write(to: file, options: .atomic)
            } catch {
                throw .saveFailed
            }
            switch item.type {
            case .photo:
                do throws(ImageImportError) {
                    let staged = try stagingPhotos.stage(at: file)
                    observer?(.staged(item.path))
                    stagedPhoto = staged
                    storeIDs[item.key] = staged.id.uuidString
                } catch {
                    throw .media(path: item.path, message: error.message)
                }
            case .video:
                do throws(VideoImportError) {
                    let staged = try await stagingVideos.stage(at: file)
                    observer?(.staged(item.path))
                    stagedVideo = staged
                    storeIDs[item.key] = staged.id.uuidString
                } catch {
                    throw .media(path: item.path, message: error.message)
                }
            }
        }

        // Remap and check every reference against the staged copies before touching the stores.
        let document = contents.document.remappingStoreIDs(storeIDs)
        let staged = StoredMediaAvailability(photos: Set([stagedPhoto?.id.uuidString].compactMap { $0 }),
                                             videos: Set([stagedVideo?.id.uuidString].compactMap { $0 }))
        let unresolved = document.validate(registry: registry, assets: staged)
            .filter { (issue: SceneIssue) -> Bool in issue.isError || issue.code == .missingAsset }
        guard unresolved.isEmpty else { throw .unresolved(unresolved) }

        // Commit: move the copies in (undo on failure), then switch the identifiers.
        var adoptedPhoto: StoredPhoto?
        var adoptedVideo: StoredVideo?
        do {
            if let stagedPhoto {
                adoptedPhoto = try photos.adopt(stagedPhoto)
                observer?(.adopted(.photo))
            }
            if let stagedVideo {
                adoptedVideo = try videos.adopt(stagedVideo)
                observer?(.adopted(.video))
            }
        } catch {
            if let adoptedPhoto { photos.discard(adoptedPhoto) }
            if let adoptedVideo { videos.discard(adoptedVideo) }
            throw .saveFailed
        }
        let replacedPhoto = adoptedPhoto != nil && photos.current() != nil
        let replacedVideo = adoptedVideo != nil && videos.current() != nil
        if let adoptedPhoto {
            photos.makeCurrent(adoptedPhoto)
            observer?(.madeCurrent(.photo))
        }
        if let adoptedVideo {
            videos.makeCurrent(adoptedVideo)
            observer?(.madeCurrent(.video))
        }
        let decodeOnly = contents.warnings.filter { (issue: SceneIssue) -> Bool in
            issue.code == .valueClamped || issue.code == .droppedField
        }
        let report = SceneRepairReport(document: document, decodeWarnings: decodeOnly, registry: registry, assets: availability())
        return SceneArchiveImportResult(document: document, photo: adoptedPhoto, video: adoptedVideo,
                                        replacedPhoto: replacedPhoto, replacedVideo: replacedVideo, warnings: contents.warnings,
                                        repairReport: report)
    }

    /// Which stored photo and video exist now (for validating an imported scene).
    func availability() -> StoredMediaAvailability {
        StoredMediaAvailability(photos: Set([photos.current()?.id.uuidString].compactMap { $0 }),
                                videos: Set([videos.current()?.id.uuidString].compactMap { $0 }))
    }

    /// The only place the picked URL is touched: its size is checked against the archive limit, then
    /// it is copied once into `folder` under its security scope and a coordinated read.
    private func copyPicked(_ source: URL, into folder: URL) throws(SceneArchiveServiceError) -> URL {
        let scoped = source.startAccessingSecurityScopedResource()   // false for URLs that need no scope
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let copy = folder.appendingPathComponent("picked.\(SceneArchiveFormat.fileExtension)", isDirectory: false)
        let limit = limits.maxArchiveBytes
        var result: Result<URL, SceneArchiveServiceError> = .failure(.unreadable)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges,
                                                         error: &coordinationError) { (readable: URL) in
            guard let size = try? readable.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
            guard size <= limit else { result = .failure(.archive(.archiveTooLarge(limit: limit))); return }
            do {
                try FileManager.default.copyItem(at: readable, to: copy)
                result = .success(copy)
            } catch {
                result = .failure(.unreadable)
            }
        }
        if coordinationError != nil { throw .unreadable }
        return try result.get()
    }
}
