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
// * FILE-001 splits the import into stage (sanitized copy under a new identifier, not current),
//   adopt (move a staged copy in from a staging folder) and makeCurrent, so a scene archive's photo
//   and video are switched together only after every check passed (SceneArchiveService).
// * No file timestamps or volume capacity are read (required-reason APIs; research MED-001-D10): a
//   full disk surfaces as a failed write (`.saveFailed`).
// * FILE-008 (ADR-0043): the folder is content-addressed (`ContentAddressedMediaFolder`): the copy is
//   stored once as `<sha256>.png|jpg` and `references.json` maps each identifier to it, so importing
//   the same picture again (or adopting it from a scene archive) adds a reference, not a second file.
//   Making a photo current keeps references that share its payload (scenes and cues naming them still
//   find the picture) and releases the previous content; Remove releases every reference to the
//   current content, so its bytes leave the device. Legacy `<UUID>.png|jpg` files still resolve and are
//   migrated at launch (`prepareFolder`, `reconcileFolder`).
// * MED-006-R11: the image slideshow's pictures are references in this folder too; making a photo current,
//   trimming and Remove keep them (`SlideshowStore.protectedIDs`), even when they share the photo's picture.
// Synchronous and Sendable: imports run off the main actor (PhotoCoordinator).
import Foundation
import ImageLayer
import LocalPortability

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

    /// FILE-008: payloads and references.
    let folder: ContentAddressedMediaFolder

    init(directory: URL, defaults: UserDefaults, limits: ImageImportLimits = .standard,
         fault: (@Sendable (ContentAddressedMediaFolder.Step, URL) throws -> Void)? = nil) {
        self.directory = directory
        self.defaults = defaults
        self.limits = limits
        self.folder = ContentAddressedMediaFolder(directory: directory, extensions: Self.extensions, fault: fault)
    }

    /// The folder's name in Application Support (FILE-009 measures it).
    static let folderName = "Photos"

    /// `Library/Application Support/Photos`.
    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(folderName, isDirectory: true)
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

    /// The copy of `id` inside the folder, if one exists: a legacy `<UUID>.png|jpg` or its payload (FILE-008).
    func existingFile(for id: UUID) -> URL? {
        folder.resolve(id)
    }

    /// FILE-008-R5: every identifier that resolves (the current one, earlier references to the same
    /// picture, photos a FILE-005 restore wrote).
    func knownIDs() -> [UUID] {
        folder.references()
    }

    /// Imports the image at `source` (a picked file) and makes it the stored photo.
    @discardableResult
    func importImage(at source: URL) throws(ImageImportError) -> StoredPhoto {
        let staged = try stage(at: source)
        makeCurrent(staged)
        return staged
    }

    /// FILE-001: the sanitized copy of `source` written into this store's folder under a new
    /// identifier, without making it current (the identifier key is not touched). A failure leaves
    /// no file.
    func stage(at source: URL) throws(ImageImportError) -> StoredPhoto {
        let data = try Self.readPicked(source, limits: limits)
        let copy = try ImageSanitizer.sanitize(data, limits: limits)
        let id = UUID()
        let temp = folder.incomingURL(for: id, extension: copy.fileExtension)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try copy.data.write(to: temp, options: .atomic)
            let url = try folder.intern(temp, as: id, consumingSource: true)   // FILE-008-R2
            return StoredPhoto(id: id, url: url)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw .saveFailed
        }
    }

    /// FILE-001: moves a copy staged by another store (a staging folder) into this folder under the
    /// same identifier, without making it current. FILE-008: an equal payload already here is reused.
    func adopt(_ staged: StoredPhoto) throws(ImageImportError) -> StoredPhoto {
        guard Self.extensions.contains(staged.url.pathExtension) else { throw .saveFailed }
        do {
            let url = try folder.intern(staged.url, as: staged.id, consumingSource: true)
            return StoredPhoto(id: staged.id, url: url)
        } catch {
            throw .saveFailed
        }
    }

    /// Makes a copy inside this folder the stored photo, then releases the previous content (R6).
    /// FILE-008-R4: references sharing the new photo's payload stay; at most 32 per payload.
    func makeCurrent(_ photo: StoredPhoto) {
        let previous = current()
        defaults.set(photo.id.uuidString, forKey: Self.idKey)
        let slides: Set<UUID> = SlideshowStore.protectedIDs(defaults)   // MED-006-R11
        if let previous, previous.id != photo.id, !folder.sharesPayload(previous.id, photo.id) {
            try? folder.releaseSharing(payloadOf: previous.id, keeping: slides.union([photo.id]))
        }
        try? folder.trim(payloadOf: photo.id, keeping: slides.union([photo.id]))
    }

    /// FILE-001: deletes a copy that never became current (staged or adopted, then abandoned). FILE-008:
    /// releases its reference; a payload another reference shares stays.
    func discard(_ photo: StoredPhoto) {
        guard photo.id != current()?.id else { return }
        try? folder.release([photo.id])
    }

    /// Deletes the stored copy and its identifier (MED-001-R7). FILE-008: every reference to the current
    /// picture is released, so its payload is deleted.
    func remove() {
        if let raw = defaults.string(forKey: Self.idKey), let id = UUID(uuidString: raw), id.uuidString == raw {
            try? folder.releaseSharing(payloadOf: id, keeping: SlideshowStore.protectedIDs(defaults))   // MED-006-R11
        }
        defaults.removeObject(forKey: Self.idKey)
    }

    // MARK: FILE-008 launch (research FILE-008-D5)

    /// Synchronous: temporary files and already migrated legacy names. Reads no content.
    func prepareFolder() { folder.prepare() }

    /// Off the main thread: migrates legacy copies and collects unreferenced payloads.
    func reconcileFolder() { _ = try? folder.reconcile() }

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
