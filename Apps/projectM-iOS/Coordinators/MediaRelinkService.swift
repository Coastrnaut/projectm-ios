// MediaRelinkService.swift — MED-013 (contract specs/146-med-013-media-relinking/contracts/media-relink.md
// L5; research MED-013-D1-D4, D6): missing imported media and its relinking, off the main actor.
//
// * Missing media: every photo or video identifier a readable saved scene (SHOW-001) names that does not
//   resolve in its FILE-008 folder (photo assets, slideshow slides and logos in Photos; videos in Videos).
// * Relink by checksum: `adoptKnown` re-registers identifiers whose known payload exists again; an
//   identifier still registered resolves by itself once its payload is back.
// * Find in folder: one bounded, read-only scan (`MediaFolderScan`) of the picked folder under its security
//   scope for the missing payloads' SHA-256; each match is copied in, verified, and its identifiers adopted.
// * Replacement: the picked file goes through the store's own import (sanitized copy) under a new
//   identifier; every saved scene's reference is rewritten all or nothing (`ShowStore.rewriteMediaReferences`),
//   then the settings values that still name the old identifier. A failed rewrite discards the new copy.
// `@unchecked Sendable`: UserDefaults is thread-safe (documented) but not marked Sendable in the SDK.
import Foundation
import ImageLayer
import LocalPortability
import SceneFormat
import ShowControl
import ShowStorage
import VideoLayer

/// One missing identifier and who uses it (MED-013-R1).
struct MissingMediaItem: Identifiable, Equatable, Sendable {
    let store: SceneMediaStore
    let storeID: UUID
    /// Saved scenes naming it (sorted).
    let sceneIDs: [String]
    /// Cues whose scene names it.
    let cueCount: Int
    /// Its payload name is known (a checksum relink is possible).
    let checksumKnown: Bool

    var id: String { "\(store.rawValue):\(storeID.uuidString)" }
    var kindTitle: String { store == .photos ? "Photo" : "Video" }
    /// "Photo 1A2B3C4D".
    var title: String { "\(kindTitle) \(storeID.uuidString.prefix(8))" }

    /// "Used by 2 scenes and 2 cues" (", checksum unknown").
    var usageText: String {
        let scenes = sceneIDs.count == 1 ? "1 scene" : "\(sceneIDs.count) scenes"
        let cues = cueCount == 1 ? "1 cue" : "\(cueCount) cues"
        let usage = "Used by \(scenes) and \(cues)"
        return checksumKnown ? usage : usage + ", checksum unknown"
    }
}

/// What a relink did (MED-013-R8).
struct MediaRelinkReport: Equatable, Sendable {
    var relinked: Int = 0
    var scenes: Int = 0
    var cues: Int = 0
    var references: Int = 0
    var unreadableScenes: Int = 0
    var contentDiffers = false
    var storeKind = "photo"
    /// Folder scans: the folder was not fully searched.
    var limitReached = false
    var scanned = false

    var message: String {
        if contentDiffers {
            let scenesText = scenes == 1 ? "1 scene" : "\(scenes) scenes"
            let cuesText = cues == 1 ? "1 cue" : "\(cues) cues"
            var text = "Relinked: \(scenesText) and \(cuesText) now use the new \(storeKind) (\(references) "
                + (references == 1 ? "reference). " : "references). ")
            text += "It differs from the original."
            if unreadableScenes > 0 { text += " \(unreadableScenes) unreadable " + (unreadableScenes == 1 ? "scene was" : "scenes were") + " left alone." }
            return text
        }
        var text: String
        if relinked == 0 {
            text = scanned ? "No matching files were found." : "No missing media matched."
        } else {
            text = "Relinked \(relinked) missing " + (relinked == 1 ? "item" : "items") + " by checksum."
        }
        if limitReached { text += " The folder was not fully searched." }
        return text
    }
}

enum MediaRelinkError: Error, Equatable, Sendable {
    case photo(ImageImportError)
    case video(VideoImportError)
    /// The scenes could not be rewritten; nothing changed.
    case rewriteFailed
    case unreadableFolder

    var message: String {
        switch self {
        case let .photo(error): error.message
        case let .video(error): error.message
        case .rewriteFailed: "The scenes could not be updated. Nothing was changed."
        case .unreadableFolder: "The folder could not be read."
        }
    }
}

struct MediaRelinkService: @unchecked Sendable {
    /// File types a folder scan hashes.
    static let scanExtensions: Set<String> = ["png", "jpg", "jpeg", "mov"]

    let photos: PhotoStore
    let videos: VideoStore
    let show: ShowStore
    var scanLimits = MediaFolderScanLimits(maxFileBytes: max(ImageImportLimits.standard.maxFileBytes, VideoImportLimits.standard.maxFileBytes))

    var defaults: UserDefaults { photos.defaults }

    static func makeDefault(defaults: UserDefaults) -> MediaRelinkService? {
        guard let photos = try? PhotoStore.defaultDirectory(), let videos = try? VideoStore.defaultDirectory(),
              let show = try? ShowStore.defaultDirectory() else { return nil }
        return MediaRelinkService(photos: PhotoStore(directory: photos, defaults: defaults),
                                  videos: VideoStore(directory: videos, defaults: defaults), show: ShowStore(directory: show))
    }

    func folder(_ store: SceneMediaStore) -> ContentAddressedMediaFolder {
        store == .photos ? photos.folder : videos.folder
    }

    // MARK: - Missing media (MED-013-R1)

    func missingItems(cues: ShowCueList) -> [MissingMediaItem] {
        let usage = show.mediaUsage()
        var items: [MissingMediaItem] = []
        for key in usage.scenes.keys.sorted() {
            guard let id = UUID(uuidString: key.storeID), id.uuidString == key.storeID else { continue }
            let store = folder(key.store)
            guard store.resolve(id) == nil else { continue }
            let scenes: Set<String> = usage.scenes[key] ?? []
            let cueCount = cues.cues.filter { (cue: ShowCue) -> Bool in scenes.contains(cue.sceneID) }.count
            items.append(MissingMediaItem(store: key.store, storeID: id, sceneIDs: scenes.sorted(), cueCount: cueCount,
                                          checksumKnown: store.knownPayloadName(of: id) != nil))
        }
        return items.sorted { (a: MissingMediaItem, b: MissingMediaItem) -> Bool in
            if a.store != b.store { return a.store < b.store }
            if a.sceneIDs.count != b.sceneIDs.count { return a.sceneIDs.count > b.sceneIDs.count }
            return a.storeID.uuidString < b.storeID.uuidString
        }
    }

    private func ids(_ items: [MissingMediaItem], in store: SceneMediaStore) -> Set<UUID> {
        Set(items.filter { (i: MissingMediaItem) -> Bool in i.store == store }.map(\.storeID))
    }

    private func resolvedCount(_ items: [MissingMediaItem]) -> Int {
        items.filter { (i: MissingMediaItem) -> Bool in folder(i.store).resolve(i.storeID) != nil }.count
    }

    // MARK: - Relink by checksum (MED-013-R4)

    /// Adopts every missing identifier whose content is stored again; returns how many resolve now.
    func relinkByChecksum(_ items: [MissingMediaItem]) -> MediaRelinkReport {
        for store in SceneMediaStore.allCases {
            _ = try? folder(store).adoptKnown(ids(items, in: store))
        }
        return MediaRelinkReport(relinked: resolvedCount(items))
    }

    /// Scans `root` (a picked folder) for the missing payloads and copies matches in (MED-013-R5).
    func scanFolder(_ root: URL, items: [MissingMediaItem]) -> MediaRelinkReport {
        let scoped = root.startAccessingSecurityScopedResource()   // false for URLs that need no scope
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        var wanted: [String: (SceneMediaStore, Set<UUID>)] = [:]
        for store in SceneMediaStore.allCases {
            for (hash, ids) in folder(store).missingByHash(ids(items, in: store)) { wanted[hash] = (store, ids) }
        }
        var report = MediaRelinkReport(scanned: true)
        guard !wanted.isEmpty else { return report }
        let result = MediaFolderScan.scan(root: root, wanted: Set(wanted.keys), extensions: Self.scanExtensions, limits: scanLimits)
        for (hash, file) in result.matches.sorted(by: { (a: (key: String, value: URL), b: (key: String, value: URL)) -> Bool in a.key < b.key }) {
            guard let (store, ids) = wanted[hash] else { continue }
            _ = try? folder(store).restorePayload(from: file, missing: ids)
        }
        report.relinked = resolvedCount(items)
        report.limitReached = result.limitReached
        return report
    }

    // MARK: - Replacement (MED-013-R6, R7)

    /// Imports `source` for `item` and rewrites every reference to it. Nothing changes on failure.
    func replace(_ item: MissingMediaItem, with source: URL, cues: ShowCueList) async throws(MediaRelinkError) -> MediaRelinkReport {
        let newID: UUID
        switch item.store {
        case .photos:
            do throws(ImageImportError) {
                newID = try photos.stage(at: source).id
            } catch {
                throw .photo(error)
            }
        case .videos:
            do throws(VideoImportError) {
                newID = try await videos.stage(at: source).id
            } catch {
                throw .video(error)
            }
        }
        let rewrite: ShowMediaRewriteReport
        do throws(ShowMediaRewriteError) {
            rewrite = try show.rewriteMediaReferences(store: item.store, from: item.storeID.uuidString, to: newID.uuidString)
        } catch {
            try? folder(item.store).release([newID])   // the staged copy goes; nothing else changed
            try? folder(item.store).forget([newID])
            throw .rewriteFailed
        }
        rewriteSettings(store: item.store, from: item.storeID, to: newID)
        // The old identifier is no longer named: its dangling entry goes, and no relink hint stays.
        if folder(item.store).resolve(item.storeID) == nil { try? folder(item.store).release([item.storeID]) }
        try? folder(item.store).forget([item.storeID])
        let scenes = Set(rewrite.scenes)
        let cueCount = cues.cues.filter { (cue: ShowCue) -> Bool in scenes.contains(cue.sceneID) }.count
        return MediaRelinkReport(scenes: rewrite.scenes.count, cues: cueCount, references: rewrite.references,
                                 unreadableScenes: rewrite.unreadable.count, contentDiffers: true,
                                 storeKind: item.store == .photos ? "photo" : "video")
    }

    /// Settings values still naming `old` (read raw: their readers drop missing identifiers).
    func rewriteSettings(store: SceneMediaStore, from old: UUID, to new: UUID) {
        switch store {
        case .photos:
            for key in [PhotoStore.idKey, LogoStore.idKey] where defaults.string(forKey: key) == old.uuidString {
                defaults.set(new.uuidString, forKey: key)
            }
            let slideshow = SlideshowSettings.decode(defaults.data(forKey: SlideshowStore.key))
            if slideshow.slides.contains(old) {
                let slides = slideshow.slides.map { (id: UUID) -> UUID in id == old ? new : id }
                defaults.set(slideshow.with(slides: slides).encoded, forKey: SlideshowStore.key)
            }
        case .videos:
            if defaults.string(forKey: VideoStore.idKey) == old.uuidString {
                defaults.set(new.uuidString, forKey: VideoStore.idKey)
                defaults.removeObject(forKey: VideoStore.loopKey)    // the content differs: whole file
                defaults.removeObject(forKey: VideoStore.speedKey)   // at 1×
            }
        }
    }
}
