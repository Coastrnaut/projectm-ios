// ScenePackImporter.swift — adding a scene pack's scene to the show (SCN-014-R5 to R8, R10; research
// SCN-014-D3 to D5; contract specs/187-scn-014-dependency-pack/contracts/scene-pack.md P4).
//
// * `preview(at:)` is the dry run: the picked file is copied once into a staging folder (its security
//   scope and a coordinated read, as FILE-001), read and verified by `SceneArchiveReader` (FILE-002
//   checksums, PRE-014 entry names, content checks), the scene's media identifiers are replaced by ones
//   derived from the pack's bytes (`mediaID`), and FILE-004 plans the install against the stored show with
//   Keep both. SCN-012's entries are computed against the stores plus the pack's media. Nothing outside
//   the staging folder is written; the folder is removed.
// * `adoptMedia(at:preview:)` re-reads the file (its SHA-256 must equal the preview's), stages every file
//   through its store's own import path in a staging store (a picture that is already a pixels-only copy is
//   kept byte for byte, `ScenePackPicture`), then adopts each copy into the real folder (FILE-008: an equal
//   payload is stored once). Nothing becomes current. It returns the identifiers that
//   were new, so `release(_:)` can undo exactly those when the scene install is refused.
// * The install itself is `ShowCoordinator.installImportedScene` (main actor), between the two.
// No networking; nothing from a pack is executed. Runs off the main actor.
import Foundation
import ImageLayer
import LocalPortability
import ParameterGraph
import SceneArchive
import SceneFormat
import ShowControl
import ShowStorage
import VideoLayer

/// What importing a pack would do (data-model "Pack preview").
struct ScenePackPreview: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case refused(String)
        /// The scene is added under its own ID.
        case new
        /// The ID is taken: the scene is added as a copy under a new ID with this name.
        case copy(String)
        /// The same scene (same media) is already in the show: nothing to add.
        case identical
    }

    let archiveSHA256: String
    let status: Status
    let sceneName: String
    let photoCount: Int
    let slideCount: Int
    let logoCount: Int
    let videoCount: Int
    let totalBytes: Int
    /// The scene with the derived media identifiers (nil when refused).
    let document: SceneDocument?
    let showPlan: ShowSceneImportPlan?
    let repairEntries: [SceneRepairReport.Entry]
    /// Packs carry only the user's own media: always empty.
    let licenses: [String]

    var canImport: Bool {
        switch status {
        case .new, .copy: true
        case .refused, .identical: false
        }
    }

    static func refused(_ message: String, sha256: String = "") -> ScenePackPreview {
        ScenePackPreview(archiveSHA256: sha256, status: .refused(message), sceneName: "", photoCount: 0, slideCount: 0, logoCount: 0,
                         videoCount: 0, totalBytes: 0, document: nil, showPlan: nil, repairEntries: [], licenses: [])
    }
}

/// The media an import added to the folders (released again when the scene install is refused).
struct ScenePackAdoption: Sendable, Equatable {
    var newPhotoIDs: Set<UUID> = []
    var newVideoIDs: Set<UUID> = []
}

struct ScenePackImporter: Sendable {
    let archive: SceneArchiveService
    let show: ShowStore

    /// SCN-014-D3: `derivedUUID("SCN-014|<role>|<index>|<sha256>")`; role photo, slide, logo or video.
    static func mediaID(role: String, index: Int, data: Data) -> UUID {
        ShowSceneImportPlanner.derivedUUID("SCN-014|" + role + "|" + String(index) + "|" + PortableSHA256.hex(data))
    }

    /// The derived identifiers of a pack's media: asset key → ID, and photo asset key → slide IDs in order.
    static func identifiers(for contents: SceneArchiveContents) -> (media: [String: UUID], slides: [String: [UUID]]) {
        var media: [String: UUID] = [:]
        for item in contents.media { media[item.key] = mediaID(role: item.type.rawValue, index: 0, data: item.data) }
        var slides: [String: [UUID]] = [:]
        for slide in contents.slides { slides[slide.key, default: []].append(mediaID(role: "slide", index: slide.index, data: slide.data)) }
        return (media, slides)
    }

    static func remapped(_ contents: SceneArchiveContents) -> SceneDocument {
        let ids = identifiers(for: contents)
        return contents.document
            .remappingStoreIDs(ids.media.mapValues { (id: UUID) -> String in id.uuidString })
            .remappingSlideIDs(ids.slides.mapValues { (list: [UUID]) -> [String] in list.map(\.uuidString) })
    }

    /// Whether an earlier import of this pack stored it as a FILE-004 copy (the copy's derived scene IDs, in
    /// order, hold `document` under that ID and the copy's name): re-importing then adds nothing (SCN-014-S3).
    static func hasStoredCopy(of document: SceneDocument, in show: ShowStore) -> Bool {
        let sha = PortableSHA256.hex(document.encoded())
        var tried: Set<String> = []
        for _ in 0..<8 {
            let id = ShowSceneImportPlanner.derivedSceneID(incomingID: document.id, contentSHA256: sha, avoiding: tried)
            tried.insert(id)
            guard let stored = try? show.scene(id).document else { continue }
            if let copy = try? document.duplicated(newID: id, name: stored.name), copy.encoded() == stored.encoded() { return true }
        }
        return false
    }

    /// Reads and verifies the picked pack (a copy in `staging`).
    private func read(_ source: URL, staging: URL) throws(SceneArchiveServiceError) -> (sha256: String, contents: SceneArchiveContents) {
        let data = try archive.readPicked(source, staging: staging)
        do {
            return (PortableSHA256.hex(data), try SceneArchiveReader.read(data, registry: archive.registry, limits: archive.limits))
        } catch {
            throw .archive(error)
        }
    }

    // MARK: Dry run (R5)

    func preview(at source: URL) async -> ScenePackPreview {
        let staging = archive.newStagingFolder()
        defer { try? FileManager.default.removeItem(at: staging) }
        let sha256: String
        let contents: SceneArchiveContents
        do throws(SceneArchiveServiceError) {
            (sha256, contents) = try read(source, staging: staging)
        } catch {
            return .refused(error.message)
        }
        let document = Self.remapped(contents)
        let plan = show.planSceneImport([document], defaultChoice: .keepBoth)
        if let refusal = plan.refusal { return .refused(refusal.message, sha256: sha256) }
        guard let entry = plan.entries.first else { return .refused(ShowSceneImportText.nothingToInstall, sha256: sha256) }
        let status: ScenePackPreview.Status
        if entry.kind == .identical || (entry.isConflict && Self.hasStoredCopy(of: document, in: show)) {
            status = .identical
        } else if let action = entry.install, action.sceneID != document.id {
            status = .copy(action.name)
        } else {
            status = .new
        }
        // SCN-012 after the import: the stores now plus the pack's media.
        let ids = Self.identifiers(for: contents)
        var photos = archive.availability().photos
        var videos = archive.availability().videos
        for item in contents.media {
            guard let id = ids.media[item.key]?.uuidString else { continue }
            if item.type == .video { videos.insert(id) } else { photos.insert(id) }
        }
        for list in ids.slides.values { photos.formUnion(list.map(\.uuidString)) }
        let decodeOnly = contents.warnings.filter { (issue: SceneIssue) -> Bool in issue.code == .valueClamped || issue.code == .droppedField }
        let report = SceneRepairReport(document: document, decodeWarnings: decodeOnly, registry: archive.registry,
                                       assets: StoredMediaAvailability(photos: photos, videos: videos))
        var total = 0
        for item in contents.media { total += item.data.count }
        for slide in contents.slides { total += slide.data.count }
        let count: (SceneArchiveAssetType) -> Int = { (type: SceneArchiveAssetType) -> Int in
            contents.media.filter { (item: SceneArchiveMedia) -> Bool in item.type == type }.count
        }
        return ScenePackPreview(archiveSHA256: sha256, status: status, sceneName: contents.document.name, photoCount: count(.photo),
                                slideCount: contents.slides.count, logoCount: count(.logo), videoCount: count(.video), totalBytes: total,
                                document: document, showPlan: plan, repairEntries: report.entries, licenses: [])
    }

    // MARK: Media (R6, R7)

    /// Stages and adopts the pack's media under the derived identifiers. Throws `.planChanged` when the
    /// file is not the previewed one; any failure leaves the folders as they were.
    func adoptMedia(at source: URL, preview: ScenePackPreview) async throws(SceneArchiveServiceError) -> ScenePackAdoption {
        guard preview.canImport else { throw .planChanged }
        let staging = archive.newStagingFolder()
        defer { try? FileManager.default.removeItem(at: staging) }
        let (sha256, contents) = try read(source, staging: staging)
        guard sha256 == preview.archiveSHA256, Self.remapped(contents) == preview.document else { throw .planChanged }
        let ids = Self.identifiers(for: contents)
        let photos = archive.photos, videos = archive.videos
        let stagingPhotos = PhotoStore(directory: staging.appendingPathComponent("Photos", isDirectory: true), defaults: photos.defaults,
                                       limits: photos.limits)
        let stagingVideos = VideoStore(directory: staging.appendingPathComponent("Videos", isDirectory: true), defaults: videos.defaults,
                                       limits: videos.limits)
        let incoming = staging.appendingPathComponent("Incoming", isDirectory: true)
        var stagedPhotos: [StoredPhoto] = []
        var stagedVideos: [StoredVideo] = []
        for item in contents.media {
            guard let id = ids.media[item.key] else { continue }
            let file = try write(item.data, name: "\(item.key).\(item.fileExtension)", into: incoming)
            switch item.type {
            case .photo:
                do throws(ImageImportError) { stagedPhotos.append(try stagingPhotos.stage(at: file, id: id, keepingCleanOriginal: true)) } catch {
                    throw .media(path: item.path, message: error.message)
                }
            case .logo:
                do throws(ImageImportError) { stagedPhotos.append(try LogoStore(photos: stagingPhotos).stage(at: file, id: id, keepingCleanOriginal: true)) } catch {
                    throw .media(path: item.path, message: LogoImport.message(for: error))
                }
            case .video:
                do throws(VideoImportError) { stagedVideos.append(try await stagingVideos.stage(at: file, id: id)) } catch {
                    throw .media(path: item.path, message: error.message)
                }
            }
        }
        for slide in contents.slides {
            guard let id = ids.slides[slide.key]?[slide.index - 1] else { continue }
            stagedPhotos.append(try archive.stageSlide(slide, into: stagingPhotos, incoming: incoming, id: id,
                                                         keepingCleanOriginal: true))
        }
        // Adopt; remember which identifiers are new so a refusal releases only those.
        var adoption = ScenePackAdoption()
        do {
            for staged in stagedPhotos {
                let isNew = photos.existingFile(for: staged.id) == nil
                _ = try photos.adopt(staged)
                if isNew { adoption.newPhotoIDs.insert(staged.id) }
            }
            for staged in stagedVideos {
                let isNew = videos.existingFile(for: staged.id) == nil
                _ = try videos.adopt(staged)
                if isNew { adoption.newVideoIDs.insert(staged.id) }
            }
        } catch {
            release(adoption)
            throw .saveFailed
        }
        return adoption
    }

    /// Releases the identifiers an import added (a payload another reference shares stays).
    func release(_ adoption: ScenePackAdoption) {
        try? archive.photos.folder.release(adoption.newPhotoIDs)
        try? archive.videos.folder.release(adoption.newVideoIDs)
    }

    private func write(_ data: Data, name: String, into folder: URL) throws(SceneArchiveServiceError) -> URL {
        let file = folder.appendingPathComponent(name, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            throw .saveFailed
        }
        return file
    }
}
