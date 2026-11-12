// Tasks T036, T042, T043: adapter mapping logic with fake platform seams (no device, no SDK).
import XCTest
import Foundation
import AudioCore
@testable import CaptureKit

// MARK: - Fakes

@MainActor
final class FakeStreamDriver: StreamDriver {
    var isSupported = true
    var isAllowed = true
    var contentIdentity: String?
    var startError: (any Error)?
    /// When true, `start` waits like a system picker that has not answered, until `stop()` ends
    /// it with `.cancelled`, as SCKStreamDriver does (ADR-0001 ruling 7).
    var holdsStart = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onEvent: (@Sendable (SourceEvent) -> Void)?
    private var picker: CheckedContinuation<Void, any Error>?

    var isWaitingOnPicker: Bool { picker != nil }

    func start(sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) async throws {
        startCount += 1
        if let startError { throw startError }
        if holdsStart {
            try await withCheckedThrowingContinuation { picker = $0 }
        }
        self.onEvent = onEvent
    }

    func stop() async {
        stopCount += 1
        onEvent = nil
        if let picker {
            self.picker = nil
            picker.resume(throwing: SourceError(.cancelled, detail: "Stopped from the app while the system picker was open"))
        }
    }

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

    /// Every track a start was asked to play, including failed starts.
    private(set) var requestedTracks: [InAppPlaybackTrack] = []
    /// Tracks that actually started.
    private(set) var startedTracks: [InAppPlaybackTrack] = []

    // Transport (AUD-006): a scripted position and a record of every call.
    var loopsCurrentTrack = true
    var onTrackEnded: (@MainActor () -> Void)?
    var positionSeconds = 0.0
    var durationSeconds = 60.0
    /// Tracks whose `replaceTrack` fails, like a stored copy that is gone.
    var unplayable: Set<InAppPlaybackTrack> = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var seekTargets: [Double] = []
    private(set) var replaceRequests: [InAppPlaybackTrack] = []
    private(set) var replacedTracks: [InAppPlaybackTrack] = []
    /// `loopsCurrentTrack` at each start and each successful replace.
    private(set) var loopFlags: [Bool] = []
    /// Calls that reached the backend after `stop()`.
    private(set) var callsAfterStop = 0

    var position: PlaybackPosition { PlaybackPosition(seconds: positionSeconds, durationSeconds: durationSeconds) }

    func start(track: InAppPlaybackTrack, sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {
        requestedTracks.append(track)
        if trackMissing { throw SourceError(.inAppPlaybackFailed) }
        started = true
        paused = false
        positionSeconds = 0
        startedTracks.append(track)
        loopFlags.append(loopsCurrentTrack)
        self.onEvent = onEvent
    }

    func stop() { started = false; stopCount += 1 }

    func pause() {
        guard started else { callsAfterStop += 1; return }
        paused = true
        pauseCount += 1
    }

    /// AUD-014: `resume()` throws this, like iOS refusing to give the audio back during a call.
    var resumeError: SourceError?
    private(set) var refusedResumeCount = 0

    func resume() throws {
        guard started else { callsAfterStop += 1; return }
        if let resumeError { refusedResumeCount += 1; throw resumeError }
        paused = false
        resumeCount += 1
    }

    func seek(to seconds: Double) {
        guard started else { callsAfterStop += 1; return }
        seekTargets.append(seconds)
        positionSeconds = PlaybackPosition(seconds: seconds, durationSeconds: durationSeconds).seconds
    }

    func replaceTrack(_ track: InAppPlaybackTrack) throws {
        guard started else { callsAfterStop += 1; throw SourceError(.inAppPlaybackFailed) }
        replaceRequests.append(track)
        if unplayable.contains(track) { throw SourceError(.inAppPlaybackFailed) }
        replacedTracks.append(track)
        loopFlags.append(loopsCurrentTrack)
        positionSeconds = 0
    }
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

    /// FR-004 (owner ruling 2026-11-08): an iOS 27 device where screen recording is not allowed
    /// shows "Screen recording not allowed", not the iOS 26 reason, and does not start.
    func testNotAllowedIsUnavailableWithItsOwnReason() async {
        let driver = FakeStreamDriver()
        driver.isAllowed = false
        let source = ScreenCaptureSource(driver: driver)
        XCTAssertEqual(source.availability, .unavailable(.screenRecordingNotAllowed))
        do {
            _ = try await source.start(into: PCMSink())
            XCTFail("must not start")
        } catch let e as SourceError {
            XCTAssertEqual(e.reason, .screenRecordingNotAllowed)
            XCTAssertEqual(e.detail, "SCContentSharingPicker.isAvailable is false at start")
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(driver.startCount, 0, "the picker must not be shown when not allowed")
        driver.isAllowed = true
        XCTAssertEqual(source.availability, .available, "availability is re-read each time")
    }

    /// US1-AS4: declining screen recording (-3801, mapped by the driver) reads "Screen recording not
    /// allowed" in the manager.
    func testDeclinedRecordingShowsNotAllowed() async {
        let driver = FakeStreamDriver()
        driver.startError = SourceError(.screenRecordingNotAllowed)
        let manager = CaptureManager(sources: [ScreenCaptureSource(driver: driver)], runsAnalysisTimer: false)
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.stopReason, .screenRecordingNotAllowed)
        XCTAssertEqual(manager.state, .notStarted)
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

    /// ADR-0001 ruling 7: a start waiting on a picker that never answers ends when the source is
    /// stopped, as cancelled, instead of waiting forever.
    func testStopEndsAStartWaitingOnThePicker() async {
        let driver = FakeStreamDriver()
        driver.holdsStart = true
        let source = ScreenCaptureSource(driver: driver)
        let start = Task { @MainActor in try await source.start(into: PCMSink()) }
        await waitUntil { driver.isWaitingOnPicker }
        await source.stop()
        do {
            _ = try await start.value
            XCTFail("the waiting start must end with an error")
        } catch let e as SourceError {
            XCTAssertEqual(e.reason, .cancelled)
        } catch { XCTFail("\(error)") }
        XCTAssertFalse(driver.isWaitingOnPicker)
    }

    /// Stop in CaptureLab while the picker has not answered: the manager does not wait behind the
    /// start, and the attempt ends as "Not started — cancelled" (ADR-0001 ruling 7).
    func testManagerStopCancelsAStartWaitingOnThePicker() async {
        let driver = FakeStreamDriver()
        driver.holdsStart = true
        let manager = CaptureManager(sources: [ScreenCaptureSource(driver: driver)], runsAnalysisTimer: false)
        let select = Task { @MainActor in await manager.select(.systemAppCapture) }
        await waitUntil { driver.isWaitingOnPicker }
        XCTAssertTrue(manager.isStarting)
        let begin = Date()
        await manager.stop()
        await select.value
        XCTAssertLessThan(Date().timeIntervalSince(begin), 1.0, "FR-007: stop within 1 s")
        XCTAssertFalse(manager.isStarting)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .cancelled)
        XCTAssertEqual(manager.stopDetail, "Start cancelled from the app before the source started")
    }
}

/// Polls `condition` on the main actor for up to 2 s.
@MainActor
func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
        try? await Task.sleep(nanoseconds: 10_000_000)
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

    // MARK: Imported tracks (AUD-001-T11)

    func testTrackDefaultsToReference() async throws {
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        XCTAssertEqual(source.track, .reference)
        _ = try await source.start(into: PCMSink())
        XCTAssertEqual(backend.startedTracks, [.reference])
        XCTAssertEqual(source.mode, .inAppPlayback)
    }

    func testSelectedFileTrackReachesBackendAndKeepsTheMode() async throws {
        let url = URL(fileURLWithPath: "/library/assets/abc.wav")
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        source.track = .file(url)
        _ = try await source.start(into: PCMSink())
        XCTAssertEqual(backend.startedTracks, [.file(url)])
        XCTAssertEqual(source.mode, .inAppPlayback, "AUD-001-R18: an imported track is In-App Playback")
        XCTAssertEqual(source.availability, .available)
    }

    func testUnplayableFileTrackFailsWithoutFallback() async {
        let url = URL(fileURLWithPath: "/library/assets/missing.wav")
        let backend = FakePlaybackBackend()
        backend.trackMissing = true
        let source = InAppPlaybackSource(backend: backend)
        source.track = .file(url)
        await assertThrows(.inAppPlaybackFailed) { _ = try await source.start(into: PCMSink()) }
        XCTAssertEqual(backend.requestedTracks, [.file(url)], "AUD-001-R19: no second start with another track")
        XCTAssertEqual(backend.startedTracks, [])
    }

    func testManagerLabelsImportedTrackAsInAppPlaybackAndRestartsIt() async {
        let url = URL(fileURLWithPath: "/library/assets/abc.wav")
        let backend = FakePlaybackBackend()
        let source = InAppPlaybackSource(backend: backend)
        let manager = CaptureManager(sources: [source], runsAnalysisTimer: false)
        source.track = .file(url)
        await manager.select(.inAppPlayback)
        XCTAssertEqual(manager.activeMode, .inAppPlayback)
        await manager.restart()
        XCTAssertEqual(backend.startedTracks, [.file(url), .file(url)])
        // Back to the reference track at the next selection.
        await manager.stop()
        source.track = .reference
        await manager.select(.inAppPlayback)
        XCTAssertEqual(backend.startedTracks.last, .reference)
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
