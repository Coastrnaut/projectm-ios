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
// Sendable; imports run off the main actor (VideoCoordinator).
import Foundation
import VideoLayer

struct StoredVideo: Equatable, Sendable {
    let id: UUID
    let url: URL
}

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct VideoStore: @unchecked Sendable {
    static let idKey = "settings.video.id"
    static let fileExtension = "mov"

    let directory: URL
    let defaults: UserDefaults
    let limits: VideoImportLimits

    init(directory: URL, defaults: UserDefaults, limits: VideoImportLimits = .standard) {
        self.directory = directory
        self.defaults = defaults
        self.limits = limits
    }

    /// `Library/Application Support/Videos`.
    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Videos", isDirectory: true)
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

    /// `<UUID>.mov` inside the folder, if it exists.
    func existingFile(for id: UUID) -> URL? {
        let url = file(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func file(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)", isDirectory: false)
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
        let url = file(for: id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .saveFailed
        }
        do throws(VideoImportError) {
            _ = try await VideoSanitizer.copy(picked, to: url, limits: limits)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return StoredVideo(id: id, url: url)
    }

    /// FILE-001: moves a copy staged by another store (a staging folder) into this folder under the
    /// same name, without making it current. Only `<UUID>.mov` names are accepted.
    func adopt(_ staged: StoredVideo) throws(VideoImportError) -> StoredVideo {
        guard staged.url.lastPathComponent == "\(staged.id.uuidString).\(Self.fileExtension)" else { throw .saveFailed }
        let url = file(for: staged.id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staged.url, to: url)
        } catch {
            throw .saveFailed
        }
        return StoredVideo(id: staged.id, url: url)
    }

    /// Makes a copy inside this folder the stored video, then deletes the previous copy (R6).
    func makeCurrent(_ video: StoredVideo) {
        let previous = current()
        defaults.set(video.id.uuidString, forKey: Self.idKey)
        if let previous, previous.id != video.id { try? FileManager.default.removeItem(at: previous.url) }
    }

    /// FILE-001: deletes a copy that never became current (staged or adopted, then abandoned).
    func discard(_ video: StoredVideo) {
        guard video.id != current()?.id else { return }
        try? FileManager.default.removeItem(at: file(for: video.id))
    }

    /// Deletes the stored copy and its identifier (MED-002-R7).
    func remove() {
        if let raw = defaults.string(forKey: Self.idKey), let id = UUID(uuidString: raw), id.uuidString == raw {
            try? FileManager.default.removeItem(at: file(for: id))
        }
        defaults.removeObject(forKey: Self.idKey)
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
