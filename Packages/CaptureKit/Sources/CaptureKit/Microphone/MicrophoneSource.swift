// MicrophoneSource.swift — Microphone fallback (task T045; FR-005, FR-019, FR-051, FR-053, FR-069).
//
// Ambient room sound through the device microphone. Never labeled as System/App Capture
// (FR-013). The FR-005 explainer must be shown (and acknowledged) before the system permission
// prompt; `start` enforces that.
import AudioCore

public enum MicrophonePermission: Sendable, Equatable {
    case undetermined
    case granted
    case denied
}

/// Platform seam for the microphone (AVAudioEngine in production, a fake in tests).
@MainActor
public protocol MicrophoneBackend: AnyObject {
    var permission: MicrophonePermission { get }
    func requestPermission() async -> Bool
    var isInputAvailable: Bool { get }
    /// Starts capture into `sink`. Throws `SourceError`.
    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws
    func stop()
    /// Stops the engine for backgrounding; keeps configuration for `resume`.
    func pause()
    func resume() throws
}

@MainActor
public final class MicrophoneSource: AudioSource {
    public let mode: AudioSourceMode = .microphone
    private let backend: any MicrophoneBackend
    private var continuation: AsyncStream<SourceEvent>.Continuation?
    private var explainerAcknowledged = false
    private var running = false

    public init(backend: any MicrophoneBackend) {
        self.backend = backend
    }

    public var availability: SourceAvailability { .available }

    /// True when the app must show the FR-005 explainer before starting.
    public var needsExplainer: Bool { backend.permission == .undetermined && !explainerAcknowledged }

    /// Call after the user has read the explainer (contracts/ui-states.md) and chosen to continue.
    public func acknowledgeExplainer() { explainerAcknowledged = true }

    public func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        switch backend.permission {
        case .denied:
            throw SourceError(.permissionDenied)
        case .undetermined:
            guard explainerAcknowledged else {
                // Programming error guard: FR-005 requires the explainer before the prompt.
                throw SourceError(.error("Microphone explainer not shown before the permission prompt"))
            }
            guard await backend.requestPermission() else { throw SourceError(.permissionDenied) }
        case .granted:
            break
        }
        guard backend.isInputAvailable else { throw SourceError(.microphoneUnavailable) }
        let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        do {
            try backend.start(sink: sink) { continuation.yield($0) }
        } catch {
            continuation.finish()
            throw (error as? SourceError) ?? SourceError(.microphoneUnavailable)
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

    /// Re-checks permission and input on return (FR-053), then restarts the engine.
    public func resume() async throws {
        guard running else { return }
        guard backend.permission == .granted else { throw SourceError(.permissionDenied) }
        guard backend.isInputAvailable else { throw SourceError(.microphoneUnavailable) }
        do {
            try backend.resume()
        } catch {
            throw (error as? SourceError) ?? SourceError(.microphoneUnavailable)
        }
    }
}
