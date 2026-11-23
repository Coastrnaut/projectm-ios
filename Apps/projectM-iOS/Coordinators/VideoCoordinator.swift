// VideoCoordinator.swift — the Video visual's video: picker results → VideoStore, the notice, and
// Remove Video (MED-002-R2, R6, R7, R14; research MED-002-D9). Mirrors PhotoCoordinator (MED-001).
//
// * Photos: SwiftUI's `PhotosPicker` with the videos filter, without a photo library (out of process,
//   no permission, no library identifiers). The chosen item is received as a movie file
//   (`PickedVideoFile`) in the app's temporary folder, imported, and the temporary file deleted.
// * Files: `fileImporter` with movie types, one file; the URL is read once by the store.
// * Imports run off the main actor; one at a time. A refused or failed import keeps the stored
//   video and shows `notice` (the error's plain message), which clears itself after 6 s or on
//   Dismiss and never blocks anything. Cancelling a picker shows nothing.
// * `onVideoChange` tells the app coordinator which stored copy the video layer plays.
// * MED-003 (loop region, R7, R9, R10): `loopRegion` is the stored video's saved region (nil: the
//   whole file), kept clamped to `durationNanoseconds` once the layer reports it. Slider edits save
//   at once and reach the player through `onLoopRegionChange` once they settle (`loopSettle` after
//   the last change, or `commitLoop()` at the end of a drag), so a drag restarts the decoder once.
// * MED-004 (speed, R6, R8): `speed` is the stored video's saved speed (1× by default). A pick saves
//   and reaches the player at once through `onSpeedChange` (no settle: one discrete action). Speed
//   only ever goes to the video layer; nothing here touches the audio source.
// * MED-005 (reverse, R1, R5, R7): `reverse` is the stored video's saved direction (forward by default). The switch
//   saves and reaches the player at once through `onReverseChange`. The layer's `VideoReverseState` comes back through
//   `reverseStateChanged`: `reverseCaption` is "Preparing reverse…" or the unsupported clip's sentence (announced once);
//   the clip keeps playing forward meanwhile.
import CoreTransferable
import Foundation
import Observation
import PhotosUI
import SceneFormat
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VideoLayer

@MainActor
@Observable
final class VideoCoordinator {
    static let noticeDuration: Duration = .seconds(6)
    static let storedCopyUnreadableMessage = "The video couldn't be played."

    /// The stored video (nil: none).
    private(set) var video: StoredVideo?
    /// True while a picked video is being checked and copied.
    private(set) var isImporting = false
    /// The non-blocking notice (MED-002-R14); nil when none.
    private(set) var notice: String?
    /// The upright size of the playing copy, from the video layer (nil until it plays).
    var playingSize: (width: Int, height: Int)?

    @ObservationIgnored private let store: VideoStore?
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored var onVideoChange: ((StoredVideo?) -> Void)?

    /// MED-003: the stored video's loop region (nil: the whole file).
    private(set) var loopRegion: VideoLoopRegion?
    /// MED-003: the playing copy's duration, from the video layer (nil until it opened).
    var durationNanoseconds: Int64? {
        didSet { if let durationNanoseconds, durationNanoseconds != oldValue { clampLoopToDuration(durationNanoseconds) } }
    }
    /// MED-003: tells the app coordinator the region to play, after an edit settled.
    @ObservationIgnored var onLoopRegionChange: ((VideoLoopRegion?) -> Void)?
    /// MED-003: how long an edit must rest before it reaches the player.
    @ObservationIgnored var loopSettle: Duration = .milliseconds(400)
    @ObservationIgnored private var loopApplyTask: Task<Void, Never>?
    /// MED-003: the region last handed to the player (tests).
    @ObservationIgnored private(set) var appliedLoopRegion: VideoLoopRegion?

    /// MED-004: the stored video's playback speed (1× without a video).
    private(set) var speed: VideoPlaybackSpeed = .normal
    /// MED-004: tells the app coordinator the speed to play, at once.
    @ObservationIgnored var onSpeedChange: ((VideoPlaybackSpeed) -> Void)?

    /// MED-005: reverse playback of the stored video (forward without a video).
    private(set) var reverse = false
    /// MED-005: the video layer's reverse state.
    private(set) var reverseState: VideoReverseState = .off
    /// MED-005: tells the app coordinator the direction to play, at once.
    @ObservationIgnored var onReverseChange: ((Bool) -> Void)?
    /// MED-005: the unsupported reason announced last (each reason is announced once while reverse stays on).
    @ObservationIgnored private var announcedReverseReason: VideoReverseUnsupported?

    /// "Preparing reverse…" while the cache is built.
    static let reversePreparingCaption = "Preparing reverse…"

    /// `store` is nil when the folder cannot be named; imports then fail with `.saveFailed`.
    init(store: VideoStore?,
         announce: @escaping @MainActor (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.store = store
        self.announce = announce
        video = store?.current()
        loopRegion = video.flatMap { (stored: StoredVideo) -> VideoLoopRegion? in store?.loopRegion(for: stored.id) }
        appliedLoopRegion = loopRegion
        speed = video.map { (stored: StoredVideo) -> VideoPlaybackSpeed in store?.speed(for: stored.id) ?? .normal } ?? .normal
        reverse = video.map { (stored: StoredVideo) -> Bool in store?.isReversed(stored.id) ?? false } ?? false   // MED-005
    }

    /// FILE-008-R5: every stored identifier that resolves (scene and cue checks count them as present).
    var knownIDs: Set<String> { Set((store?.knownIDs() ?? []).map(\.uuidString)) }

    static func makeDefault(defaults: UserDefaults) -> VideoCoordinator {
        VideoCoordinator(store: (try? VideoStore.defaultDirectory()).map { VideoStore(directory: $0, defaults: defaults) })
    }

    /// "No video", "Importing…", "Loading…" or "1920 × 1080".
    var summary: String {
        if isImporting { return "Importing…" }
        guard video != nil else { return "No video" }
        guard let size = playingSize else { return "Loading…" }
        return "\(size.width) × \(size.height)"
    }

    // MARK: - Pickers

    /// The Files picker finished (one file). Cancelling changes nothing.
    func filePicked(_ result: Result<URL, any Error>) async {
        switch result {
        case .success(let url):
            await importVideo(at: url, deleteAfterwards: false)
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { show(VideoImportError.unreadable.message) }
        }
    }

    /// The Photos picker finished: the item arrives as a temporary movie file, deleted afterwards.
    func videoPicked(_ item: PhotosPickerItem) async {
        guard !isImporting else { return }
        isImporting = true
        let picked: PickedVideoFile?
        do {
            picked = try await item.loadTransferable(type: PickedVideoFile.self)
        } catch {
            picked = nil
        }
        isImporting = false
        guard let picked else { show(VideoImportError.unreadable.message); return }
        await importVideo(at: picked.url, deleteAfterwards: true)
    }

    /// Imports `url` off the main actor and publishes the result.
    func importVideo(at url: URL, deleteAfterwards: Bool) async {
        guard !isImporting else { return }
        guard let store else { show(VideoImportError.saveFailed.message); return }
        isImporting = true
        let result: Result<StoredVideo, VideoImportError> = await Task.detached(priority: .userInitiated) {
            defer { if deleteAfterwards { try? FileManager.default.removeItem(at: url) } }
            do throws(VideoImportError) {
                return .success(try await store.importVideo(at: url))
            } catch {
                return .failure(error)
            }
        }.value
        isImporting = false
        switch result {
        case .success(let stored):
            setVideo(stored)
            clearNotice()
            announce("Video imported.")
        case .failure(let error):
            show(error.message)
        }
    }

    #if DEBUG
    /// UI tests only (UITestVideoFixture): an import of a small fixture before the first screen.
    func importNow(at url: URL) async {
        guard let store else { return }
        do throws(VideoImportError) {
            setVideo(try await store.importVideo(at: url))
        } catch {
            show(error.message)
        }
    }
    #endif

    /// Remove Video: deletes the copy and its identifier.
    func remove() {
        store?.remove()
        setVideo(nil)
        clearNotice()
        announce("Video removed.")
    }

    /// SHOW-001 Clarification 2026-11-23: a cue's scene names `storeID` as its video. When it resolves and is not the
    /// current movie (FILE-008: an identifier sharing the current payload counts as current), it becomes the stored
    /// video without releasing anything. True when the video changed.
    @discardableResult
    func selectStored(storeID: String?) -> Bool {
        guard let storeID, let store, let id = UUID(uuidString: storeID), id.uuidString == storeID else { return false }
        if let current = video, store.isSameVideo(id, as: current.id) { return false }
        guard let selected = store.select(id) else { return false }
        setVideo(selected)
        return true
    }

    /// The video layer could not play the stored copy (it keeps its identifier; R18).
    func storedCopyFailed() { show(Self.storedCopyUnreadableMessage) }

    private func setVideo(_ stored: StoredVideo?) {
        video = stored
        playingSize = nil
        durationNanoseconds = nil
        loopApplyTask?.cancel()
        loopApplyTask = nil
        loopRegion = stored.flatMap { (s: StoredVideo) -> VideoLoopRegion? in store?.loopRegion(for: s.id) }
        appliedLoopRegion = loopRegion
        speed = stored.map { (s: StoredVideo) -> VideoPlaybackSpeed in store?.speed(for: s.id) ?? .normal } ?? .normal   // MED-004
        reverse = stored.map { (s: StoredVideo) -> Bool in store?.isReversed(s.id) ?? false } ?? false   // MED-005
        reverseState = .off
        announcedReverseReason = nil
        onVideoChange?(stored)
    }

    // MARK: - Loop region (MED-003)

    /// The region the sliders show: the saved one clamped to the duration, or the whole file.
    var effectiveLoop: VideoLoopRegion? {
        guard let durationNanoseconds else { return nil }
        return VideoLoopRegion.effective(loopRegion, duration: durationNanoseconds)
    }

    /// True when a region other than the whole file is saved.
    var hasLoopRegion: Bool { loopRegion != nil }

    /// The In slider moved to `seconds`.
    func setLoop(inSeconds seconds: Double) {
        guard let current = effectiveLoop else { return }
        let start: Int64 = Self.nanoseconds(seconds)
        var end: Int64 = current.outNanoseconds
        if end - start < VideoLoopRegion.minimumLengthNanoseconds { end = start + VideoLoopRegion.minimumLengthNanoseconds }
        updateLoop(VideoLoopRegion(inNanoseconds: start, outNanoseconds: end))
    }

    /// The Out slider moved to `seconds`.
    func setLoop(outSeconds seconds: Double) {
        guard let current = effectiveLoop else { return }
        let end: Int64 = Self.nanoseconds(seconds)
        var start: Int64 = current.inNanoseconds
        if end - start < VideoLoopRegion.minimumLengthNanoseconds { start = end - VideoLoopRegion.minimumLengthNanoseconds }
        updateLoop(VideoLoopRegion(inNanoseconds: start, outNanoseconds: end))
    }

    /// Reset Loop: the whole file, applied at once.
    func resetLoop() {
        updateLoop(nil)
        commitLoop()
    }

    /// The end of a drag: the player gets the saved region now.
    func commitLoop() {
        loopApplyTask?.cancel()
        loopApplyTask = nil
        applyLoop()
    }

    /// MED-003-R8: a restored scene's, undo state's or cue's region; applied only when `storeID` is
    /// the stored video or shares its payload (FILE-008) (nil: the scene has no video, nothing changes; no loop: the whole file).
    func restoreLoop(storeID: String?, loop: SceneVideoLoop?) {
        // FILE-008-R5: an earlier reference to the same stored movie counts as the stored video.
        guard let storeID, let video, let id = UUID(uuidString: storeID), id.uuidString == storeID,
              store?.isSameVideo(id, as: video.id) ?? (id == video.id) else { return }
        let region = SceneVideoLoopBridge.region(loop)
        guard region != loopRegion else { return }
        updateLoop(region)
        commitLoop()
    }

    /// Milliseconds rounded to the nearest whole millisecond.
    private static func nanoseconds(_ seconds: Double) -> Int64 {
        let milliseconds: Double = (max(seconds, 0) * 1000).rounded()
        return Int64(milliseconds) * 1_000_000
    }

    /// Saves `region` (clamped; the whole file is saved as none) and schedules the player update.
    private func updateLoop(_ region: VideoLoopRegion?) {
        guard let video else { return }
        var saved: VideoLoopRegion? = region
        if let region, let durationNanoseconds {
            let clamped = region.effective(duration: durationNanoseconds)
            saved = clamped.isWholeFile(duration: durationNanoseconds) ? nil : clamped
        }
        loopRegion = saved
        store?.setLoopRegion(saved, for: video.id)
        loopApplyTask?.cancel()
        let delay = loopSettle
        loopApplyTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.applyLoop()
        }
    }

    private func applyLoop() {
        guard appliedLoopRegion != loopRegion else { return }
        appliedLoopRegion = loopRegion
        onLoopRegionChange?(loopRegion)
    }

    /// A saved region that no longer fits the opened copy is clamped (and saved) without a restart.
    private func clampLoopToDuration(_ duration: Int64) {
        guard let video, let region = loopRegion else { return }
        let clamped = region.effective(duration: duration)
        let saved: VideoLoopRegion? = clamped.isWholeFile(duration: duration) ? nil : clamped
        guard saved != region else { return }
        if appliedLoopRegion == region { appliedLoopRegion = saved }   // the layer already plays the clamped region
        loopRegion = saved
        store?.setLoopRegion(saved, for: video.id)
    }

    // MARK: - Playback speed (MED-004)

    /// The Speed picker chose `speed`: saved and applied at once (nothing without a video).
    func setSpeed(_ newSpeed: VideoPlaybackSpeed) {
        guard let video, newSpeed != speed else { return }
        speed = newSpeed
        store?.setSpeed(newSpeed, for: video.id)
        onSpeedChange?(newSpeed)
    }

    /// MED-004-R7: a restored scene's, undo state's or cue's speed; applied only when `storeID` is the
    /// stored video or shares its payload (FILE-008) (nil storeID: nothing changes; nil or an unknown
    /// percent: 1×).
    func restoreSpeed(storeID: String?, speedPercent: Int?) {
        guard let storeID, let video, let id = UUID(uuidString: storeID), id.uuidString == storeID,
              store?.isSameVideo(id, as: video.id) ?? (id == video.id) else { return }
        let restored: VideoPlaybackSpeed = speedPercent.flatMap { (p: Int) -> VideoPlaybackSpeed? in VideoPlaybackSpeed(percent: p) } ?? .normal
        setSpeed(restored)
    }

    /// The scene field for the current speed (nil at 1×).
    var sceneSpeedPercent: Int? { speed.isNormal ? nil : speed.percent }

    // MARK: - Reverse (MED-005)

    /// The Reverse switch: saved and applied at once (nothing without a video).
    func setReverse(_ on: Bool) {
        guard let video, on != reverse else { return }
        reverse = on
        store?.setReversed(on, for: video.id)
        if !on {
            reverseState = .off
            announcedReverseReason = nil
        }
        onReverseChange?(on)
    }

    /// The video layer reported its reverse state. An unsupported reason is announced once.
    func reverseStateChanged(_ state: VideoReverseState) {
        reverseState = state
        guard reverse, case .unsupported(let reason) = state, reason != announcedReverseReason else { return }
        announcedReverseReason = reason
        announce(reason.message)
    }

    /// The caption under the switch while reverse is on: preparing, or why the clip plays forward; nil otherwise.
    var reverseCaption: String? {
        guard reverse else { return nil }
        switch reverseState {
        case .preparing: return Self.reversePreparingCaption
        case .unsupported(let reason): return reason.message
        case .off, .playing: return nil
        }
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

/// A Photos video received as a file in the app's temporary folder (research MED-002-D9).
struct PickedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { (received: ReceivedTransferredFile) -> PickedVideoFile in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PickedVideos", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = folder.appendingPathComponent(UUID().uuidString, isDirectory: false).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideoFile(url: copy)
        }
    }
}
