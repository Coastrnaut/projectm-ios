// InAppPlaybackSource.swift — deterministic In-App Playback fallback (task T046; FR-006, FR-051, FR-069).
//
// Plays the bundled reference track (scripts/generate_reference_audio.py), a track from the
// user's imported library (AUD-001), or a generated reference tone (AUD-016), audibly through the current output, and taps the app's own
// mix. Without a transport a track repeats until stopped; PlaybackTransport (AUD-006) adds pause,
// seek and track changes through the members at the end of this file. Never opens an input. Every track is In-App Playback: the mode and
// its label do not change with the track (Constitution IV, AUD-001-R18).
import AudioCore
import Foundation

/// What In-App Playback plays.
public enum InAppPlaybackTrack: Sendable, Hashable {
    /// The bundled reference track (FR-006).
    case reference
    /// A file in the app's own audio library (`AudioLibrary.fileURL(for:)`). Never a picked or
    /// security-scoped URL, and never persisted (AUD-001-R3).
    case file(URL)
    /// A reference-tone fixture, generated in memory at 48 kHz stereo when it is loaded and played
    /// as a 10 s loop (AUD-016-R15, R19, R23). Never written to disk and never persisted.
    case tone(ReferenceToneFixture)
}

/// Platform seam (AVAudioEngine + AVAudioPlayerNode in production, a fake in tests).
///
/// Transport guarantees (AUD-006; specs/007-aud-006-seekable-transport/contracts/transport.md):
/// 1. `pause()` holds the position and `resume()` continues from it.
/// 2. After `seek`, `replaceTrack` and `resume`, the first audio written to the sink is the
///    track's audio at the new position; nothing from before the call is written or left
///    downstream (the backend calls the sink's `discardBufferedAudio()`).
/// 3. A track that loops never ends; one that does not calls `onTrackEnded` once at its end.
@MainActor
public protocol InAppPlaybackBackend: AnyObject {
    /// Loads `track` and starts playback at its start, tapping the mix into `sink`. Throws
    /// `SourceError` when the track cannot be played; it never plays a different track instead
    /// (AUD-001-R19).
    func start(track: InAppPlaybackTrack, sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws
    func stop()
    func pause()
    func resume() throws

    /// True (the default): the current track repeats without a gap and never ends. False: it
    /// plays to its end once, then `onTrackEnded` is called. Set before `start` or `replaceTrack`.
    var loopsCurrentTrack: Bool { get set }
    /// Called when a track that does not loop has reached its end while playing.
    var onTrackEnded: (@MainActor () -> Void)? { get set }
    /// Where playback is; `.zero` when not started.
    var position: PlaybackPosition { get }
    /// Moves to `seconds` (limited to the track). Playing continues from there, paused stays paused.
    func seek(to seconds: Double)
    /// Changes to `track` at its start, keeping playing or paused. Throws
    /// `SourceError(.inAppPlaybackFailed)` when it cannot be loaded; the old track is then silent
    /// and no other track is played (AUD-006-R19).
    func replaceTrack(_ track: InAppPlaybackTrack) throws
    /// AUD-003: the current track now repeats (`loops` true) or ends, at once: the position is
    /// kept, nothing is cut and the playing, paused or held state stays. While paused or held only
    /// the flag changes.
    func updateLooping(_ loops: Bool)
    /// AUD-004: false while a track that played to its end may still have frames on their way to the
    /// sink (at most one tap block); the transport waits for it before stopping at the end.
    var hasDeliveredTrackEnd: Bool { get }
    /// AUD-010: the monitoring balance, −1 (left) … +1 (right), already validated. Changes what is
    /// heard only, never what reaches the sink; applies at once and to every later track and graph.
    func setMonitorBalance(_ balance: Double)
}

extension InAppPlaybackBackend {
    /// For backends without a live update (scripted test backends): the flag only.
    public func updateLooping(_ loops: Bool) {
        loopsCurrentTrack = loops
    }

    /// For backends whose tap delivers at once (scripted test backends).
    public var hasDeliveredTrackEnd: Bool { true }

    /// For backends that play nothing aloud (scripted test backends).
    public func setMonitorBalance(_ balance: Double) {}
}

@MainActor
public final class InAppPlaybackSource: AudioSource {
    public let mode: AudioSourceMode = .inAppPlayback
    private let backend: any InAppPlaybackBackend
    private var continuation: AsyncStream<SourceEvent>.Continuation?
    private var running = false
    /// The track the next `start` plays. Changing it while running takes effect at the next start
    /// (a restart through CaptureManager starts the same track again); `replaceTrack` changes the
    /// playing track and this value together.
    public var track: InAppPlaybackTrack = .reference
    /// Successful starts so far. The transport uses it to tell sessions apart (AUD-006).
    public private(set) var sessionCount = 0
    /// AUD-010: the monitoring balance (validated, `MonitorBalance`), forwarded to the backend on
    /// every set, whether or not a session runs. In-App Playback only: no other source plays aloud.
    public var monitorBalance: Double = 0 {
        didSet {
            let valid = MonitorBalance.validated(monitorBalance)
            if valid != monitorBalance || monitorBalance.isNaN { monitorBalance = valid }
            backend.setMonitorBalance(valid)
        }
    }

    public init(backend: any InAppPlaybackBackend) {
        self.backend = backend
    }

    public var availability: SourceAvailability { .available }

    /// True between a successful `start` and `stop`.
    public var isStarted: Bool { running }

    public func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        // Start on a started source ends the current session first (Constitution VII; QA-007-R2).
        if running { await stop() }
        let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        do {
            try backend.start(track: track, sink: sink) { continuation.yield($0) }
        } catch {
            continuation.finish()
            throw SourceError(.inAppPlaybackFailed)
        }
        self.continuation = continuation
        running = true
        sessionCount += 1
        return stream
    }

    public func stop() async {
        guard running else { return }
        running = false
        backend.stop()
        continuation?.finish()
        continuation = nil
    }

    public func suspend() async {
        guard running else { return }
        backend.pause()
    }

    public func resume() async throws {
        guard running else { return }
        do {
            try backend.resume()
        } catch {
            throw SourceError(.inAppPlaybackFailed)
        }
    }

    // MARK: - Transport (AUD-006). Used by PlaybackTransport; no effect unless started.

    /// Whether the current track repeats by itself (one track in the play order) or ends.
    public var loopsCurrentTrack: Bool {
        get { backend.loopsCurrentTrack }
        set { backend.loopsCurrentTrack = newValue }
    }

    /// Called when a track that does not loop has reached its end while playing.
    public var onTrackEnded: (@MainActor () -> Void)? {
        get { backend.onTrackEnded }
        set { backend.onTrackEnded = newValue }
    }

    /// AUD-003: the play order changed whether the current track repeats; takes effect at once,
    /// keeping the position and without a cut (`InAppPlaybackBackend.updateLooping`).
    public func updateLooping(_ loops: Bool) {
        if running { backend.updateLooping(loops) } else { backend.loopsCurrentTrack = loops }
    }

    /// AUD-004: whether the end of a track that played to its end has reached the sink.
    public var hasDeliveredTrackEnd: Bool {
        running ? backend.hasDeliveredTrackEnd : true
    }

    public var playbackPosition: PlaybackPosition {
        running ? backend.position : .zero
    }

    public func seek(to seconds: Double) {
        guard running else { return }
        backend.seek(to: seconds)
    }

    /// Changes the playing track; `track` follows, so a Restart plays the new one.
    public func replaceTrack(_ newTrack: InAppPlaybackTrack) throws {
        guard running else { throw SourceError(.inAppPlaybackFailed) }
        try backend.replaceTrack(newTrack)
        track = newTrack
    }

    /// Ends the session as "In-App Playback failed" through the manager's event stream.
    public func reportFailure() {
        guard running else { return }
        continuation?.yield(.failed(.inAppPlaybackFailed))
    }
}
