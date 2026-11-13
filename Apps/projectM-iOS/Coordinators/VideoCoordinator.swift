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
import CoreTransferable
import Foundation
import Observation
import PhotosUI
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

    /// `store` is nil when the folder cannot be named; imports then fail with `.saveFailed`.
    init(store: VideoStore?,
         announce: @escaping @MainActor (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.store = store
        self.announce = announce
        video = store?.current()
    }

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

    /// The video layer could not play the stored copy (it keeps its identifier; R18).
    func storedCopyFailed() { show(Self.storedCopyUnreadableMessage) }

    private func setVideo(_ stored: StoredVideo?) {
        video = stored
        playingSize = nil
        onVideoChange?(stored)
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
