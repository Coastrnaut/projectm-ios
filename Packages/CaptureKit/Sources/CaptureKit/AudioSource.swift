// AudioSource.swift — the source contract (task T028; contracts/audio-source.md).
import AudioCore

/// Events a running source reports to the CaptureManager.
public enum SourceEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// In-App Playback lost its output route (e.g. headphones unplugged); the source paused itself.
    case outputRouteLost
    /// The source stopped for a non-user reason (e.g. microphone no longer available).
    case failed(StopReason)
    /// The OS ended the capture session (System/App Capture).
    case endedBySystem(String?)
    case formatChanged
}

/// Error thrown by `start`/`resume`, carrying the user-visible reason (FR-015).
public struct SourceError: Error, Equatable, Sendable {
    public let reason: StopReason
    public init(_ reason: StopReason) { self.reason = reason }
}

/// A selectable origin of audio.
///
/// Guarantees (contracts/audio-source.md):
/// 1. `start` presents the system picker (capture) or the permission prompt (microphone) only
///    when called from a user action; a source never starts silently (FR-002).
/// 2. Real-time callbacks write only to `PCMSink`, which is allocation-free and lock-free. They
///    never call async code, log, or touch the main actor.
/// 3. `stop()` is idempotent and safe to call while a `start` is in flight (FR-052).
/// 4. After `stop()` returns, the source holds no reference to the sink and delivers no audio.
/// 5. Platform types (ScreenCaptureKit, CMSampleBuffer, AVAudioPCMBuffer) never cross this boundary.
@MainActor
public protocol AudioSource: AnyObject {
    var mode: AudioSourceMode { get }
    var availability: SourceAvailability { get }
    /// Starts the source and returns this session's event stream. Throws `SourceError`.
    func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent>
    /// Stops within 1 s (FR-007). Idempotent.
    func stop() async
    /// Suspends for backgrounding/lock (FR-050, FR-054). System/App Capture keeps running.
    func suspend() async
    /// Resumes after `suspend` or a lost route; re-checks permissions (FR-053). Throws `SourceError`.
    func resume() async throws
}

/// Sources that may know which content the OS selected (FR-014). Shown only after Active audio
/// is verified; see `CaptureManager.displayedContentIdentity`.
@MainActor
public protocol ContentIdentifying: AnyObject {
    var contentIdentity: String? { get }
}

/// App-level lifecycle inputs (LifecycleObserver, FR-050–FR-054).
public enum AppLifecycleEvent: String, Sendable {
    case background
    case foreground
    case lock
    case unlock
}

/// A format observed during a session (export `formats`).
public struct FormatObservation: Sendable, Equatable {
    public var format: AudioFormat
    public var firstSeenSeconds: Double
}

/// Entry for the export's `lifecycleEvents` (schema enum names).
public struct LifecycleLogEntry: Sendable, Equatable {
    public var atSeconds: Double
    public var event: String
}
