// UIStrings.swift — every user-visible source/status string, verbatim from
// specs/001-ios-projectm-visualizer/contracts/ui-states.md (English only).
// scripts/test_scripts.py cross-checks these literals against the contract on every CI run.
import AudioCore
import CaptureKit

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

    // MARK: Imported audio (AUD-001; specs/003-aud-001-import-drm-free-audio-files/contracts/ui-strings.md)
    public static let yourAudio = "Your Audio"
    public static let importAudio = "Import Audio…"
    public static let importing = "Importing…"
    public static let noImportedAudio = "No imported audio yet."
    public static let importedAudioFooter = "Imported tracks play as In-App Playback. Files are copied into the app and stay on this device."
    public static let remove = "Remove"
    public static let importedTrackHint = "Plays this track as In-App Playback."
    public static let importAlertTitle = "Import Audio"
    public static let ok = "OK"

    /// Why a picked file was not imported (AUD-001-R6, AUD-002-R7).
    public static func message(_ error: AudioImportError) -> String {
        switch error {
        case .notAudio: return "This file isn't a supported audio file."
        case .unreadable: return "This audio file can't be read. It may be damaged."
        case .protectedContent: return "This file is copy-protected (DRM) and can't be imported."
        case .tooLarge(let limitBytes): return "This file is too large. The limit is \(byteLimit(limitBytes))."
        case .unsupportedChannelCount: return "Only mono and stereo audio can be imported."
        case .insufficientStorage: return "There isn't enough storage on this device."
        case .sourceUnavailable: return "This file couldn't be opened."
        case .libraryUnavailable: return "Your audio library isn't available."
        // AUD-002-R7 (specs/006-aud-002-support-common-audio-containers/contracts/ui-strings.md)
        case .unsupportedFormat: return "This file's format isn't supported. Import MP3, AAC, M4A, WAV or AIFF audio."
        case .unsupportedEncoding: return "The audio in this file uses an encoding this device can't play."
        case .noAudio: return "This file contains no audio."
        }
    }

    /// Why the library cannot be used (AUD-001-R15).
    public static func message(_ unavailable: AudioLibraryState.Unavailable) -> String {
        switch unavailable {
        case .newerFormat: return "Your audio library was saved by a newer version of the app. Update the app to use it."
        case .storage: return "Your audio library couldn't be opened."
        }
    }

    /// A size limit in whole binary units: "500 MB", "97 KB".
    public static func byteLimit(_ bytes: Int64) -> String {
        let megabyte: Int64 = 1024 * 1024
        return bytes >= megabyte ? "\(bytes / megabyte) MB" : "\(max(1, bytes / 1024)) KB"
    }

    /// The result of one import, for the alert and the VoiceOver announcement: how many tracks were
    /// imported, then one line per duplicate and per failure in the order picked. Nil when nothing
    /// was picked.
    public static func importSummary(_ outcomes: [AudioImportOutcome]) -> String? {
        guard !outcomes.isEmpty else { return nil }
        var imported = 0
        var lines: [String] = []
        for outcome in outcomes {
            switch outcome {
            case .imported: imported += 1
            case .duplicate(let track): lines.append("“\(track.title)” is already in your library.")
            case .failed(let name, let error): lines.append("“\(name)”: \(message(error))")
            }
        }
        if imported == 1 { lines.insert("Imported 1 track.", at: 0) }
        if imported > 1 { lines.insert("Imported \(imported) tracks.", at: 0) }
        return lines.joined(separator: "\n")
    }

    /// True when the result must be shown: some file was a duplicate or was not imported.
    public static func importNeedsAlert(_ outcomes: [AudioImportOutcome]) -> Bool {
        outcomes.contains { if case .imported = $0 { return false } else { return true } }
    }

    /// A track's duration as shown: `m:ss`, or `h:mm:ss` from one hour.
    public static func duration(_ seconds: Double) -> String {
        let (hours, minutes, secs) = durationParts(seconds)
        let ss = secs < 10 ? "0\(secs)" : "\(secs)"
        guard hours > 0 else { return "\(minutes):\(ss)" }
        return "\(hours):\(minutes < 10 ? "0\(minutes)" : "\(minutes)"):\(ss)"
    }

    /// A track's duration as VoiceOver reads it: "3 minutes 5 seconds".
    public static func spokenDuration(_ seconds: Double) -> String {
        let (hours, minutes, secs) = durationParts(seconds)
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if secs > 0 || parts.isEmpty { parts.append(secs == 1 ? "1 second" : "\(secs) seconds") }
        return parts.joined(separator: " ")
    }

    public static func trackAccessibilityLabel(_ track: ImportedTrack) -> String {
        "\(track.title), \(spokenDuration(track.durationSeconds))"
    }

    private static func durationParts(_ seconds: Double) -> (hours: Int, minutes: Int, seconds: Int) {
        guard seconds.isFinite, seconds > 0 else { return (0, 0, 0) }
        let total = Int(min(seconds, 359_999))   // below 100 hours
        return (total / 3600, (total % 3600) / 60, total % 60)
    }

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
