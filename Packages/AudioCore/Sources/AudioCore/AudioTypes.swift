// AudioTypes.swift — shared audio vocabulary (task T023; data-model.md).

/// The three source modes (FR-001). Raw values match the diagnostics export schema.
public enum AudioSourceMode: String, Sendable, CaseIterable, Codable, Hashable {
    case systemAppCapture
    case microphone
    case inAppPlayback
}

/// Truthfulness status of the active source (FR-010). Raw values match the export schema.
public enum AudioState: String, Sendable, CaseIterable, Codable {
    case notStarted
    case waiting
    case noAudioReceived
    case silent
    case active
    case paused
    case interrupted
    case stopped
    case endedBySystem

    /// States in which the source is running and audio is being classified.
    public var isRunning: Bool {
        switch self {
        case .waiting, .noAudioReceived, .silent, .active: return true
        default: return false
        }
    }
}

/// Why a source stopped or failed (FR-015).
public enum StopReason: Sendable, Equatable, Hashable, Codable {
    case cancelled
    case permissionDenied
    case microphoneUnavailable
    case inAppPlaybackFailed
    case interrupted
    case audioRouteChanged
    case endedBySystem
    case unsupportedOS
    /// System/App Capture: the user declined screen recording (SCStreamError -3801), or the OS
    /// reports that screen recording is not allowed on this device (owner ruling 2026-11-08).
    case screenRecordingNotAllowed
    case error(String)

    /// Stable code used in exports and UI-string lookup.
    public var code: String {
        switch self {
        case .cancelled: return "cancelled"
        case .permissionDenied: return "permissionDenied"
        case .microphoneUnavailable: return "microphoneUnavailable"
        case .inAppPlaybackFailed: return "inAppPlaybackFailed"
        case .interrupted: return "interrupted"
        case .audioRouteChanged: return "audioRouteChanged"
        case .endedBySystem: return "endedBySystem"
        case .unsupportedOS: return "unsupportedOS"
        case .screenRecordingNotAllowed: return "screenRecordingNotAllowed"
        case .error: return "error"
        }
    }
}

public enum SampleType: String, Sendable, Codable {
    case float32
    case int16
    case int32
}

/// The format of incoming audio as delivered by the source (data-model.md §AudioFormat).
/// "channelCount ≥ 1". Streams with more than 2 channels are downmixed in Plan Phase B (FR-017).
public struct AudioFormat: Sendable, Equatable, Hashable, Codable {
    public var sampleRate: Double
    public var channelCount: Int
    public var isInterleaved: Bool
    public var sampleType: SampleType

    public init(sampleRate: Double, channelCount: Int, isInterleaved: Bool, sampleType: SampleType) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.isInterleaved = isInterleaved
        self.sampleType = sampleType
    }

    public var isValid: Bool { sampleRate > 0 && channelCount >= 1 }
}

/// Whether a mode can be offered on this device (FR-004).
public enum SourceAvailability: Sendable, Equatable {
    case available
    case unavailable(StopReason)
}

/// Lifecycle inputs to the classifier (data-model.md §Transitions).
public enum LifecycleEvent: Sendable, Equatable {
    /// The source started successfully.
    case started
    /// The source failed to start; state returns to Not started.
    case startFailed(StopReason)
    /// The user stopped the source (FR-007).
    case userStopped
    /// The source stopped for a non-user reason (e.g. microphone lost).
    case failed(StopReason)
    /// The app suspended the source: background, device lock, or lost output route (FR-050, FR-054).
    case suspended
    /// A suspended source resumed.
    case resumed
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// The OS ended the capture session (US6-AS3).
    case endedBySystem
}

/// Tunable thresholds (spec Assumptions). Finalized in the Stage 1 report (task T054).
public struct ClassifierThresholds: Sendable, Equatable {
    /// "peak ≥ −50 dBFS for ≥ 250 ms" → Active audio (FR-011).
    public var activePeakDBFS: Float
    public var activeMinDuration: Double
    /// "peak < −60 dBFS for ≥ 2 s" → Audio received — silent (FR-011).
    public var silentPeakDBFS: Float
    public var silentMinDuration: Double
    /// No audio data for this long → No audio received (FR-012).
    public var noAudioTimeout: Double
    /// Silent this long → prolonged-silence hint (FR-018).
    public var prolongedSilenceHint: Double

    public init(activePeakDBFS: Float = -50, activeMinDuration: Double = 0.25,
                silentPeakDBFS: Float = -60, silentMinDuration: Double = 2,
                noAudioTimeout: Double = 5, prolongedSilenceHint: Double = 60) {
        self.activePeakDBFS = activePeakDBFS
        self.activeMinDuration = activeMinDuration
        self.silentPeakDBFS = silentPeakDBFS
        self.silentMinDuration = silentMinDuration
        self.noAudioTimeout = noAudioTimeout
        self.prolongedSilenceHint = prolongedSilenceHint
    }

    public static let `default` = ClassifierThresholds()
}

/// A recorded state change, for the export's `stateTransitions` (schema max 1000 items).
public struct StateTransition: Sendable, Equatable, Codable {
    public var atSeconds: Double
    public var state: AudioState
    public var reason: String?

    public init(atSeconds: Double, state: AudioState, reason: String? = nil) {
        self.atSeconds = atSeconds
        self.state = state
        self.reason = reason
    }
}
