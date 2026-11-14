// BackgroundPolicy.swift — what happens to the active source when the app is away (AUD-015-R1;
// specs/097-aud-015-background-playback-policy/contracts/background-policy.md, ADR-0036).
//
// "Away" means the app is in the background, the device is locked, or both. The app declares only
// the `screen-capture` background mode (ADR-0001 ruling 17), so iOS suspends its audio shortly after
// it leaves the foreground. The policy:
//
// | Source             | Foreground and unlocked | Away                                                    |
// |--------------------|-------------------------|---------------------------------------------------------|
// | Microphone         | run                     | stopCapture, always (no covert capture)                 |
// | In-App Playback    | run                     | continuePlayback only with the audio mode AND the       |
// |                    |                         | user's wish to keep playing; otherwise pausePlayback    |
// | System/App Capture | run                     | followSystem (the screen-capture mode; a lock ends it)  |
//
// Automatic resume (FR-050) is allowed only when the app is in the foreground and unlocked, and
// never for System/App Capture, which restarts only through the system picker (FR-055). Pure Swift:
// no platform types, so the table is tested on Linux too.
import AudioCore

public enum BackgroundPolicy {
    /// What the app is entitled to and what the user intended.
    public struct Configuration: Sendable, Equatable {
        /// Info.plist `UIBackgroundModes` contains `audio`.
        public var declaresAudioBackgroundMode: Bool
        /// The user asked In-App Playback to keep playing in the background.
        public var keepPlayingInBackground: Bool

        public init(declaresAudioBackgroundMode: Bool, keepPlayingInBackground: Bool) {
            self.declaresAudioBackgroundMode = declaresAudioBackgroundMode
            self.keepPlayingInBackground = keepPlayingInBackground
        }

        /// The app as shipped: no `audio` mode and no "keep playing" setting (AUD-015-R3).
        public static let shipped = Configuration(declaresAudioBackgroundMode: false, keepPlayingInBackground: false)
    }

    public struct Context: Sendable, Equatable {
        public var mode: AudioSourceMode
        public var isBackgrounded: Bool
        public var isLocked: Bool
        public var configuration: Configuration

        public init(mode: AudioSourceMode, isBackgrounded: Bool, isLocked: Bool, configuration: Configuration) {
            self.mode = mode
            self.isBackgrounded = isBackgrounded
            self.isLocked = isLocked
            self.configuration = configuration
        }

        /// In the background, locked, or both.
        public var isAway: Bool { isBackgrounded || isLocked }
    }

    public enum Action: String, Sendable, Equatable {
        /// The app is in the foreground and unlocked: the source runs as the user left it.
        case run
        /// In-App Playback pauses at its position.
        case pausePlayback
        /// The microphone engine stops; nothing is captured.
        case stopCapture
        /// In-App Playback keeps playing (entitled and intended only).
        case continuePlayback
        /// System/App Capture: the app does nothing; the system decides.
        case followSystem
    }

    public enum Reason: String, Sendable, Equatable {
        case foreground
        case playbackPausedInBackground
        case playbackContinuesInBackground
        case microphoneStoppedInBackground
        case systemCaptureFollowsSystem

        /// The notice shown on return (AUD-015-R7); nil when nothing needs explaining.
        public var notice: String? {
            switch self {
            case .playbackPausedInBackground:
                return "Playback paused while projectM-iOS was in the background."
            case .microphoneStoppedInBackground:
                return "The microphone was off while projectM-iOS was in the background. It never listens in the background."
            case .foreground, .playbackContinuesInBackground, .systemCaptureFollowsSystem:
                return nil
            }
        }
    }

    public struct Decision: Sendable, Equatable {
        public let action: Action
        public let reason: Reason
    }

    public static func decide(_ context: Context) -> Decision {
        guard context.isAway else { return Decision(action: .run, reason: .foreground) }
        switch context.mode {
        case .microphone:
            // Whatever the background modes: the microphone never listens while the app is away.
            return Decision(action: .stopCapture, reason: .microphoneStoppedInBackground)
        case .inAppPlayback:
            let entitled: Bool = context.configuration.declaresAudioBackgroundMode
            let intended: Bool = context.configuration.keepPlayingInBackground
            if entitled && intended {
                return Decision(action: .continuePlayback, reason: .playbackContinuesInBackground)
            }
            return Decision(action: .pausePlayback, reason: .playbackPausedInBackground)
        case .systemAppCapture:
            return Decision(action: .followSystem, reason: .systemCaptureFollowsSystem)
        }
    }

    /// True when a source the app paused may resume by itself (FR-050): in the foreground and
    /// unlocked, and not System/App Capture.
    public static func mayResumeAutomatically(_ context: Context) -> Bool {
        !context.isAway && context.mode != .systemAppCapture
    }

    /// Reads Info.plist's `UIBackgroundModes` values.
    public static func declaresAudioMode(in backgroundModes: [String]) -> Bool {
        backgroundModes.contains("audio")
    }
}
