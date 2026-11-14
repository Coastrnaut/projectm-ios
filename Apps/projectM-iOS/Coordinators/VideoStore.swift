// VideoStore.swift — the app's one imported video on disk (MED-002-R3 to R8, R17, R18; research
// MED-002-D6, D9; data-model "Stored video").
//
// * Folder `Library/Application Support/Videos` (private to the app, persistent, included in the
//   user's own device backups like imported audio and the photo; spec Privacy review). One file,
//   `<UUID>.mov`: the copy made by `VideoSanitizer` (video pictures and timing only: no soundtrack,
//   no metadata, not re-compressed).
// * The identifier is the UUID string in UserDefaults `settings.video.id`. Resolving it accepts only
//   a canonical UUID and `<UUID>.mov` inside the folder, so no stored value can make the app open a
//   file anywhere else (R18). A missing file or an invalid value reads as "no video" and is cleared.
// * Import: the picked file is copied once into the temporary folder under its security scope and a
//   coordinated read (the picked URL is not kept), then checked and remuxed into the folder; only
//   then the key is set and the previous copy deleted (R6). A failed import changes nothing and
//   leaves no file. No file timestamps or volume capacity are read (required-reason APIs): a full
//   disk surfaces as a failed export (`.saveFailed`).
// FILE-001 splits the import into stage, adopt (from a staging folder) and makeCurrent so a scene
// archive's media are switched together after every check (SceneArchiveService).
// MED-003 (research MED-003-D7): the stored video's loop region is `settings.video.loop` =
// `{id, inMilliseconds, outMilliseconds}`, read only while `id` is the stored video's; a foreign or
// malformed value reads as none and is removed. Remove Video and a new current video remove it.
// FILE-008 (ADR-0043): the folder is content-addressed like the photo's (`ContentAddressedMediaFolder`):
// one `<sha256>.mov` payload per content plus `references.json`; the sanitized copy has zeroed header
// times (`MovieHeaderTimes`), so importing the same movie again adds a reference, not a file. Making a
// video current keeps references sharing its payload; Remove releases every reference to it.
// Sendable; imports run off the main actor (VideoCoordinator).
import Foundation
import LocalPortability
import VideoLayer

struct StoredVideo: Equatable, Sendable {
    let id: UUID
    let url: URL
}

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct VideoStore: @unchecked Sendable {
    static let idKey = "settings.video.id"
    /// MED-003: the stored video's loop region.
    static let loopKey = "settings.video.loop"
    static let fileExtension = "mov"

    let directory: URL
    let defaults: UserDefaults
    let limits: VideoImportLimits

    /// FILE-008: payloads and references.
    let folder: ContentAddressedMediaFolder

    init(directory: URL, defaults: UserDefaults, limits: VideoImportLimits = .standard,
         fault: (@Sendable (ContentAddressedMediaFolder.Step, URL) throws -> Void)? = nil) {
        self.directory = directory
        self.defaults = defaults
        self.limits = limits
        self.folder = ContentAddressedMediaFolder(directory: directory, extensions: [Self.fileExtension], fault: fault)
    }

    /// The folder's name in Application Support (FILE-009 measures it).
    static let folderName = "Videos"

    /// `Library/Application Support/Videos`.
    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// The stored video, or nil (clearing an invalid identifier or one whose file is gone).
    func current() -> StoredVideo? {
        guard let raw = defaults.string(forKey: Self.idKey) else { return nil }
        guard let id = UUID(uuidString: raw), id.uuidString == raw, let url = existingFile(for: id) else {
            defaults.removeObject(forKey: Self.idKey)
            return nil
        }
        return StoredVideo(id: id, url: url)
    }

    /// The copy of `id` inside the folder: a legacy `<UUID>.mov` or its payload (FILE-008).
    func existingFile(for id: UUID) -> URL? {
        folder.resolve(id)
    }

    /// FILE-008-R5: every identifier that resolves.
    func knownIDs() -> [UUID] {
        folder.references()
    }

    /// FILE-008-R5: whether `id` names the same stored movie as the current video.
    func isSameVideo(_ id: UUID, as current: UUID) -> Bool {
        id == current || folder.sharesPayload(id, current)
    }

    /// Imports the video at `source` (a picked file) and makes it the stored video.
    @discardableResult
    func importVideo(at source: URL) async throws(VideoImportError) -> StoredVideo {
        let staged = try await stage(at: source)
        makeCurrent(staged)
        return staged
    }

    /// FILE-001: the checked, remuxed copy of `source` written into this store's folder under a new
    /// identifier, without making it current (the identifier key is not touched). A failure leaves
    /// no file.
    func stage(at source: URL) async throws(VideoImportError) -> StoredVideo {
        let picked = try Self.copyPicked(source, limits: limits)
        defer { try? FileManager.default.removeItem(at: picked) }
        let id = UUID()
        let temp = folder.incomingURL(for: id, extension: Self.fileExtension)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .saveFailed
        }
        do throws(VideoImportError) {
            _ = try await VideoSanitizer.copy(picked, to: temp, limits: limits)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        do {
            let url = try folder.intern(temp, as: id, consumingSource: true)   // FILE-008-R2
            return StoredVideo(id: id, url: url)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw .saveFailed
        }
    }

    /// FILE-001: moves a copy staged by another store (a staging folder) into this folder under the
    /// same identifier, without making it current. FILE-008: an equal payload already here is reused.
    func adopt(_ staged: StoredVideo) throws(VideoImportError) -> StoredVideo {
        guard staged.url.pathExtension == Self.fileExtension else { throw .saveFailed }
        do {
            let url = try folder.intern(staged.url, as: staged.id, consumingSource: true)
            return StoredVideo(id: staged.id, url: url)
        } catch {
            throw .saveFailed
        }
    }

    /// Makes a copy inside this folder the stored video, then releases the previous content (R6).
    /// FILE-008-R4: references sharing the new video's payload stay; at most 32 per payload.
    func makeCurrent(_ video: StoredVideo) {
        let previous = current()
        defaults.set(video.id.uuidString, forKey: Self.idKey)
        if previous?.id != video.id { defaults.removeObject(forKey: Self.loopKey) }   // MED-003: a new video plays whole
        if let previous, previous.id != video.id, !folder.sharesPayload(previous.id, video.id) {
            try? folder.releaseSharing(payloadOf: previous.id, keeping: [video.id])
        }
        try? folder.trim(payloadOf: video.id, keeping: [video.id])
    }

    /// FILE-001: deletes a copy that never became current (staged or adopted, then abandoned). FILE-008:
    /// releases its reference; a payload another reference shares stays.
    func discard(_ video: StoredVideo) {
        guard video.id != current()?.id else { return }
        try? folder.release([video.id])
    }

    /// Deletes the stored copy and its identifier (MED-002-R7). FILE-008: every reference to the current
    /// movie is released, so its payload is deleted.
    func remove() {
        if let raw = defaults.string(forKey: Self.idKey), let id = UUID(uuidString: raw), id.uuidString == raw {
            try? folder.releaseSharing(payloadOf: id)
        }
        defaults.removeObject(forKey: Self.idKey)
        defaults.removeObject(forKey: Self.loopKey)   // MED-003
    }

    // MARK: FILE-008 launch (research FILE-008-D5)

    /// Synchronous: temporary files and already migrated legacy names. Reads no content.
    func prepareFolder() { folder.prepare() }

    /// Off the main thread: migrates legacy copies and collects unreferenced payloads.
    func reconcileFolder() { _ = try? folder.reconcile() }

    // MARK: Loop region (MED-003-R7)

    /// The loop region saved for the video `id` (nil: the whole file). A value for another video or a
    /// malformed one is removed.
    func loopRegion(for id: UUID) -> VideoLoopRegion? {
        guard let stored = defaults.dictionary(forKey: Self.loopKey) else { return nil }
        guard let raw = stored["id"] as? String, raw == id.uuidString,
              let start = stored["inMilliseconds"] as? Int, let end = stored["outMilliseconds"] as? Int,
              start >= 0, end > start else {
            defaults.removeObject(forKey: Self.loopKey)
            return nil
        }
        return VideoLoopRegion(inMilliseconds: start, outMilliseconds: end)
    }

    /// Saves `region` for the video `id`; nil removes it (the whole file).
    func setLoopRegion(_ region: VideoLoopRegion?, for id: UUID) {
        guard let region else {
            defaults.removeObject(forKey: Self.loopKey)
            return
        }
        let value: [String: Any] = ["id": id.uuidString, "inMilliseconds": region.inMilliseconds,
                                    "outMilliseconds": region.outMilliseconds]
        defaults.set(value, forKey: Self.loopKey)
    }

    /// The only place the picked URL is touched: its size is checked, then it is copied once into
    /// the temporary folder under its security scope and a coordinated read. Returns the temporary copy.
    private static func copyPicked(_ source: URL, limits: VideoImportLimits) throws(VideoImportError) -> URL {
        let scoped = source.startAccessingSecurityScopedResource()   // false for URLs that need no scope
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PickedVideos", isDirectory: true)
        let ext = source.pathExtension.isEmpty ? VideoStore.fileExtension : source.pathExtension   // AVFoundation reads the type from it
        let copy = folder.appendingPathComponent(UUID().uuidString, isDirectory: false).appendingPathExtension(ext)
        var result: Result<URL, VideoImportError> = .failure(.unreadable)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges,
                                                         error: &coordinationError) { (readable: URL) in
            guard let size = try? readable.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
            guard Int64(size) <= limits.maxFileBytes else { result = .failure(.tooLarge); return }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: readable, to: copy)
                result = .success(copy)
            } catch {
                result = .failure(.unreadable)
            }
        }
        if coordinationError != nil {
            try? FileManager.default.removeItem(at: copy)
            throw .unreadable
        }
        return try result.get()
    }
}
