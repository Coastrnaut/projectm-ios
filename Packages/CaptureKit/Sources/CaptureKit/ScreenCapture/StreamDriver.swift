// StreamDriver.swift — the seam between ScreenCaptureSource and ScreenCaptureKit (task T038).
// ScreenCaptureKit types live only in this folder (Constitution VI; enforced by
// scripts/check_compliance.py). Tests substitute a fake driver.
import AudioCore

@MainActor
public protocol StreamDriver: AnyObject {
    /// Whether this OS offers the system content-sharing flow (FR-004, FR-008).
    var isSupported: Bool { get }
    /// Whether the OS currently allows screen recording on this device (runtime probe). Read each
    /// time availability is asked, because a restriction can change while the app runs.
    var isAllowed: Bool { get }
    /// Identity of the selected content if the OS provides one (FR-014); nil otherwise.
    var contentIdentity: String? { get }
    /// Presents the system picker (from a user action only, FR-002), then starts an audio-only
    /// stream that writes into `sink`. Throws `SourceError(.cancelled)` if the user cancels the
    /// picker and `SourceError(.screenRecordingNotAllowed)` if screen recording is declined or not
    /// allowed.
    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) async throws
    /// Stops the stream within 1 s. Idempotent.
    func stop() async
}
