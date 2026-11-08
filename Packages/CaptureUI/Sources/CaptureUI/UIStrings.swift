// UIStrings.swift — every user-visible source/status string, verbatim from
// specs/001-ios-projectm-visualizer/contracts/ui-states.md (English only).
// scripts/test_scripts.py cross-checks these literals against the contract on every CI run.
import AudioCore

public enum UIStrings {
    // MARK: Source labels (FR-013)
    public static func label(_ mode: AudioSourceMode) -> String {
        switch mode {
        case .systemAppCapture: return "System/App Capture"
        case .microphone: return "Microphone"
        case .inAppPlayback: return "In-App Playback"
        }
    }

    // MARK: Source chooser descriptions (FR-080)
    public static func description(_ mode: AudioSourceMode) -> String {
        switch mode {
        case .systemAppCapture: return "Visualize audio from content you choose to share, where iOS allows it."
        case .microphone: return "Visualize sound in the room through the microphone."
        case .inAppPlayback: return "Visualize the built-in reference track."
        }
    }

    public static let unavailableNewerIOS = "Requires a newer iOS version"

    // MARK: Microphone explainer (FR-005); also the NSMicrophoneUsageDescription text (FR-019)
    public static let microphoneExplainer = "Microphone mode listens to sound in the room through your device's microphone. It does not capture audio directly from other apps."

    // MARK: Audio states (FR-010)
    public static func state(_ state: AudioState) -> String {
        switch state {
        case .notStarted: return "Not started"
        case .waiting: return "Waiting"
        case .noAudioReceived: return "No audio received"
        case .silent: return "Audio received — silent"
        case .active: return "Active audio"
        case .paused: return "Paused"
        case .interrupted: return "Interrupted"
        case .stopped: return "Stopped"
        case .endedBySystem: return "Ended by system"
        }
    }

    /// Accessibility hint for a chooser row: the actual reason when unavailable (e.g. the iOS version
    /// or "Screen recording not allowed", FR-004), otherwise the mode's description.
    public static func chooserHint(_ availability: SourceAvailability, mode: AudioSourceMode) -> String {
        if case .unavailable(let reason) = availability { return message(reason) }
        return description(mode)
    }

    // MARK: Stop/failure reasons (FR-015)
    public static func message(_ reason: StopReason) -> String {
        switch reason {
        case .cancelled: return "Not started — cancelled"
        case .permissionDenied: return "Microphone permission denied. Enable it in Settings › Privacy › Microphone."
        case .microphoneUnavailable: return "Microphone unavailable"
        case .inAppPlaybackFailed: return "In-App Playback failed"
        case .interrupted: return "Interrupted"
        case .audioRouteChanged: return "Paused — audio route changed"
        case .endedBySystem: return "Ended by system"
        case .unsupportedOS: return "Requires a newer iOS version"
        case .screenRecordingNotAllowed: return "Screen recording not allowed"
        case .error(let description): return "Something went wrong: \(description)"
        }
    }

    // MARK: Hints
    public static let noAudioHint = "No audio received. Try another source or use Microphone."
    public static let prolongedSilenceHint = "No sound detected — is playback paused?"

    // MARK: Diagnostics export (FR-021)
    public static let exportNotePlaceholder = "Optional note, e.g. which app was playing. Do not enter personal information."

    // MARK: Actions
    public static let chooseSource = "Choose source"
    public static let chooseAudioSource = "Choose Audio Source"
    public static let restart = "Restart"
    public static let resume = "Resume"
    public static let openSettings = "Open Settings"
    public static let stop = "Stop"
    public static let continueAction = "Continue"
    public static let cancel = "Cancel"
}

/// Banner actions per StopReason (contracts/ui-states.md §Stop/failure reasons).
public enum BannerAction: String, Sendable, CaseIterable {
    case chooseSource, openSettings, restart, resume

    public var title: String {
        switch self {
        case .chooseSource: return UIStrings.chooseSource
        case .openSettings: return UIStrings.openSettings
        case .restart: return UIStrings.restart
        case .resume: return UIStrings.resume
        }
    }

    public static func actions(for reason: StopReason) -> [BannerAction] {
        switch reason {
        case .cancelled, .microphoneUnavailable, .inAppPlaybackFailed, .unsupportedOS: return [.chooseSource]
        case .permissionDenied: return [.openSettings, .chooseSource]
        case .interrupted, .endedBySystem, .screenRecordingNotAllowed, .error: return [.restart, .chooseSource]
        case .audioRouteChanged: return [.resume, .chooseSource]
        }
    }
}
