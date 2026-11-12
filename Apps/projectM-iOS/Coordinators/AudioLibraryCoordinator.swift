// AudioLibraryCoordinator.swift — presentation state for the imported-audio library (AUD-001-T17;
// AUD-001-R1, R9, R10, R13, R24). The library itself (validation, copying, the record) is
// CaptureKit's `AudioLibrary`; this type only lists it for the chooser, runs imports off the main
// actor's critical path, and words the result.
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

    @ObservationIgnored private let library: AudioLibrary?
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// `library` is nil when its folder cannot even be named; the section then shows the storage message.
    init(library: AudioLibrary?,
         announce: @escaping @MainActor (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.library = library
        self.announce = announce
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
        return AudioLibraryCoordinator(library: directory.map { AudioLibrary(directory: $0) })
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

    private func refresh() async {
        guard let library else { return }
        switch await library.load() {
        case .ready:
            unavailableMessage = nil
            tracks = await library.tracks.reversed()
        case .unavailable(let reason):
            unavailableMessage = UIStrings.message(reason)
            tracks = []
        }
    }
}
