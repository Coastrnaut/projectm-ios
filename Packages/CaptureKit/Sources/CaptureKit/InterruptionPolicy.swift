// InterruptionPolicy.swift — when interrupted audio may resume (AUD-014-T11; AUD-014-R1 to R9;
// specs/009-aud-014-audio-session-interruption-recovery/contracts/interruption-policy.md).
//
// One pure decision over everything that matters after an audio-session interruption, a change of
// the audio hardware or a media-services reset: resume, stay paused, stay stopped, or fail with a
// visible reason. It holds no state and touches no audio; CaptureManager (which remembers the open
// interruption) and the In-App Playback backend (after an engine restart) ask it.
//
// In-App Playback resumes only when all of this holds (AUD-014-R2): it can still be used; it was
// playing before; nobody holds it paused (not the user, and not the system because the output
// was lost); the user did not change the transport meanwhile; iOS indicated that audio may resume,
// or there was no interruption at all; and the app is in the foreground and unlocked.
//
// Microphone and System/App Capture: the rows state what feature 001 already does (FR-050,
// FR-051, FR-055; ADR-0001). CaptureManager's code for them is not routed through this type and
// did not change (AUD-014-R9).
import AudioCore

public enum InterruptionPolicy {
    public enum Source: Sendable, Equatable, CaseIterable {
        case inAppPlayback, microphone, systemAppCapture

        public init(_ mode: AudioSourceMode) {
            switch mode {
            case .inAppPlayback: self = .inAppPlayback
            case .microphone: self = .microphone
            case .systemAppCapture: self = .systemAppCapture
            }
        }
    }

    /// The transport before the interruption. Being held only by the app lifecycle (background,
    /// lock) is not a pause: that is `playing` with `isPresentable` false.
    public enum Transport: Sendable, Equatable, CaseIterable {
        case playing, paused, stopped
    }

    /// Who holds playback paused now. `system`: the output route was lost.
    public enum PausedBy: Sendable, Equatable, CaseIterable {
        case nobody, user, system
    }

    /// What iOS has indicated so far.
    public enum SystemSignal: Sendable, Equatable, CaseIterable {
        /// No interruption is involved (a hardware change, a media-services reset).
        case notInterrupted
        /// The interruption began and has not ended.
        case pending
        case endedWithoutResume
        case endedShouldResume
    }

    public struct Input: Sendable, Equatable {
        public var source: Source
        public var before: Transport
        public var pausedBy: PausedBy
        public var signal: SystemSignal
        /// The app is in the foreground and unlocked.
        public var isPresentable: Bool
        /// The user paused, stopped playback, sought or changed the track during the interruption.
        public var userChangedTransport: Bool
        /// The source can still play or capture (false: its engine could not be rebuilt).
        public var sourceIsUsable: Bool

        public init(source: Source, before: Transport, pausedBy: PausedBy, signal: SystemSignal, isPresentable: Bool,
                    userChangedTransport: Bool, sourceIsUsable: Bool) {
            self.source = source
            self.before = before
            self.pausedBy = pausedBy
            self.signal = signal
            self.isPresentable = isPresentable
            self.userChangedTransport = userChangedTransport
            self.sourceIsUsable = sourceIsUsable
        }
    }

    /// Why playback stays paused.
    public enum Hold: Sendable, Equatable, CaseIterable {
        /// The user paused; only the user continues.
        case user
        /// The output route was lost ("Paused — audio route changed").
        case outputDisconnected
        /// The interruption is open, ended without a resume indication, or the user took over.
        case interrupted
        /// A resume is permitted but the app is not in the foreground: ask again when it is.
        case notPresentable
    }

    public enum Decision: Sendable, Equatable {
        case resume
        case stayPaused(Hold)
        case stayStopped
        case fail(StopReason)
        /// The source is not governed by the audio session (System/App Capture): nothing changes.
        case notApplicable
    }

    /// The contract's rules, in order; the first that matches decides.
    public static func decide(_ input: Input) -> Decision {
        guard input.source != .systemAppCapture else { return .notApplicable }
        guard input.sourceIsUsable else {
            return .fail(input.source == .microphone ? .microphoneUnavailable : .inAppPlaybackFailed)
        }
        if input.before == .stopped { return .stayStopped }
        let resumeIndicated = input.signal == .endedShouldResume || input.signal == .notInterrupted

        if input.source == .microphone {
            if input.before == .paused { return .stayStopped }       // Microphone has no pause
            guard resumeIndicated else { return .stayPaused(.interrupted) }
            return input.isPresentable ? .resume : .stayPaused(.notPresentable)
        }

        switch input.pausedBy {
        case .user: return .stayPaused(.user)
        case .system: return .stayPaused(.outputDisconnected)
        case .nobody: break
        }
        if input.before == .paused { return .stayPaused(.user) }
        if input.userChangedTransport || !resumeIndicated { return .stayPaused(.interrupted) }
        return input.isPresentable ? .resume : .stayPaused(.notPresentable)
    }
}
