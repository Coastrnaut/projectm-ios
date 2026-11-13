// PhotoStore.swift — the app's one imported photo on disk (MED-001-R3 to R8, R13, R14; research
// MED-001-D9; data-model "StoredPhoto").
//
// * Folder `Library/Application Support/Photos` (private to the app, persistent, included in the
//   user's own device backups like imported audio; spec Clarifications). One file,
//   `<UUID>.png` or `<UUID>.jpg`, the pixels-only copy made by `ImageSanitizer` (no metadata).
// * The identifier is the UUID string in UserDefaults `settings.photo.id`. Resolving it accepts only
//   a canonical UUID and the two names above inside the folder, so no stored value can make the app
//   open a file anywhere else (R14). A missing file or an invalid value reads as "no photo" and the
//   key is cleared.
// * Import: the picked file is read once (its security scope and a coordinated read end before
//   this returns; the URL is not kept), sanitized, written atomically, then the key is set and only
//   then the previous copy deleted (R6). A failed import changes nothing.
// * No file timestamps or volume capacity are read (required-reason APIs; research MED-001-D10): a
//   full disk surfaces as a failed write (`.saveFailed`).
// Synchronous and Sendable: imports run off the main actor (PhotoCoordinator).
import Foundation
import ImageLayer

struct StoredPhoto: Equatable, Sendable {
    let id: UUID
    let url: URL
}

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct PhotoStore: @unchecked Sendable {
    static let idKey = "settings.photo.id"
    static let extensions = ["png", "jpg"]

    let directory: URL
    let defaults: UserDefaults
    let limits: ImageImportLimits

    init(directory: URL, defaults: UserDefaults, limits: ImageImportLimits = .standard) {
        self.directory = directory
        self.defaults = defaults
        self.limits = limits
    }

    /// `Library/Application Support/Photos`.
    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Photos", isDirectory: true)
    }

    /// The stored photo, or nil (clearing an invalid identifier or one whose file is gone).
    func current() -> StoredPhoto? {
        guard let raw = defaults.string(forKey: Self.idKey) else { return nil }
        guard let id = UUID(uuidString: raw), id.uuidString == raw, let url = existingFile(for: id) else {
            defaults.removeObject(forKey: Self.idKey)
            return nil
        }
        return StoredPhoto(id: id, url: url)
    }

    /// The copy of `id` inside the folder, if one exists. Only `<UUID>.png` and `<UUID>.jpg`.
    func existingFile(for id: UUID) -> URL? {
        Self.extensions.lazy.map { directory.appendingPathComponent("\(id.uuidString).\($0)", isDirectory: false) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Imports the image at `source` (a picked file) and makes it the stored photo.
    @discardableResult
    func importImage(at source: URL) throws(ImageImportError) -> StoredPhoto {
        let data = try Self.readPicked(source, limits: limits)
        let copy = try ImageSanitizer.sanitize(data, limits: limits)
        let previous = current()
        let id = UUID()
        let url = directory.appendingPathComponent("\(id.uuidString).\(copy.fileExtension)", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try copy.data.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw .saveFailed
        }
        defaults.set(id.uuidString, forKey: Self.idKey)
        if let previous { deleteFiles(of: previous.id) }
        return StoredPhoto(id: id, url: url)
    }

    /// Deletes the stored copy and its identifier (MED-001-R7).
    func remove() {
        if let raw = defaults.string(forKey: Self.idKey), let id = UUID(uuidString: raw), id.uuidString == raw {
            deleteFiles(of: id)
        }
        defaults.removeObject(forKey: Self.idKey)
    }

    private func deleteFiles(of id: UUID) {
        for ext in Self.extensions {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id.uuidString).\(ext)", isDirectory: false))
        }
    }

    /// The only place the picked URL is touched: a bounded, coordinated read under its security scope.
    private static func readPicked(_ source: URL, limits: ImageImportLimits) throws(ImageImportError) -> Data {
        let scoped = source.startAccessingSecurityScopedResource()   // false for URLs that need no scope
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, ImageImportError> = .failure(.unreadable)
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: .withoutChanges,
                                                         error: &coordinationError) { (readable: URL) in
            do throws(ImageImportError) {
                result = .success(try ImageSanitizer.readBounded(readable, limits: limits))
            } catch {
                result = .failure(error)
            }
        }
        if coordinationError != nil { throw .unreadable }
        return try result.get()
    }
}
