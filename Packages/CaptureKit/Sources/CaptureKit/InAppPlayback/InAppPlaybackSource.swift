// InAppPlaybackSource.swift — deterministic In-App Playback fallback (task T046; FR-006, FR-051, FR-069).
//
// Plays the bundled reference track (scripts/generate_reference_audio.py) audibly through the
// current output, looping until stopped, and taps the app's own mix. Never opens an input.
import AudioCore

/// Platform seam (AVAudioEngine + AVAudioPlayerNode in production, a fake in tests).
@MainActor
public protocol InAppPlaybackBackend: AnyObject {
    /// Loads the track and starts looping playback, tapping the mix into `sink`. Throws `SourceError`.
    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws
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

    public init(backend: any InAppPlaybackBackend) {
        self.backend = backend
    }

    public var availability: SourceAvailability { .available }

    public func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        do {
            try backend.start(sink: sink) { continuation.yield($0) }
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
