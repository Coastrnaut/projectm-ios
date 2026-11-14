// PhotosSaveCoordinator.swift — Save to Photos for a saved frame, a finished recording or a kept recording
// (REC-011; spec specs/210-rec-011-export-to-photos, contracts/photos-save.md, research REC-011-D1 to D9,
// ADR-0059).
//
// * Add-only access (`PHAccessLevel.addOnly`, research D1). The status is read, and access requested when iOS
//   has not asked yet, only inside `save(_:)`, which only a Save to Photos tap calls (REC-011-R2, R4; D2).
//   Creating the coordinator touches nothing.
// * A still is added from its encoded bytes, a recording from its file with `shouldMoveFile = false` (D4): the
//   original is never moved, changed or deleted, whatever the outcome (REC-011-R5, R6).
// * Denied, restricted and failed saves set a notice saying the file is still in the app, with Open Settings for
//   denied and restricted (REC-011-R7, R8; texts from PermissionCatalog). Every outcome is announced through the
//   ACC-011 router (row X8a, posted by `CaptureEventChanges`).
// * One save at a time; `saving` names the item so its Save…, Keep, Discard, Rename and Delete wait (R10, D5).
// * Access and saving sit behind `PhotosAccessProviding` and `PhotosSaving` (D8): tests inject counting fakes,
//   DEBUG `-uitestPhotosAccess <state>` installs the stand-in (PhotosSaveStandIn.swift).
// * Nothing is remembered about saved items: no key, no identifier, no history (REC-011-R14).
import FrameCapture
import Foundation
import Observation
import Photos

/// iOS's add-only Photos status as the app sees it (research D3).
enum PhotosAccess: String, Sendable, Equatable, CaseIterable {
    case notDetermined, granted, denied, restricted

    /// `.limited` counts as granted; an unknown future status as denied (as the camera mapping).
    static func from(_ status: PHAuthorizationStatus) -> PhotosAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized, .limited: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    /// FILE-013's permission state.
    var permissionState: PermissionState {
        switch self {
        case .notDetermined: .notDetermined
        case .granted: .granted
        case .denied: .denied
        case .restricted: .restricted
        }
    }
}

/// What the user asked to save.
enum PhotosSaveItem: Sendable, Equatable {
    /// An offered still: its encoded bytes and the name its file would get.
    case frame(data: Data, format: FrameCaptureFormat, name: String)
    /// An offered or kept recording: its file, which stays where it is.
    case recording(URL)

    /// Which item a save belongs to (the offered frame, or a recording by its path).
    enum Key: Hashable, Sendable {
        case frame
        case file(String)
    }

    var key: Key {
        switch self {
        case .frame: .frame
        case .recording(let url): .file(url.standardizedFileURL.path)
        }
    }

    static func key(for file: URL) -> Key { .file(file.standardizedFileURL.path) }
}

/// How a save ended (contract C3).
enum PhotosSaveOutcome: String, Sendable, Equatable {
    case saved, denied, restricted, failed

    static let savedText = "Saved to Photos."
    static let failedText = "The file couldn't be saved to Photos. It is still in the app."

    var notice: String {
        switch self {
        case .saved: return Self.savedText
        case .failed: return Self.failedText
        case .denied, .restricted:
            let state: PermissionState = self == .denied ? .denied : .restricted
            guard let notice = PermissionCatalog.notice(.photosAdd, state) else { return Self.failedText }
            let kept: String = notice.fallback ?? PermissionCatalog.photosOriginalKept
            return notice.text + " " + kept
        }
    }

    /// Denied and restricted offer Open Settings (iOS has a per-app Photos switch).
    var offersSettings: Bool { self == .denied || self == .restricted }
}

/// Reads and requests add-only Photos access.
@MainActor
protocol PhotosAccessProviding: AnyObject {
    func status() -> PhotosAccess
    func request() async -> PhotosAccess
}

/// Adds one item to the photo library.
@MainActor
protocol PhotosSaving: AnyObject {
    func save(_ item: PhotosSaveItem) async throws
}

/// The real add-only access (research D1, D2).
@MainActor
final class LivePhotosAccess: PhotosAccessProviding {
    func status() -> PhotosAccess {
        PhotosAccess.from(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    func request() async -> PhotosAccess {
        let status: PHAuthorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return PhotosAccess.from(status)
    }
}

/// The real saver: one Photos change per item, the original untouched (research D4).
@MainActor
final class LivePhotosSaver: PhotosSaving {
    func save(_ item: PhotosSaveItem) async throws {
        try await PHPhotoLibrary.shared().performChanges(Self.changes(for: item))
    }

    /// The change block, made outside the main actor: Photos runs it on its own queue, so a block formed in this
    /// main-actor class would inherit the main actor and trap Swift's isolation check (seen on the simulator).
    nonisolated private static func changes(for item: PhotosSaveItem) -> @Sendable () -> Void {
        { () -> Void in addResource(item) }
    }

    /// Runs inside Photos' change block.
    nonisolated private static func addResource(_ item: PhotosSaveItem) {
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        switch item {
        case let .frame(data, format, name):
            options.originalFilename = name
            options.uniformTypeIdentifier = format.typeIdentifier
            request.addResource(with: .photo, data: data, options: options)
        case let .recording(url):
            options.originalFilename = url.lastPathComponent
            options.shouldMoveFile = false   // REC-011-R6: Photos copies; the file stays in the app
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }
}

@MainActor
@Observable
final class PhotosSaveCoordinator {
    /// The item being saved; nil when no save runs.
    private(set) var saving: PhotosSaveItem.Key?
    private(set) var notice: String?
    private(set) var noticeOffersSettings = false
    private(set) var lastOutcome: PhotosSaveOutcome?
    /// Successful saves this launch (tests and the DEBUG probe; never stored).
    private(set) var savedCount = 0

    @ObservationIgnored let access: any PhotosAccessProviding
    @ObservationIgnored let saver: any PhotosSaving
    @ObservationIgnored private var task: Task<Void, Never>?

    init(access: any PhotosAccessProviding = LivePhotosAccess(), saver: any PhotosSaving = LivePhotosSaver()) {
        self.access = access
        self.saver = saver
    }

    /// The app's coordinator: the live service, or DEBUG `-uitestPhotosAccess <state>`'s stand-in.
    static func forCurrentLaunch() -> PhotosSaveCoordinator {
        #if DEBUG
        if let standIn = PhotosSaveStandIn.fromArguments() {
            return PhotosSaveCoordinator(access: standIn, saver: standIn)
        }
        #endif
        return PhotosSaveCoordinator()
    }

    var isSaving: Bool { saving != nil }

    func isSaving(_ key: PhotosSaveItem.Key) -> Bool { saving == key }

    /// Save to Photos (the user's tap). Returns false when another save is running (the tap is ignored).
    @discardableResult
    func save(_ item: PhotosSaveItem) -> Bool {
        guard saving == nil else { return false }
        saving = item.key
        notice = nil   // a repeated outcome is a new notice (and a new announcement)
        noticeOffersSettings = false
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome: PhotosSaveOutcome = await self.run(item)
            self.finish(outcome)
        }
        return true
    }

    /// Awaits the running save (tests).
    func waitForSave() async {
        await task?.value
    }

    func clearNotice() {
        notice = nil
        noticeOffersSettings = false
    }

    func openSettings() {
        PermissionCatalog.openSettings()
    }

    private func run(_ item: PhotosSaveItem) async -> PhotosSaveOutcome {
        var state: PhotosAccess = access.status()
        if state == .notDetermined { state = await access.request() }
        switch state {
        case .granted:
            do {
                try await saver.save(item)
                return .saved
            } catch {
                return .failed
            }
        case .denied, .notDetermined:
            return .denied
        case .restricted:
            return .restricted
        }
    }

    private func finish(_ outcome: PhotosSaveOutcome) {
        saving = nil
        task = nil
        lastOutcome = outcome
        if outcome == .saved { savedCount += 1 }
        notice = outcome.notice
        noticeOffersSettings = outcome.offersSettings
    }
}
