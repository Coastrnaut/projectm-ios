// RecordingAudioPolicy.swift — REC-004 which audio a recording may contain (REC-004-R1, R2, R4;
// specs/134-rec-004-recording-audio, contracts/recording-audio.md C1, ADR-0053). Plain Swift; builds on Linux.
//
// Only audio the app owns (In-App Playback: files imported into the app's library, which the import
// refuses when protected) or the user consented to (the Microphone, with the system permission and the
// "Include microphone audio" setting) is written. Other apps' audio (System/App Capture) never is.
// The decision is made once, at Record, and fixes whether the file gets an audio track.

/// The audio source a recording would take its sound from (the app maps its source modes to it).
public enum RecordingAudioSourceKind: String, Sendable, Equatable, CaseIterable {
    case inAppPlayback
    case microphone
    case systemCapture
}

/// What a recording's audio is.
public enum RecordingAudioDecision: Sendable, Equatable, Hashable {
    public enum Included: String, Sendable, Equatable, Hashable, CaseIterable {
        case appAudio
        case microphone
    }

    public enum Excluded: String, Sendable, Equatable, Hashable, CaseIterable {
        case otherAppsAudio
        case microphoneSettingOff
        case microphonePermissionMissing
        case noSource
    }

    case include(Included)
    case exclude(Excluded)

    /// True when the file gets an audio track.
    public var includesAudio: Bool {
        if case .include = self { return true }
        return false
    }

    /// The audio status shown and announced (data-model.md).
    public var statusText: String {
        switch self {
        case .include(.appAudio): "Recording includes app audio."
        case .include(.microphone): "Recording includes microphone audio."
        case .exclude(.otherAppsAudio): "Recording has no audio: other apps' audio is never recorded."
        case .exclude(.microphoneSettingOff): "Recording has no audio: Include microphone audio is off."
        case .exclude(.microphonePermissionMissing): "Recording has no audio: microphone permission is off."
        case .exclude(.noSource): "Recording has no audio."
        }
    }

    /// The text after the audio ended early in a recording (REC-004-R5).
    public static let endedText = "Recording audio ended."
}

public enum RecordingAudioPolicy {
    /// Contract C1. System/App Capture is excluded whatever the other values (REC-004-R2).
    public static func decide(source: RecordingAudioSourceKind?, includeMicrophone: Bool,
                              microphoneGranted: Bool) -> RecordingAudioDecision {
        switch source {
        case .inAppPlayback: return .include(.appAudio)
        case .systemCapture: return .exclude(.otherAppsAudio)
        case .microphone:
            if !microphoneGranted { return .exclude(.microphonePermissionMissing) }
            if !includeMicrophone { return .exclude(.microphoneSettingOff) }
            return .include(.microphone)
        case nil: return .exclude(.noSource)
        }
    }
}
