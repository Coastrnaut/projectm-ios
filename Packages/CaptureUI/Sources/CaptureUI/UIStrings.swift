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

    // MARK: Queue (AUD-003; specs/015-aud-003-audio-library-queue/contracts/ui-strings.md)
    public static let queue = "Queue"
    public static let queueHint = "Shows and edits the order of imported tracks."
    public static let upNext = "Up Next"
    public static let notInQueue = "Not in Queue"
    public static let queueEmpty = "Nothing is queued. Add tracks below."
    public static let queueFooter = "Next track and the end of a track follow this order. Removing a track from the queue keeps it in Your Audio."
    public static let nowPlaying = "Now Playing"
    public static let currentTrack = "Current"
    public static let playQueue = "Play Queue"
    public static let playNext = "Play Next"
    public static let addToQueue = "Add to Queue"
    public static let removeFromQueue = "Remove from Queue"
    public static let moveUp = "Move Up"
    public static let moveDown = "Move Down"
    public static let clearQueue = "Clear Queue"
    public static let clearQueueConfirm = "Clear the queue? Tracks stay in Your Audio."
    public static let done = "Done"

    /// The chooser's queue row: "Queue, 3 tracks".
    public static func queueRowLabel(count: Int) -> String {
        switch count {
        case 0: return "Queue, empty"
        case 1: return "Queue, 1 track"
        default: return "Queue, \(count) tracks"
        }
    }

    /// A queued track's place: "2 of 3".
    public static func queuePosition(_ position: Int, of count: Int) -> String {
        "\(position) of \(count)"
    }

    /// What VoiceOver reads for a queue row: "Song, 1 minute 5 seconds, 2 of 3, Now Playing".
    public static func queueRowAccessibilityLabel(title: String, durationSeconds: Double, position: Int, count: Int,
                                                  marker: String?) -> String {
        var parts = [title, spokenDuration(durationSeconds), queuePosition(position, of: count)]
        if let marker { parts.append(marker) }
        return parts.joined(separator: ", ")
    }

    public static func queueMovedAnnouncement(title: String, position: Int, count: Int) -> String {
        "\(title), now \(queuePosition(position, of: count))"
    }

    public static func queueAddedAnnouncement(title: String) -> String { "\(title) added to the queue" }
    public static func playNextAnnouncement(title: String) -> String { "\(title) plays next" }
    public static func queueRemovedAnnouncement(title: String) -> String { "\(title) removed from the queue" }

    // MARK: Transport (AUD-006; specs/007-aud-006-seekable-transport/contracts/ui-strings.md)
    public static let transportPlay = "Play"
    public static let transportPause = "Pause playback"
    public static let transportStop = "Stop playback"
    public static let previousTrack = "Previous track"
    public static let nextTrack = "Next track"
    public static let transportScrubber = "Playback position"
    public static let referenceTrackTitle = "Reference track"
    /// How far the VoiceOver increment and decrement gestures move the scrubber (AUD-006-R26).
    public static let scrubStepSeconds = 10.0

    /// The Play/Pause button's label: what a tap does.
    public static func transportPlayPause(isPlaying: Bool) -> String {
        isPlaying ? transportPause : transportPlay
    }

    /// Elapsed time as shown: `m:ss`, or `h:mm:ss` from one hour.
    public static func elapsedTime(_ seconds: Double) -> String {
        duration(seconds)
    }

    /// Remaining time as shown, with a minus sign: "−1:05". Whole seconds, so that elapsed plus
    /// remaining is the track's length.
    public static func remainingTime(elapsed: Double, duration total: Double) -> String {
        let whole = elapsed.isFinite ? max(0, elapsed.rounded(.down)) : 0
        return "−" + duration(max(0, (total.isFinite ? total : 0) - whole))
    }

    /// What VoiceOver reads for the scrubber: "1 minute 5 seconds of 3 minutes".
    public static func scrubberValue(elapsed: Double, duration total: Double) -> String {
        "\(spokenDuration(elapsed)) of \(spokenDuration(total))"
    }

    // MARK: In-App Playback on hold (AUD-014; specs/009-aud-014-audio-session-interruption-recovery/contracts/ui-strings.md)
    public static let playbackInterruptedDetail = "Playback is on hold at its position. It continues when iOS allows it, or press Play."
    public static let playbackOutputDisconnectedDetail = "The audio output was disconnected. Press Play to continue."

    /// The explanation shown under the feature 001 message while In-App Playback is interrupted or
    /// was paused by a disconnected output (AUD-014-R17). Nil for every other reason and for
    /// Microphone and System/App Capture, whose texts do not change (AUD-014-R19).
    public static func playbackHoldDetail(mode: AudioSourceMode?, reason: StopReason?) -> String? {
        guard mode == .inAppPlayback else { return nil }
        switch reason {
        case .interrupted: return playbackInterruptedDetail
        case .audioRouteChanged: return playbackOutputDisconnectedDetail
        default: return nil
        }
    }

    /// What VoiceOver announces when In-App Playback goes on hold (AUD-014-R18): `status` (the
    /// source-and-state indicator's text), then the explanation. Nil when there is no explanation.
    public static func playbackHoldAnnouncement(status: String, mode: AudioSourceMode?, reason: StopReason?) -> String? {
        playbackHoldDetail(mode: mode, reason: reason).map { "\(status). \($0)" }
    }

    // MARK: Test signals (AUD-016; specs/011-aud-016-reference-tone-suite/contracts/ui-strings.md)
    public static let diagnostics = "Diagnostics"
    public static let testSignals = "Test Signals"
    public static let testSignalsRowDetail = "Generated tones, sweeps, pulses and silence for checking the visualizer."
    public static let testSignalsFooter = "These test signals are generated on this device for checking the visualizer. They are not music. Lower the volume before you start one. Each plays as In-App Playback and repeats until you stop it."
    public static let testSignalHint = "Plays this test signal as In-App Playback."

    /// The source-and-state indicator's text (FR-013, FR-042): "In-App Playback · Active audio", or
    /// with a test signal playing "In-App Playback · Test tone 1 kHz · Active audio" (AUD-016-R16).
    /// A signal name is shown only with In-App Playback, the only mode that plays one.
    public static func sourceStatus(mode: AudioSourceMode?, state: AudioState, signal: String?) -> String {
        let label = mode.map(UIStrings.label) ?? "No source"
        if mode == .inAppPlayback, let signal { return "\(label) · \(signal) · \(UIStrings.state(state))" }
        return "\(label) · \(UIStrings.state(state))"
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
