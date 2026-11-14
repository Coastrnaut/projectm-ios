// LogoStore.swift — the MED-010 logo on disk and in the settings (MED-010-R2, R3, R9; research MED-010-D3;
// contracts/logo-overlay.md C7).
//
// * The picture is one more FILE-008 reference in the Photos folder (`PhotoStore`'s content-addressed
//   folder), named by UserDefaults `settings.logo.id`; equal pictures (the photo, a slide, an earlier logo)
//   share one payload. The copy is made by MED-001's bounded read and sanitizer with the logo's limits
//   (10 MB, 16,777,216 pixels, at most 1024 px) and always written as PNG, so alpha is kept losslessly.
// * The placement is one JSON value in `settings.logo.placement` (the default removes the key).
// * `PhotoStore` and `SlideshowStore` keep `protectedIDs` whenever they release references, so a new photo,
//   Remove Photo or a slideshow edit never deletes the logo; making a new logo current and Remove Logo
//   release the previous logo's payload while keeping the photo's and the slides' references.
// Synchronous and Sendable: imports run off the main actor (LogoCoordinator).
import Foundation
import ImageLayer

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct LogoStore: @unchecked Sendable {
    static let idKey = "settings.logo.id"
    static let placementKey = "settings.logo.placement"

    let photos: PhotoStore
    var defaults: UserDefaults { photos.defaults }

    /// The current logo, or nil (clearing an invalid identifier or one whose file is gone).
    func current() -> StoredPhoto? {
        guard let raw = defaults.string(forKey: Self.idKey) else { return nil }
        guard let id = UUID(uuidString: raw), id.uuidString == raw, let url = photos.existingFile(for: id) else {
            defaults.removeObject(forKey: Self.idKey)
            return nil
        }
        return StoredPhoto(id: id, url: url)
    }

    /// The saved placement (the default when absent or unreadable).
    var placement: LogoPlacement { LogoPlacement(jsonData: defaults.data(forKey: Self.placementKey)) }

    func savePlacement(_ placement: LogoPlacement) {
        if placement == .default {
            defaults.removeObject(forKey: Self.placementKey)
        } else {
            defaults.set(placement.jsonData, forKey: Self.placementKey)
        }
    }

    /// The sanitized PNG copy of a picked file under a new identifier, not current (MED-010-R3).
    func stage(at source: URL) throws(ImageImportError) -> StoredPhoto {
        try photos.stage(at: source, limits: LogoImport.limits, format: .png)
    }

    /// Imports `source` and makes it the logo.
    @discardableResult
    func importLogo(at source: URL) throws(ImageImportError) -> StoredPhoto {
        let staged = try stage(at: source)
        makeCurrent(staged)
        return staged
    }

    /// FILE-001: moves a logo staged in another folder (a staging store) into the Photos folder.
    func adopt(_ staged: StoredPhoto) throws(ImageImportError) -> StoredPhoto {
        guard staged.url.pathExtension == "png" else { throw .saveFailed }
        return try photos.adopt(staged)
    }

    /// The references this store must not release: the photo and the slides.
    private func othersKept() -> Set<UUID> {
        var kept: Set<UUID> = SlideshowStore.protectedIDs(defaults)
        if let photo = photos.current() { kept.insert(photo.id) }
        return kept
    }

    /// Makes a copy in the folder the logo, then releases the previous logo's payload (keeping the photo
    /// and the slides, and everything that shares the new logo's payload).
    /// `alsoKeeping`: references about to become current elsewhere (FILE-001's adopted photo).
    func makeCurrent(_ logo: StoredPhoto, alsoKeeping extra: Set<UUID> = []) {
        let previous = current()
        defaults.set(logo.id.uuidString, forKey: Self.idKey)
        let kept: Set<UUID> = othersKept().union([logo.id]).union(extra)
        if let previous, previous.id != logo.id, !photos.folder.sharesPayload(previous.id, logo.id) {
            try? photos.folder.releaseSharing(payloadOf: previous.id, keeping: kept)
        }
        try? photos.folder.trim(payloadOf: logo.id, keeping: kept)
    }

    /// FILE-001: releases a staged or adopted copy that never became the logo.
    func discard(_ logo: StoredPhoto) {
        guard logo.id != current()?.id, !othersKept().contains(logo.id) else { return }
        try? photos.folder.release([logo.id])
    }

    /// Remove Logo: releases every reference to the logo's payload except the photo's and the slides', and
    /// clears the identifier (the placement stays for the next logo).
    func remove() {
        if let raw = defaults.string(forKey: Self.idKey), let id = UUID(uuidString: raw), id.uuidString == raw {
            try? photos.folder.releaseSharing(payloadOf: id, keeping: othersKept())
        }
        defaults.removeObject(forKey: Self.idKey)
    }

    /// The identifier `PhotoStore` and `SlideshowStore` keep, read straight from the defaults.
    static func protectedIDs(_ defaults: UserDefaults) -> Set<UUID> {
        guard let raw = defaults.string(forKey: idKey), let id = UUID(uuidString: raw), id.uuidString == raw else { return [] }
        return [id]
    }
}
