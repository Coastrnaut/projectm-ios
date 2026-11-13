// AudioLibraryCoordinator.swift — presentation state for the imported-audio library (AUD-001-T17;
// AUD-001-R1, R9, R10, R13, R24). The library itself (validation, copying, the record) is
// CaptureKit's `AudioLibrary`; this type only lists it for the chooser, runs imports off the main
// actor's critical path, and words the result.
//
// AUD-003: it also owns the play queue (`PlayQueue`, stored as `queue.json` in the library folder)
// and keeps it in step with the library: after every ready load, import and removal the queue gets
// the library's tracks, and newly imported tracks join it at the top. An unavailable library is
// never handed to the queue, so its stored order is left alone.
import CaptureKit
import CaptureUI
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AudioLibraryCoordinator {
    /// Imported tracks, newest first (AUD-001-R10).
    private(set) var tracks: [ImportedTrack] = []
    /// True while picked files are being validated and copied (AUD-001-R9).
    private(set) var isImporting = false
    /// Set when the library cannot be used (AUD-001-R15); the chooser shows it instead of the list.
    private(set) var unavailableMessage: String?
    /// The result of the last import when something was not imported; shown as an alert.
    var resultMessage: String?

    /// The play order of imported audio (AUD-003).
    let queue: PlayQueue

    @ObservationIgnored private let library: AudioLibrary?
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// `library` is nil when its folder cannot even be named; the section then shows the storage message.
    /// `queueDirectory`: where `queue.json` lives (the library folder); nil keeps the queue in memory.
    init(library: AudioLibrary?, queueDirectory: URL? = nil,
         announce: @escaping @MainActor (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.library = library
        self.announce = announce
        queue = PlayQueue(store: queueDirectory.map { PlayQueueStore(directory: $0) })
        if library == nil { unavailableMessage = UIStrings.message(AudioLibraryState.Unavailable.storage) }
    }

    /// The app's library in Application Support (AUD-001-R2).
    static func makeDefault() -> AudioLibraryCoordinator {
        let directory = try? AudioLibrary.defaultDirectory()
        #if DEBUG
        // UI tests start from an empty library.
        if let directory, ProcessInfo.processInfo.arguments.contains("-uitestResetAudioLibrary") {
            try? FileManager.default.removeItem(at: directory)
        }
        #endif
        return AudioLibraryCoordinator(library: directory.map { AudioLibrary(directory: $0) }, queueDirectory: directory)
    }

    /// Reads the library record; safe to call again.
    func load() async {
        await refresh()
    }

    /// The Files picker finished. A cancelled or failed picker changes nothing; otherwise every
    /// picked file is imported in order and the result is announced, and shown when any file was
    /// a duplicate or was refused (AUD-001-R6).
    func importPicked(_ result: Result<[URL], any Error>) async {
        guard case .success(let urls) = result, !urls.isEmpty else {
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                resultMessage = UIStrings.message(AudioImportError.sourceUnavailable)
            }
            return
        }
        guard let library, !isImporting else {
            if library == nil { resultMessage = UIStrings.message(AudioImportError.libraryUnavailable) }
            return
        }
        isImporting = true
        let outcomes = await library.importFiles(at: urls)
        await refresh()
        queue.didImport(outcomes.compactMap { if case .imported(let track) = $0 { track.id.uuidString } else { nil } })
        isImporting = false
        guard let summary = UIStrings.importSummary(outcomes) else { return }
        announce(summary)                                          // FR-070 / AUD-001-R24
        if UIStrings.importNeedsAlert(outcomes) { resultMessage = summary }
    }

    /// Removes a track and its stored copy (AUD-001-R13).
    func remove(_ track: ImportedTrack) async {
        guard let library else { return }
        do {
            try await library.remove(track.id)
        } catch {
            resultMessage = UIStrings.message(error)
        }
        await refresh()
    }

    /// Where the track's copy is stored, for In-App Playback; nil when the track is no longer in
    /// the library. Always a file inside the app's own library, never the picked location.
    func playbackURL(for track: ImportedTrack) async -> URL? {
        guard let library else { return nil }
        let url = await library.storedFileURL(for: track.id)
        if url == nil { await refresh() }
        return url
    }

    // MARK: - Play order (AUD-006)

    /// The listed tracks as playable items, in list order (newest first). The queue takes them as
    /// its catalog (AUD-003); each item plays the library's own stored copy.
    func playbackItems() async -> [PlaybackItem] {
        guard let library else { return [] }
        var items: [PlaybackItem] = []
        for track in tracks {
            guard let url = await library.storedFileURL(for: track.id) else { continue }
            items.append(PlaybackItem(id: track.id.uuidString, title: track.title, durationSeconds: track.durationSeconds,
                                      track: .file(url)))
        }
        return items
    }

    // MARK: - Queue (AUD-003)

    /// "Play Next": right after the current track (at the top when there is none).
    func playNext(_ track: ImportedTrack) {
        queue.playNext(track.id.uuidString)
        announce(UIStrings.playNextAnnouncement(title: track.title))
    }

    /// "Add to Queue": at the end.
    func addToQueue(_ track: ImportedTrack) {
        queue.addToEnd(track.id.uuidString)
        announce(UIStrings.queueAddedAnnouncement(title: track.title))
    }

    /// The bundled reference track as the only item of its order: it repeats, and Next track and
    /// Previous track start it again. Its length is read from the file when it plays.
    static var referenceItem: PlaybackItem {
        PlaybackItem.reference(title: UIStrings.referenceTrackTitle, durationSeconds: 0)
    }

    private func refresh() async {
        guard let library else { return }
        switch await library.load() {
        case .ready:
            unavailableMessage = nil
            tracks = await library.tracks.reversed()
            queue.setLibrary(await playbackItems())
        case .unavailable(let reason):
            unavailableMessage = UIStrings.message(reason)
            tracks = []
        }
    }
}
