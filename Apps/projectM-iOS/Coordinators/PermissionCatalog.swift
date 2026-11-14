// PermissionCatalog.swift — every privacy permission the app can trigger, in one place (FILE-013;
// specs/078-file-013-privacy-permission-audit, plan D1-D7).
//
// * One entry per permission: its Info.plist key, the usage text (identical to project.yml; checked by
//   scripts/check_permission_catalog.py and by PermissionCatalogTests against the built Info.plist),
//   the name the privacy policy lists, the features that use it and when iOS asks.
// * The Photos library needs no permission: the Photos picker runs outside the app and returns only
//   the picked item, so the app declares no Photos library key (the script fails if one appears).
// * Each framework's status maps to one `PermissionState`; denied and restricted give the
//   user-facing `PermissionNotice`. Texts fixed elsewhere by contract are referenced, not copied
//   (feature 001's UIStrings, CAM-001's CameraFeedState); the Local Network text lives here.
// * iOS has no restricted state for the microphone and no status query for Local Network: a
//   restriction arrives as a denial, so restricted shows the denied notice (plan D3).
// * Every Open Settings goes through `openSettings()` (plan D7).
import AVFoundation
import AudioCore
import CameraLayer
import CaptureKit
import CaptureUI
import PerformanceControl
import UIKit

/// A privacy permission the app can trigger.
enum AppPermission: String, CaseIterable, Sendable {
    case microphone, camera, localNetwork, screenCapture
}

/// One state per permission, whatever the framework calls it.
enum PermissionState: String, CaseIterable, Sendable {
    case notDetermined, granted, denied, restricted
}

/// What the app tells the user when a permission is denied or restricted.
struct PermissionNotice: Equatable, Sendable {
    let permission: AppPermission
    /// Nil for a feature notice that is not about the permission (for example no rear camera).
    let state: PermissionState?
    let text: String
    /// The notice offers Open Settings (the app's page in iOS Settings).
    let offersSettings: Bool
    /// CAM-013-R2: the notice offers Retry (the camera is interrupted or stopped by an error).
    var offersRetry: Bool = false
    /// UIX-015-R7, R8: what still works without the permission (nil when the text already says it).
    var fallback: String? = nil
    /// UIX-015-R7: the notice offers Dismiss for the current attempt (camera denied or restricted).
    var offersDismiss: Bool = false
}

/// The catalog's description of one permission.
struct PermissionEntry: Equatable, Sendable {
    let permission: AppPermission
    /// The name the privacy policy's "Permissions and why" section lists.
    let name: String
    let infoPlistKey: String
    /// Identical to the Info.plist value in project.yml.
    let usageDescription: String
    let features: [String]
    let askedWhen: String
    /// iOS Settings has a switch the user can change for this app.
    let settingsCanChange: Bool
    /// iOS reports restricted separately from denied.
    let hasDistinctRestrictedState: Bool
}

enum PermissionCatalog {
    // MARK: Entries (plan D10: the script reads the `name:`, `infoPlistKey:` and `usageDescription:` literals)

    static let entries: [PermissionEntry] = [
        PermissionEntry(permission: .microphone,
                        name: "Microphone",
                        infoPlistKey: "NSMicrophoneUsageDescription",
                        usageDescription: "Microphone mode listens to sound in the room through your device's microphone. It does not capture audio directly from other apps.",
                        features: ["Microphone mode (FR-005)", "Microphone audio in recordings, only with Include microphone audio on (REC-004)"],
                        askedWhen: "The first time you choose Microphone mode, after an explanation.",
                        settingsCanChange: true,
                        hasDistinctRestrictedState: false),
        PermissionEntry(permission: .camera,
                        name: "Camera",
                        infoPlistKey: "NSCameraUsageDescription",
                        usageDescription: "The Camera visual shows the live view from the front or rear camera you choose, behind the visualization. The picture stays on your device: it is never sent, and it is saved only when you save a frame or record the visualization yourself.",
                        features: ["Camera visual (CAM-001, front camera CAM-002)"],
                        askedWhen: "The first time you choose the Camera visual in Settings.",
                        settingsCanChange: true,
                        hasDistinctRestrictedState: true),
        PermissionEntry(permission: .localNetwork,
                        name: "Local Network",
                        infoPlistKey: "NSLocalNetworkUsageDescription",
                        usageDescription: "When you turn on OSC receiver in Settings, projectM listens on your local network for OSC control messages. It never connects to the internet.",
                        features: ["OSC receiver (OSC-001)"],
                        askedWhen: "When you turn on OSC receiver in Settings.",
                        settingsCanChange: true,
                        hasDistinctRestrictedState: false),
        PermissionEntry(permission: .screenCapture,
                        name: "Screen recording (System/App Capture)",
                        infoPlistKey: "NSScreenCaptureUsageDescription",
                        usageDescription: "Only the audio of the content you choose to share is used, and only on this device. It is not recorded or sent anywhere.",
                        features: ["System/App Capture (FR-001)"],
                        askedWhen: "Each time you start System/App Capture, through iOS's own picker.",
                        settingsCanChange: false,
                        hasDistinctRestrictedState: true),
    ]

    /// The Photos library: no permission (MED-001, MED-002, REC-012).
    static let photosLibrary = "Choosing a photo or video needs no permission: the Photos picker runs outside the app and gives it only the item you pick."

    static func entry(_ permission: AppPermission) -> PermissionEntry {
        entries.first { (entry: PermissionEntry) -> Bool in entry.permission == permission }!
    }

    // MARK: Notices

    /// The Local Network denial (OSC-001-R17; moved here from OSCReceiverCoordinator).
    static let localNetworkDenied =
        "Local network access is off for projectM in Settings › Privacy & Security › Local Network."

    // MARK: Explainer and fallbacks (UIX-015; research D6)

    /// The camera notice's fallback (CAM-001's wording for a missing camera).
    static let cameraFallback = "Showing the spectrum only."
    /// The Local Network notice's fallback.
    static let localNetworkFallback = "OSC control is unavailable; everything else works as usual."
    /// The explainer's last line, before Continue and Not now.
    static let explainerNote = "iOS asks next. You can change this later in Settings."

    /// What happens if the user declines, said before iOS's prompt; nil where no explainer exists.
    static func explainerFallback(_ permission: AppPermission) -> String? {
        switch permission {
        case .camera: "If you don't allow it, the Camera visual shows the spectrum only."
        case .localNetwork: "If you don't allow it, OSC control stays unavailable and everything else works."
        case .microphone, .screenCapture: nil
        }
    }

    /// The decorative symbol of a permission's explainer.
    static func explainerSymbol(_ permission: AppPermission) -> String {
        switch permission {
        case .camera: "video"
        case .localNetwork: "network"
        case .microphone: "mic"
        case .screenCapture: "rectangle.on.rectangle"
        }
    }

    /// The notice for a denied or restricted permission; nil for notDetermined and granted.
    static func notice(_ permission: AppPermission, _ state: PermissionState) -> PermissionNotice? {
        guard state == .denied || state == .restricted else { return nil }
        let text: String
        switch permission {
        case .microphone:
            text = UIStrings.message(.permissionDenied)
        case .camera:
            text = (state == .restricted ? CameraFeedState.restricted.notice : CameraFeedState.denied.notice) ?? ""
        case .localNetwork:
            text = localNetworkDenied
        case .screenCapture:
            text = UIStrings.message(.screenRecordingNotAllowed)
        }
        let fallback: String? = switch permission {
        case .camera: cameraFallback
        case .localNetwork: localNetworkFallback
        case .microphone, .screenCapture: nil   // contract-fixed banners; Choose source is the fallback
        }
        return PermissionNotice(permission: permission, state: state, text: text,
                                offersSettings: entry(permission).settingsCanChange,
                                fallback: fallback, offersDismiss: permission == .camera)
    }

    /// The camera visual's notice: the catalog's for denied and restricted, otherwise CAM-001's notice
    /// for the feed state (no camera, paused) without Open Settings; nil when none is needed.
    /// CAM-002-R10: denied and restricted are the same for both cameras; no camera names the position.
    /// CAM-013-R2, R3: interrupted or failed name the reason and offer Retry; denied and restricted
    /// never offer Retry (R8).
    static func cameraNotice(for feed: CameraFeedState, position: CameraPosition = .back,
                             reason: CameraStopReason? = nil) -> PermissionNotice? {
        if let state = state(camera: feed), let notice = notice(.camera, state) { return notice }
        guard let text = feed.notice(position: position, reason: reason) else { return nil }
        return PermissionNotice(permission: .camera, state: nil, text: text, offersSettings: false,
                                offersRetry: feed.offersRetry)
    }

    // MARK: Mappings (plan D5)

    static func state(microphone: MicrophonePermission) -> PermissionState {
        switch microphone {
        case .undetermined: .notDetermined
        case .granted: .granted
        case .denied: .denied
        }
    }

    static func state(cameraAuthorization: AVAuthorizationStatus) -> PermissionState {
        switch cameraAuthorization {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .restricted: .restricted
        case .denied: .denied
        @unknown default: .denied   // as AVCameraFrameProvider
        }
    }

    /// Nil when the feed state says nothing about the permission (idle, no camera, paused, failed).
    static func state(camera: CameraFeedState) -> PermissionState? {
        switch camera {
        case .requestingAccess: .notDetermined
        case .starting, .running: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .idle, .unavailable, .interrupted, .failed: nil
        }
    }

    /// iOS has no Local Network query: listening proves access, a policy failure proves a denial,
    /// anything else is unknown (nil).
    static func state(localNetwork: OSCReceiverState) -> PermissionState? {
        switch localNetwork {
        case .listening: .granted
        case .failed(_, .localNetworkDenied): .denied
        default: nil
        }
    }

    /// Not allowed on this device (the picker's availability) is restricted; a declined picker or
    /// start (-3801) is denied; nil otherwise.
    static func state(screenCaptureAvailability availability: SourceAvailability, stopReason: StopReason?) -> PermissionState? {
        if availability == .unavailable(.screenRecordingNotAllowed) { return .restricted }
        if stopReason == .screenRecordingNotAllowed { return .denied }
        return nil
    }

    // MARK: Open Settings (plan D7)

    /// Opens the app's page in iOS Settings.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
