// ScreenCaptureSource.swift — System/App Capture (task T037; ADR-0001; FR-002, FR-004, FR-008,
// FR-009, FR-014, FR-051, FR-069).
//
// ScreenCaptureKit only, in-process: no ReplayKit, no broadcast extension. On OS versions
// without the system capture flow (presumed iOS 26), the mode is unavailable with
// "Requires a newer iOS version" and fallbacks remain (FR-004).
import AudioCore

@MainActor
public final class ScreenCaptureSource: AudioSource, ContentIdentifying {
    public let mode: AudioSourceMode = .systemAppCapture
    private let driver: (any StreamDriver)?
    private var continuation: AsyncStream<SourceEvent>.Continuation?

    /// - Parameter driver: nil means this OS has no supported capture flow.
    public init(driver: (any StreamDriver)?) {
        self.driver = driver
    }

    /// The production source: the ScreenCaptureKit driver where available, else unavailable.
    ///
    /// TODO(T035, RI-004): replace `27.0` with the first iOS version that provides the required
    /// ScreenCaptureKit audio APIs, as recorded in docs/platform-research/screencapturekit-ios.md.
    public static func makeDefault() -> ScreenCaptureSource {
        #if os(iOS) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            return ScreenCaptureSource(driver: SCKStreamDriver())
        }
        #endif
        return ScreenCaptureSource(driver: nil)
    }

    public var availability: SourceAvailability {
        guard let driver, driver.isSupported else { return .unavailable(.unsupportedOS) }
        return .available
    }

    public var contentIdentity: String? { driver?.contentIdentity }

    public func start(into sink: PCMSink) async throws -> AsyncStream<SourceEvent> {
        guard let driver, driver.isSupported else { throw SourceError(.unsupportedOS) }
        let (stream, continuation) = AsyncStream.makeStream(of: SourceEvent.self)
        do {
            try await driver.start(sink: sink) { continuation.yield($0) }
        } catch let error as SourceError {
            continuation.finish()
            throw error
        } catch {
            continuation.finish()
            throw SourceError(.error(String(describing: error)))
        }
        self.continuation = continuation
        return stream
    }

    public func stop() async {
        await driver?.stop()
        continuation?.finish()
        continuation = nil
    }

    /// FR-050: System/App Capture keeps running in the background if the OS lets the stream
    /// deliver; if the OS stops it, the driver reports endedBySystem. Nothing to do here.
    public func suspend() async {}

    /// Nothing to resume: a stopped stream must be restarted through the system picker (FR-055).
    public func resume() async throws {}
}
