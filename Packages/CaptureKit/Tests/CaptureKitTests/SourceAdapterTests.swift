// Tasks T036, T042, T043: adapter mapping logic with fake platform seams (no device, no SDK).
import XCTest
import Foundation
import AudioCore
@testable import CaptureKit

// MARK: - Fakes

@MainActor
final class FakeStreamDriver: StreamDriver {
    var isSupported = true
    var contentIdentity: String?
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onEvent: (@Sendable (SourceEvent) -> Void)?

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) async throws {
        startCount += 1
        if let startError { throw startError }
        self.onEvent = onEvent
    }

    func stop() async { stopCount += 1; onEvent = nil }

    /// Simulates SCStreamDelegate.stream(_:didStopWithError:).
    func simulateSystemStop() { onEvent?(.endedBySystem("user stopped sharing")) }
}

@MainActor
final class FakeMicrophoneBackend: MicrophoneBackend {
    var permission: MicrophonePermission = .undetermined
    var grantOnRequest = true
    var isInputAvailable = true
    var startError: SourceError?
    private(set) var requestCount = 0
    private(set) var started = false
    private(set) var paused = false
    private(set) var resumed = 0

    func requestPermission() async -> Bool {
        requestCount += 1
        permission = grantOnRequest ? .granted : .denied
        return grantOnRequest
    }

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        if let startError { throw startError }
        started = true
    }

    func stop() { started = false }
    func pause() { paused = true }
    func resume() throws { resumed += 1; paused = false }
}

@MainActor
final class FakePlaybackBackend: InAppPlaybackBackend {
    var trackMissing = false
    private(set) var started = false
    private(set) var paused = false
    private(set) var openedInput = false
    private(set) var stopCount = 0
    var onEvent: (@Sendable (SourceEvent) -> Void)?

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        if trackMissing { throw SourceError(.inAppPlaybackFailed) }
        started = true
        self.onEvent = onEvent
    }

    func stop() { started = false; stopCount += 1 }
    func pause() { paused = true }
    func resume() throws { paused = false }
}

// MARK: - System/App Capture (T036)

@MainActor
final class ScreenCaptureSourceTests: XCTestCase {
    func testUnsupportedOSIsUnavailable() async {
        let source = ScreenCaptureSource(driver: nil)
        XCTAssertEqual(source.availability, .unavailable(.unsupportedOS))     // FR-004
        do {
            _ = try await source.start(into: PCMSink())
            XCTFail("must not start")
        } catch let e as SourceError {
            XCTAssertEqual(e.reason, .unsupportedOS)
        } catch { XCTFail("\(error)") }
    }

    func testPickerCancelIsCancelled() async {
        let driver = FakeStreamDriver()
        driver.startError = SourceError(.cancelled)
        let source = ScreenCaptureSource(driver: driver)
        do {
            _ = try await source.start(into: PCMSink())
            XCTFail("must throw")
        } catch let e as SourceError {
            XCTAssertEqual(e.reason, .cancelled)
        } catch { XCTFail("\(error)") }
    }

    func testOtherErrorsMapToError() async {
        struct Boom: Error {}
        let driver = FakeStreamDriver()
        driver.startError = Boom()
        let source = ScreenCaptureSource(driver: driver)
        do {
            _ = try await source.start(into: PCMSink())
            XCTFail("must throw")
        } catch let e as SourceError {
            if case .error = e.reason {} else { XCTFail("expected .error, got \(e.reason)") }
        } catch { XCTFail("\(error)") }
    }

    func testSystemStopBecomesEndedBySystemInManager() async {
        let driver = FakeStreamDriver()
        let manager = CaptureManager(sources: [ScreenCaptureSource(driver: driver)], runsAnalysisTimer: false)
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.state, .waiting)
        driver.simulateSystemStop()
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(manager.state, .endedBySystem)
        XCTAssertEqual(driver.stopCount, 1)
    }

    func testIdentityHiddenUntilVerified() async {
        let driver = FakeStreamDriver()
        driver.contentIdentity = "Some App"
        let manager = CaptureManager(sources: [ScreenCaptureSource(driver: driver)], runsAnalysisTimer: false)
        await manager.select(.systemAppCapture)
        XCTAssertNil(manager.displayedContentIdentity)   // FR-014
    }

    func testStopIsIdempotent() async {
        let driver = FakeStreamDriver()
        let source = ScreenCaptureSource(driver: driver)
        _ = try? await source.start(into: PCMSink())
        await source.stop()
        await source.stop()
        XCTAssertEqual(driver.stopCount, 2, "driver.stop itself must tolerate repeats")
    }
}

// MARK: - Microphone (T042)

@MainActor
final class MicrophoneSourceTests: XCTestCase {
    func testExplainerRequiredBeforePermissionPrompt() async {
        let backend = FakeMicrophoneBackend()
        let source = MicrophoneSource(backend: backend)
        XCTAssertTrue(source.needsExplainer)
        _ = try? await source.start(into: PCMSink())
        XCTAssertEqual(backend.requestCount, 0, "FR-005: no prompt before the explainer")
        source.acknowledgeExplainer()
        _ = try? await source.start(into: PCMSink())
        XCTAssertEqual(backend.requestCount, 1)
        XCTAssertTrue(backend.started)
    }

    func testDeniedPermission() async {
        let backend = FakeMicrophoneBackend()
        backend.permission = .denied
        let source = MicrophoneSource(backend: backend)
        await assertThrows(.permissionDenied) { _ = try await source.start(into: PCMSink()) }
    }

    func testDeniedAtPrompt() async {
        let backend = FakeMicrophoneBackend()
        backend.grantOnRequest = false
        let source = MicrophoneSource(backend: backend)
        source.acknowledgeExplainer()
        await assertThrows(.permissionDenied) { _ = try await source.start(into: PCMSink()) }
    }

    func testNoInputIsMicrophoneUnavailable() async {
        let backend = FakeMicrophoneBackend()
        backend.permission = .granted
        backend.isInputAvailable = false
        let source = MicrophoneSource(backend: backend)
        await assertThrows(.microphoneUnavailable) { _ = try await source.start(into: PCMSink()) }
    }

    func testPermissionRevokedWhileBackgroundedIsDetectedOnResume() async throws {
        let backend = FakeMicrophoneBackend()
        backend.permission = .granted
        let source = MicrophoneSource(backend: backend)
        _ = try await source.start(into: PCMSink())
        await source.suspend()
        XCTAssertTrue(backend.paused)
        backend.permission = .denied                     // FR-053
        await assertThrows(.permissionDenied) { try await source.resume() }
    }

    func testBackgroundForegroundViaManagerResumesWithinTwoSeconds() async {
        let backend = FakeMicrophoneBackend()
        backend.permission = .granted
        let manager = CaptureManager(sources: [MicrophoneSource(backend: backend)], runsAnalysisTimer: false)
        await manager.select(.microphone)
        await manager.handle(.background)
        XCTAssertEqual(manager.state, .paused)
        let t0 = Date()
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
        XCTAssertEqual(backend.resumed, 1)
    }
}

// MARK: - In-App Playback (T043)

@MainActor
final class InAppPlaybackSourceTests: XCTestCase {
    func testMissingTrackFails() async {
        let backend = FakePlaybackBackend()
        backend.trackMissing = true
        let source = InAppPlaybackSource(backend: backend)
        await assertThrows(.inAppPlaybackFailed) { _ = try await source.start(into: PCMSink()) }
    }

    func testRouteLossPausesWithReason() async {
        let backend = FakePlaybackBackend()
        let manager = CaptureManager(sources: [InAppPlaybackSource(backend: backend)], runsAnalysisTimer: false)
        await manager.select(.inAppPlayback)
        backend.onEvent?(.outputRouteLost)
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(manager.stopReason, .audioRouteChanged)
    }

    func testStopWithinOneSecondAndIdempotent() async throws {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        _ = try await source.start(into: PCMSink())
        let t0 = Date()
        await source.stop()
        await source.stop()
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1)
        XCTAssertEqual(backend.stopCount, 1)
        XCTAssertFalse(backend.openedInput, "FR-069: never opens an input")
    }
}

// MARK: - Helpers

@MainActor
func assertThrows(_ expected: StopReason, file: StaticString = #filePath, line: UInt = #line,
                  _ body: () async throws -> Void) async {
    do {
        try await body()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch let e as SourceError {
        XCTAssertEqual(e.reason, expected, file: file, line: line)
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}
