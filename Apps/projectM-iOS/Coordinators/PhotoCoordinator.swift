// PhotoCoordinator.swift — the Photo visual's picture: picker results → PhotoStore, the notice, and
// Remove Photo (MED-001-R2, R6, R7, R11; research MED-001-D1, D2).
//
// * Photos: SwiftUI's `PhotosPicker` without a photo library (out of process, no permission, no
//   library identifiers). The chosen item is received as a file (`PickedImageFile`) in the app's
//   temporary folder, imported, and the temporary file deleted.
// * Files: `fileImporter` with image types, one file; the URL is read once by the store.
// * Imports run off the main actor; one at a time. A refused or failed import keeps the stored
//   photo and shows `notice` (the error's plain message), which clears itself after 6 s or on
//   Dismiss and never blocks anything. Cancelling a picker shows nothing.
// * `onPhotoChange` tells the app coordinator which stored copy the photo layer shows.
import CoreTransferable
import Foundation
import ImageLayer
import Observation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class PhotoCoordinator {
    static let noticeDuration: Duration = .seconds(6)
    static let storedCopyUnreadableMessage = "The photo couldn't be loaded."

    /// The stored photo (nil: none).
    private(set) var photo: StoredPhoto?
    /// True while a picked image is being checked and copied.
    private(set) var isImporting = false
    /// The non-blocking notice (MED-001-R11); nil when none.
    private(set) var notice: String?
    /// The pixel size of the shown copy, from the photo layer (nil until it is loaded).
    var loadedSize: (width: Int, height: Int)?

    @ObservationIgnored private let store: PhotoStore?
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored var onPhotoChange: ((StoredPhoto?) -> Void)?

    /// `store` is nil when the folder cannot be named; imports then fail with `.saveFailed`.
    init(store: PhotoStore?,
         announce: @escaping @MainActor (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.store = store
        self.announce = announce
        photo = store?.current()
    }

    /// FILE-008-R5: every stored identifier that resolves (scene and cue checks count them as present).
    var knownIDs: Set<String> { Set((store?.knownIDs() ?? []).map(\.uuidString)) }

    static func makeDefault(defaults: UserDefaults) -> PhotoCoordinator {
        PhotoCoordinator(store: (try? PhotoStore.defaultDirectory()).map { PhotoStore(directory: $0, defaults: defaults) })
    }

    /// "No photo", "Importing…" or "1920 × 1080".
    var summary: String {
        if isImporting { return "Importing…" }
        guard photo != nil else { return "No photo" }
        guard let size = loadedSize else { return "Loading…" }
        return "\(size.width) × \(size.height)"
    }

    // MARK: - Pickers

    /// The Files picker finished (one file). Cancelling changes nothing.
    func filePicked(_ result: Result<URL, any Error>) async {
        switch result {
        case .success(let url):
            await importImage(at: url, deleteAfterwards: false)
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { show(ImageImportError.unreadable.message) }
        }
    }

    /// The Photos picker finished: the item arrives as a temporary file, which is deleted afterwards.
    func photoPicked(_ item: PhotosPickerItem) async {
        guard !isImporting else { return }
        isImporting = true
        let picked: PickedImageFile?
        do {
            picked = try await item.loadTransferable(type: PickedImageFile.self)
        } catch {
            picked = nil
        }
        isImporting = false
        guard let picked else { show(ImageImportError.unreadable.message); return }
        await importImage(at: picked.url, deleteAfterwards: true)
    }

    /// Imports `url` off the main actor and publishes the result.
    func importImage(at url: URL, deleteAfterwards: Bool) async {
        guard !isImporting else { return }
        guard let store else { show(ImageImportError.saveFailed.message); return }
        isImporting = true
        let result: Result<StoredPhoto, ImageImportError> = await Task.detached(priority: .userInitiated) {
            defer { if deleteAfterwards { try? FileManager.default.removeItem(at: url) } }
            do throws(ImageImportError) {
                return .success(try store.importImage(at: url))
            } catch {
                return .failure(error)
            }
        }.value
        isImporting = false
        switch result {
        case .success(let stored):
            setPhoto(stored)
            clearNotice()
            announce("Photo imported.")
        case .failure(let error):
            show(error.message)
        }
    }

    #if DEBUG
    /// UI tests only (UITestPhotoFixture): a synchronous import of a small fixture before the first screen.
    func importNow(at url: URL) {
        guard let store else { return }
        do throws(ImageImportError) {
            setPhoto(try store.importImage(at: url))
        } catch {
            show(error.message)
        }
    }
    #endif

    /// Remove Photo: deletes the copy and its identifier.
    func remove() {
        store?.remove()
        setPhoto(nil)
        clearNotice()
        announce("Photo removed.")
    }

    /// The photo layer could not load the stored copy (it keeps its identifier; R14).
    func storedCopyFailed() { show(Self.storedCopyUnreadableMessage) }

    private func setPhoto(_ stored: StoredPhoto?) {
        photo = stored
        loadedSize = nil
        onPhotoChange?(stored)
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

/// A Photos item received as a file in the app's temporary folder (research MED-001-D1).
struct PickedImageFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { (received: ReceivedTransferredFile) -> PickedImageFile in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PickedPhotos", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedImageFile(url: copy)
        }
    }
}
