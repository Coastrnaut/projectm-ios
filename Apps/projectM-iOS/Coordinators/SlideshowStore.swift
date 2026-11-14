// SlideshowStore.swift — the image slideshow's saved arrangement and its pictures (MED-006-R1, R2, R10,
// R11; research MED-006-D1, D8; contracts/slideshow.md C4).
//
// * The pictures are FILE-008 references in the Photos folder, made by `PhotoStore.stage` (MED-001's
//   bounded read, metadata-free copy, atomic write) under new identifiers that never become the current
//   photo. Equal pictures share one payload.
// * The arrangement (on/off, order, mode, seconds, beats) is one JSON value in UserDefaults
//   `settings.photo.slideshow` (`SlideshowSettings`), included in FILE-005 backups (the pictures are
//   backed up as photos) and removed by FILE-011's "Photos and videos" erase.
// * Reading drops identifiers whose copy no longer resolves (and saves the cleaned value).
// * `PhotoStore` keeps `protectedIDs` whenever it releases references, so a new photo or Remove Photo
//   never deletes a slide.
// Synchronous and Sendable: imports run off the main actor (SlideshowCoordinator).
import Foundation
import ImageLayer

/// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
struct SlideshowStore: @unchecked Sendable {
    static let key = "settings.photo.slideshow"

    let photos: PhotoStore
    var defaults: UserDefaults { photos.defaults }

    /// The saved arrangement; identifiers that no longer resolve are dropped (and the value re-saved).
    func settings() -> SlideshowSettings {
        let stored = SlideshowSettings.decode(defaults.data(forKey: Self.key))
        let present: [UUID] = stored.slides.filter { (id: UUID) -> Bool in photos.existingFile(for: id) != nil }
        guard present.count != stored.slides.count else { return stored }
        let cleaned = stored.with(slides: present)
        save(cleaned)
        return cleaned
    }

    /// Saves the arrangement (the default value removes the key).
    func save(_ settings: SlideshowSettings) {
        if settings == .off {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set(settings.encoded, forKey: Self.key)
        }
    }

    /// A sanitized copy of a picked file under a new identifier (not added to the arrangement).
    func stage(at source: URL) throws(ImageImportError) -> UUID {
        try photos.stage(at: source).id
    }

    /// Releases the slides' references (a payload no other reference shares is deleted).
    func release(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let current: UUID? = photos.current()?.id
        let releasable: Set<UUID> = Set(ids.filter { (id: UUID) -> Bool in id != current })
        try? photos.folder.release(releasable)
    }

    /// The stored copy of a slide.
    func url(for id: UUID) -> URL? { photos.existingFile(for: id) }

    /// The identifiers `PhotoStore` must keep (the saved slides), read straight from the defaults.
    static func protectedIDs(_ defaults: UserDefaults) -> Set<UUID> {
        Set(SlideshowSettings.decode(defaults.data(forKey: key)).slides)
    }
}
