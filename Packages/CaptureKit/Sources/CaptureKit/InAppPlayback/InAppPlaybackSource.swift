// InAppPlaybackSource.swift — deterministic In-App Playback fallback (task T046; FR-006, FR-051, FR-069).
//
// Plays the bundled reference track (scripts/generate_reference_audio.py), or a track from the
// user's imported library (AUD-001), audibly through the current output, looping until stopped,
// and taps the app's own mix. Never opens an input. Every track is In-App Playback: the mode and
// its label do not change with the track (Constitution IV, AUD-001-R18).
import AudioCore
import Foundation

/// What In-App Playback plays.
public enum InAppPlaybackTrack: Sendable, Equatable {
    /// The bundled reference track (FR-006).
    case reference
    /// A file in the app's own audio library (`AudioLibrary.fileURL(for:)`). Never a picked or
    /// security-scoped URL, and never persisted (AUD-001-R3).
    case file(URL)
}

/// Platform seam (AVAudioEngine + AVAudioPlayerNode in production, a fake in tests).
@MainActor
public protocol InAppPlaybackBackend: AnyObject {
    /// Loads `track` and starts looping playback, tapping the mix into `sink`. Throws `SourceError`
    /// when the track cannot be played; it never plays a different track instead (AUD-001-R19).
    func start(track: InAppPlaybackTrack, sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws
    func stop()
    func pause()
    func resume() throws
}

@MainActor
public final class InAppPlaybackSource: AudioSource {
    public let mode: AudioSourceMode = .inAppPlayback
    private let backend: any InAppPlaybackBackend
    private var continuation: AsyncStream<SourceEvent>.Continuation?
    private var running = false
    /// The track the next `start` plays. Changing it while running takes effect at the next start
    /// (a restart through CaptureManager starts the same track again).
    public var track: InAppPlaybackTrack = .reference

    public init(backend: any InAppPlaybackBackend) {
        self.backend = backend
    }

    public var availability: SourceAvailability { .available }

    public func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        do {
            try backend.start(track: track, sink: sink) { continuation.yield($0) }
        } catch {
            continuation.finish()
            throw SourceError(.inAppPlaybackFailed)
        }
        self.continuation = continuation
        running = true
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
}
