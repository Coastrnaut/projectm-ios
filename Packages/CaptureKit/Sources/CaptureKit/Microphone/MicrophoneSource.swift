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

    /// Attempts of `resume()` before it fails, and the wait between them (FR-051).
    public static let resumeAttempts = 4
    public static let resumeRetryDelay: Duration = .milliseconds(250)
    private let retryDelay: Duration

    public init(backend: any MicrophoneBackend, resumeRetryDelay: Duration = MicrophoneSource.resumeRetryDelay) {
        self.backend = backend
        self.retryDelay = resumeRetryDelay
    }

    public var availability: SourceAvailability { .available }

    /// True when the app must show the FR-005 explainer before starting.
    public var needsExplainer: Bool { backend.permission == .undetermined && !explainerAcknowledged }

    /// Call after the user has read the explainer (contracts/ui-states.md) and chosen to continue.
    public func acknowledgeExplainer() { explainerAcknowledged = true }

    public func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        // Start on a started source ends the current session first (Constitution VII; QA-007-R2):
        // otherwise the backend would run a second engine into the sink and the first event
        // stream would never finish.
        if running { await stop() }
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
    ///
    /// Right after an interruption ends (a Clock alarm stopped, a call hung up) iOS can refuse the session's
    /// activation for a moment, so a failed restart is tried again, `resumeAttempts` times in all, `resumeRetryDelay`
    /// apart (under a second, inside FR-050's 2 s). QA-011 full 8 and pass 9 (D2, iPadOS 27.2, 2026-11-19): after a
    /// real Clock timer with `shouldResume`, the one restart failed and the microphone stayed "Stopped, Microphone
    /// unavailable" although the input was there. A lost permission or a missing input fails at once.
    public func resume() async throws {
        guard running else { return }
        var attempt = 0
        while true {
            guard backend.permission == .granted else { throw SourceError(.permissionDenied) }
            guard backend.isInputAvailable else { throw SourceError(.microphoneUnavailable) }
            do {
                try backend.resume()
                return
            } catch {
                attempt += 1
                guard attempt < Self.resumeAttempts, running else {
                    throw (error as? SourceError) ?? SourceError(.microphoneUnavailable)
                }
            }
            try? await Task.sleep(for: retryDelay)
            guard running else { return }   // stopped while waiting: nothing to resume
        }
    }
}
