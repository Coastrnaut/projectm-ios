// SlideshowCoordinator.swift — the image slideshow in the app (MED-006-R1 to R7, R12, R13; research
// MED-006-D2 to D7, D9; contracts/slideshow.md C4).
//
// * Settings: on/off, order, mode, seconds and beats are saved at once (`SlideshowStore`) and are part
//   of the scene (SceneInputs reads `settings`, so each edit is an autosave and one undo step).
// * Pictures: several at once from Photos (`PhotosPicker`, out of process, received as files) or Files,
//   imported off the main actor one after another through MED-001's sanitizer, up to 20; the rest are
//   refused with a notice. Removing and clearing release the references. Adding and removing are not
//   undoable (they change stored files, like the MED-001 photo).
// * Playback: `SlideshowSchedule`, ticked by the app once per shown frame (`tick`). It starts from the
//   first slide whenever the slideshow (re)starts; reordering keeps the shown picture, removing it shows
//   its successor. `onPlaybackChange` asks the app to re-choose the photo layer's content.
// * Beats: `grid(snapshot:readout:)` gives a grid only for a manual or stable tempo with a phase
//   (MED-006-R6); otherwise the schedule follows the Time rule.
// * Announcements go through the injected closure (the app wires the shared announcer, kind `library`).
import Foundation
import ImageIO
import ImageLayer
import Observation
import PerformanceControl
import PhotosUI
import SceneFormat
import SwiftUI
import UIKit

@MainActor
@Observable
final class SlideshowCoordinator {
    static let noticeDuration: Duration = .seconds(6)
    static let fullMessage = "A slideshow holds at most 20 pictures."
    nonisolated static let thumbnailPixels = 132

    /// The saved arrangement.
    private(set) var settings: SlideshowSettings
    /// True while picked pictures are being checked and copied.
    private(set) var isImporting = false
    /// The non-blocking notice (nil when none).
    private(set) var notice: String?
    /// Small previews for the Settings list.
    private(set) var thumbnails: [UUID: UIImage] = [:]

    @ObservationIgnored private let store: SlideshowStore?
    /// Announcements (the app wires the shared announcer, kind `library`).
    @ObservationIgnored var announce: @MainActor (String) -> Void
    @ObservationIgnored private var schedule: SlideshowSchedule
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailsLoading: Set<UUID> = []
    /// The photo layer must show `currentURL` again (start, stop, or an edit changed the shown picture).
    @ObservationIgnored var onPlaybackChange: (() -> Void)?

    init(store: SlideshowStore?, announce: @escaping @MainActor (String) -> Void = { (_: String) -> Void in }) {
        self.store = store
        self.announce = announce
        let saved: SlideshowSettings = store?.settings() ?? .off
        settings = saved
        schedule = SlideshowSchedule(count: saved.slides.count)
    }

    static func makeDefault(defaults: UserDefaults) -> SlideshowCoordinator {
        let photos: PhotoStore? = (try? PhotoStore.defaultDirectory()).map { (url: URL) -> PhotoStore in PhotoStore(directory: url, defaults: defaults) }
        return SlideshowCoordinator(store: photos.map { (p: PhotoStore) -> SlideshowStore in SlideshowStore(photos: p) })
    }

    // MARK: - Playback

    var isActive: Bool { settings.isActive }
    /// The shown slide's position (diagnostics, the probe).
    var shownIndex: Int { schedule.index }
    /// Slide changes since the slideshow started (diagnostics, the probe).
    var changes: Int { schedule.changes }

    /// The picture the photo layer shows now (nil when the slideshow is not active).
    var currentURL: URL? { isActive ? url(at: schedule.index) : nil }
    /// The picture after it (decoded ahead).
    var nextURL: URL? { isActive && settings.slides.count > 1 ? url(at: schedule.nextIndex) : nil }

    private func url(at index: Int) -> URL? {
        guard settings.slides.indices.contains(index) else { return nil }
        return store?.url(for: settings.slides[index])
    }

    /// One shown frame at `now` (monotonic nanoseconds). Returns the new slide's picture when it changes.
    func tick(now: UInt64, grid: SlideshowBeatGrid?, floorNanoseconds: UInt64) -> URL? {
        guard isActive,
              let index = schedule.tick(now: now, mode: settings.mode, seconds: settings.seconds, beats: settings.beats,
                                        grid: grid, floorNanoseconds: floorNanoseconds) else { return nil }
        return url(at: index)
    }

    /// From the first slide (the Photo visual was created, or the slideshow turned on).
    func restartPlayback() {
        schedule.restart(count: settings.slides.count)
    }

    /// MED-006-R6: a beat grid only for a manual or stable tempo with a period and a phase.
    nonisolated static func grid(snapshot: TempoSnapshot, readout: TempoReadout) -> SlideshowBeatGrid? {
        switch readout {
        case .manual, .stable: break
        case .uncertain, .searching: return nil
        }
        guard let period = snapshot.periodNanoseconds, let anchor = snapshot.anchorNanoseconds else { return nil }
        return SlideshowBeatGrid(periodNanoseconds: period, anchorNanoseconds: anchor)
    }

    // MARK: - Settings edits

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.enabled else { return }
        commit(settings.with(enabled: enabled))
        schedule.restart(count: settings.slides.count)
        onPlaybackChange?()
        announce(enabled ? "Slideshow on." : "Slideshow off.")
    }

    func setMode(_ mode: SlideshowMode) {
        guard mode != settings.mode else { return }
        commit(settings.with(mode: mode))
        schedule.timingChanged()
    }

    func setSeconds(_ seconds: Int) {
        let value: Int = SlideshowSettings.clampSeconds(seconds)
        guard value != settings.seconds else { return }
        commit(settings.with(seconds: value))
        schedule.timingChanged()
    }

    func setBeats(_ beats: Int) {
        let value: Int = SlideshowSettings.validBeats(beats)
        guard value != settings.beats else { return }
        commit(settings.with(beats: value))
        schedule.timingChanged()
    }

    private func commit(_ next: SlideshowSettings) {
        settings = next
        store?.save(next)
    }

    // MARK: - List edits (the shown picture stays where possible)

    /// Replaces the order, keeping the shown picture on screen.
    private func reorder(_ slides: [UUID]) {
        let shown: UUID? = settings.slides.indices.contains(schedule.index) ? settings.slides[schedule.index] : nil
        commit(settings.with(slides: slides))
        let index: Int = shown.flatMap { (id: UUID) -> Int? in settings.slides.firstIndex(of: id) } ?? 0
        schedule.relist(count: settings.slides.count, index: index)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var slides: [UUID] = settings.slides
        slides.move(fromOffsets: source, toOffset: destination)
        reorder(slides)
        announce("Slideshow order changed.")
    }

    func moveUp(_ id: UUID) {
        guard let i = settings.slides.firstIndex(of: id), i > 0 else { return }
        var slides: [UUID] = settings.slides
        slides.swapAt(i, i - 1)
        reorder(slides)
        announce(Self.positionText(i, of: slides.count))
    }

    func moveDown(_ id: UUID) {
        guard let i = settings.slides.firstIndex(of: id), i + 1 < settings.slides.count else { return }
        var slides: [UUID] = settings.slides
        slides.swapAt(i, i + 1)
        reorder(slides)
        announce(Self.positionText(i + 2, of: slides.count))
    }

    /// "Picture 2 of 5" (1-based position).
    static func positionText(_ position: Int, of count: Int) -> String {
        let p: String = String(position), c: String = String(count)
        return "Picture " + p + " of " + c
    }

    func remove(atOffsets offsets: IndexSet) {
        let removed: [UUID] = offsets.compactMap { (i: Int) -> UUID? in settings.slides.indices.contains(i) ? settings.slides[i] : nil }
        guard !removed.isEmpty else { return }
        let shownBefore: URL? = currentURL
        let before: Int = schedule.index
        let removedBefore: Int = offsets.filter { (i: Int) -> Bool in i < before }.count
        var slides: [UUID] = settings.slides
        slides.remove(atOffsets: offsets)
        commit(settings.with(slides: slides))
        store?.release(removed)
        for id in removed { thumbnails[id] = nil }
        var index: Int = before - removedBefore
        if index >= slides.count { index = 0 }
        schedule.relist(count: slides.count, index: index)
        if currentURL != shownBefore { onPlaybackChange?() }
        announce(removed.count == 1 ? "Picture removed from the slideshow." : "Pictures removed from the slideshow.")
    }

    func remove(_ id: UUID) {
        guard let i = settings.slides.firstIndex(of: id) else { return }
        remove(atOffsets: IndexSet(integer: i))
    }

    func clear() {
        let removed: [UUID] = settings.slides
        guard !removed.isEmpty else { return }
        commit(settings.with(slides: []))
        store?.release(removed)
        thumbnails = [:]
        schedule.restart(count: 0)
        onPlaybackChange?()
        announce("Slideshow cleared.")
    }

    /// Appends staged pictures (the shown one stays).
    private func append(_ ids: [UUID]) {
        let wasActive: Bool = isActive
        commit(settings.with(slides: settings.slides + ids))
        schedule.relist(count: settings.slides.count, index: schedule.index)
        if !wasActive && isActive {
            schedule.restart(count: settings.slides.count)
            onPlaybackChange?()
        }
    }

    // MARK: - Scenes (MED-006-R12)

    /// The scene field (nil when there is nothing to record: off and empty).
    var sceneValue: SceneSlideshow? {
        guard settings.enabled || !settings.slides.isEmpty else { return nil }
        return SceneSlideshow(enabled: settings.enabled, storeIDs: settings.slides.map(\.uuidString), mode: settings.mode.rawValue,
                              seconds: settings.seconds, beats: settings.beats)
    }

    /// PERF-005: the picture the photo layer would show first after `restore(scene)` (nil: the slideshow would be
    /// off or empty, so the stored photo shows). Changes nothing.
    func firstURL(restoring scene: SceneSlideshow?) -> URL? {
        guard let scene, scene.enabled else { return nil }
        let named: [UUID] = scene.storeIDs.compactMap { (text: String) -> UUID? in UUID(uuidString: text) }
            .filter { (id: UUID) -> Bool in settings.slides.contains(id) }
        guard let first = named.first ?? settings.slides.first else { return nil }
        return store?.url(for: first)
    }

    /// Applies a scene's slideshow: on/off and timing; stored slides reordered (named first, in the
    /// scene's order, the rest after). Absent: the slideshow turns off. Never adds or deletes pictures.
    func restore(_ scene: SceneSlideshow?) {
        guard let scene else {
            if settings.enabled {
                commit(settings.with(enabled: false))
                schedule.restart(count: settings.slides.count)
                onPlaybackChange?()
            }
            return
        }
        let named: [UUID] = scene.storeIDs.compactMap { (text: String) -> UUID? in UUID(uuidString: text) }
            .filter { (id: UUID) -> Bool in settings.slides.contains(id) }
        let rest: [UUID] = settings.slides.filter { (id: UUID) -> Bool in !named.contains(id) }
        let next = SlideshowSettings(enabled: scene.enabled, slides: named + rest,
                                     mode: SlideshowMode(rawValue: scene.mode) ?? .time, seconds: scene.seconds, beats: scene.beats)
        guard next != settings else { return }
        let playback: Bool = next.enabled != settings.enabled || next.slides != settings.slides
        commit(next)
        if playback {
            schedule.restart(count: settings.slides.count)
            onPlaybackChange?()
        } else {
            schedule.timingChanged()
        }
    }

    // MARK: - Pickers

    /// The Photos picker finished (several items); each arrives as a temporary file, deleted afterwards.
    func photosPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !isImporting else { return }
        isImporting = true
        var files: [URL] = []
        var failed = 0
        for item in items {
            let picked: PickedImageFile? = try? await item.loadTransferable(type: PickedImageFile.self)
            if let picked { files.append(picked.url) } else { failed += 1 }
        }
        isImporting = false
        await importImages(at: files, deleteAfterwards: true, alreadyFailed: failed)
    }

    /// The Files picker finished (several files). Cancelling changes nothing.
    func filesPicked(_ result: Result<[URL], any Error>) async {
        switch result {
        case .success(let urls):
            await importImages(at: urls, deleteAfterwards: false, alreadyFailed: 0)
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { show(ImageImportError.unreadable.message) }
        }
    }

    /// Imports `urls` off the main actor, in order, up to the remaining capacity.
    func importImages(at urls: [URL], deleteAfterwards: Bool, alreadyFailed: Int) async {
        guard !isImporting else { return }
        guard let store else { show(ImageImportError.saveFailed.message); return }
        let capacity: Int = settings.remainingCapacity
        let accepted: [URL] = Array(urls.prefix(capacity))
        let refused: [URL] = Array(urls.dropFirst(capacity))
        if deleteAfterwards {
            for url in refused { try? FileManager.default.removeItem(at: url) }
        }
        isImporting = true
        let outcome: (ids: [UUID], error: ImageImportError?) = await Task.detached(priority: .userInitiated) { () -> ([UUID], ImageImportError?) in
            var ids: [UUID] = []
            var lastError: ImageImportError?
            for url in accepted {
                defer { if deleteAfterwards { try? FileManager.default.removeItem(at: url) } }
                do throws(ImageImportError) {
                    ids.append(try store.stage(at: url))
                } catch {
                    lastError = error
                }
            }
            return (ids, lastError)
        }.value
        isImporting = false
        if !outcome.ids.isEmpty {
            append(outcome.ids)
            announce(Self.addedText(outcome.ids.count))
        }
        if !refused.isEmpty {
            show(Self.fullMessage)
        } else if let error = outcome.error {
            show(error.message)
        } else if alreadyFailed > 0 {
            show(ImageImportError.unreadable.message)
        } else {
            clearNotice()
        }
    }

    /// "Added 1 picture to the slideshow." / "Added 5 pictures to the slideshow."
    static func addedText(_ count: Int) -> String {
        let number: String = String(count)
        let noun: String = count == 1 ? "picture" : "pictures"
        return "Added " + number + " " + noun + " to the slideshow."
    }

    #if DEBUG
    /// UI tests only (UITestPhotoFixture): synchronous imports before the first screen, then the timing.
    func seedNow(at urls: [URL], seconds: Int) {
        guard let store else { return }
        var ids: [UUID] = []
        for url in urls {
            do throws(ImageImportError) {
                ids.append(try store.stage(at: url))
            } catch {
                continue
            }
        }
        commit(SlideshowSettings(enabled: true, slides: settings.slides + ids, mode: .time, seconds: seconds, beats: settings.beats))
        schedule.restart(count: settings.slides.count)
    }
    #endif

    // MARK: - Thumbnails

    /// Loads missing previews off the main actor.
    func loadThumbnails() async {
        guard let store else { return }
        let wanted: [(UUID, URL)] = settings.slides.compactMap { (id: UUID) -> (UUID, URL)? in
            guard thumbnails[id] == nil, !thumbnailsLoading.contains(id), let url = store.url(for: id) else { return nil }
            return (id, url)
        }
        for (id, url) in wanted {
            thumbnailsLoading.insert(id)
            let image: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in Self.thumbnail(url) }.value
            thumbnailsLoading.remove(id)
            if let image, settings.slides.contains(id) { thumbnails[id] = image }
        }
    }

    nonisolated static func thumbnail(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - Notice

    func show(_ message: String) {
        notice = message
        announce(message)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }
}
