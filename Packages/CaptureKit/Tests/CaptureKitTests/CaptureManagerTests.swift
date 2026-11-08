// Task T021: FR-001, FR-007, FR-016, FR-052, FR-055, plus lifecycle (FR-050/FR-051/FR-054) and
// FR-014 identity gating, using FakeAudioSource and an injected clock.
import XCTest
import Foundation
import AudioCore
@testable import CaptureKit

final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double = 0
    var now: Double { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ s: Double) { lock.lock(); value += s; lock.unlock() }
}

/// Test fixture: three fake sources and a manager with manual analysis and clock.
@MainActor
final class Fixture {
    let clock = ManualClock()
    let capture = FakeAudioSource(mode: .systemAppCapture)
    let mic = FakeAudioSource(mode: .microphone)
    let inApp = FakeAudioSource(mode: .inAppPlayback)
    let manager: CaptureManager

    init() {
        let clock = self.clock
        manager = CaptureManager(sources: [capture, mic, inApp], runsAnalysisTimer: false, clock: { clock.now })
    }

    var runningCount: Int { [capture, mic, inApp].filter { $0.isRunning }.count }
}

@MainActor
final class CaptureManagerTests: XCTestCase {
    // Lazy: XCTestCase.init is nonisolated; first access happens in a @MainActor test method.
    // XCTest creates a new instance per test, so every test gets a fresh fixture.
    private lazy var fixture = Fixture()
    private var clock: ManualClock { fixture.clock }
    private var capture: FakeAudioSource { fixture.capture }
    private var mic: FakeAudioSource { fixture.mic }
    private var inApp: FakeAudioSource { fixture.inApp }
    private var manager: CaptureManager { fixture.manager }

    private func playLoud(_ source: FakeAudioSource, seconds: Double = 0.5) {
        var t = 0.0
        while t < seconds {
            source.pushAudio(amplitude: 0.5, seconds: 0.01)
            clock.advance(0.01)
            manager.stepAnalysisForTesting()
            t += 0.01
        }
    }

    func testSelectStartsAndShowsWaiting() async {
        await manager.select(.microphone)
        XCTAssertEqual(manager.activeMode, .microphone)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(mic.startCount, 1)
    }

    func testOnlyOneActiveSourceAndSwitchStopsOldFirst() async {
        await manager.select(.microphone)
        await manager.select(.inAppPlayback)
        XCTAssertFalse(mic.isRunning)
        XCTAssertTrue(inApp.isRunning)
        XCTAssertEqual(mic.stopCount, 1)
        XCTAssertEqual(manager.state, .waiting, "new source shows Waiting until classified (FR-016)")
        XCTAssertEqual(manager.activeMode, .inAppPlayback)
    }

    func testActiveOnlyAfterVerifiedAudio() async {
        await manager.select(.inAppPlayback)
        playLoud(inApp)
        XCTAssertEqual(manager.state, .active)
        XCTAssertTrue(manager.hasVerifiedActiveAudio)
    }

    func testStopIsIdempotentAndFast() async {
        await manager.select(.microphone)
        let start = Date()
        await manager.stop()
        await manager.stop()
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(mic.stopCount, 1, "second stop is a no-op")
    }

    func testFiftyRapidCyclesEndInLastActionWithoutDuplicates() async {
        let modes: [AudioSourceMode] = [.microphone, .inAppPlayback, .systemAppCapture]
        for i in 0..<50 {
            if i % 3 == 2 { await manager.stop() } else { await manager.select(modes[i % modes.count]) }
        }
        await manager.select(.inAppPlayback)
        XCTAssertEqual(manager.activeMode, .inAppPlayback)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(fixture.runningCount, 1)
        XCTAssertTrue(inApp.isRunning)
    }

    func testConcurrentCommandsAreSerialized() async {
        let m = manager   // capture the main-actor manager, not the non-Sendable test case
        async let a: Void = m.select(.microphone)
        async let b: Void = m.select(.inAppPlayback)
        async let c: Void = m.stop()
        _ = await (a, b, c)
        XCTAssertLessThanOrEqual(fixture.runningCount, 1)
    }

    func testStartFailureShowsReason() async {
        mic.startError = SourceError(.permissionDenied)
        await manager.select(.microphone)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .permissionDenied)
    }

    func testUnavailableModeReportsUnsupportedOS() async {
        capture.availability = .unavailable(.unsupportedOS)
        await manager.select(.systemAppCapture)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .unsupportedOS)
        XCTAssertEqual(capture.startCount, 0, "never starts an unavailable source")
    }

    func testRestartAfterEndedBySystem() async {
        await manager.select(.systemAppCapture)
        capture.emit(.endedBySystem("stopped sharing"))
        await settle()
        XCTAssertEqual(manager.state, .endedBySystem)
        await manager.restart()
        XCTAssertEqual(capture.startCount, 2, "restart re-runs start, which re-presents the picker")
        XCTAssertEqual(manager.state, .waiting)
    }

    func testInterruptionIgnoredForSystemCaptureButNotForMicrophone() async {
        await manager.select(.systemAppCapture)
        capture.emit(.interruptionBegan)
        await settle()
        XCTAssertEqual(manager.state, .waiting, "FR-051: no change while the stream delivers")

        await manager.select(.microphone)
        mic.emit(.interruptionBegan)
        await settle()
        XCTAssertEqual(manager.state, .interrupted)
        mic.emit(.interruptionEnded(shouldResume: true))
        await settle()
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(mic.resumeCount, 1)
    }

    func testInterruptionWithoutResumeNeedsOneTapRestart() async {
        await manager.select(.microphone)
        mic.emit(.interruptionBegan)
        mic.emit(.interruptionEnded(shouldResume: false))
        await settle()
        XCTAssertEqual(manager.state, .interrupted)
        await manager.resume()
        XCTAssertEqual(manager.state, .waiting)
    }

    func testBackgroundPausesMicAndForegroundResumes() async {
        await manager.select(.microphone)
        await manager.handle(.background)
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(mic.suspendCount, 1)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(mic.resumeCount, 1)
    }

    func testLockIsHandledLikeBackground() async {
        await manager.select(.inAppPlayback)
        await manager.handle(.lock)
        XCTAssertEqual(manager.state, .paused)
        await manager.handle(.unlock)
        XCTAssertEqual(manager.state, .waiting)
    }

    func testBackgroundDoesNotTouchSystemCapture() async {
        await manager.select(.systemAppCapture)
        await manager.handle(.background)
        XCTAssertEqual(manager.state, .waiting)
        XCTAssertEqual(capture.suspendCount, 0)
    }

    func testPermissionRevokedWhileBackgrounded() async {
        await manager.select(.microphone)
        await manager.handle(.background)
        mic.resumeError = SourceError(.permissionDenied)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.stopReason, .permissionDenied)
    }

    func testOutputRouteLostPausesUntilResume() async {
        await manager.select(.inAppPlayback)
        inApp.emit(.outputRouteLost)
        await settle()
        XCTAssertEqual(manager.state, .paused)
        XCTAssertEqual(manager.stopReason, .audioRouteChanged)
        await manager.handle(.foreground)
        XCTAssertEqual(manager.state, .paused, "route-change pause needs the user's Resume")
        await manager.resume()
        XCTAssertEqual(manager.state, .waiting)
    }

    func testMicrophoneLostStopsWithReason() async {
        await manager.select(.microphone)
        mic.emit(.failed(.microphoneUnavailable))
        await settle()
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.stopReason, .microphoneUnavailable)
        XCTAssertFalse(mic.isRunning)
    }

    func testContentIdentityOnlyAfterVerifiedActiveAudio() async {
        capture.contentIdentity = "Some App"
        await manager.select(.systemAppCapture)
        XCTAssertNil(manager.displayedContentIdentity)
        playLoud(capture)
        XCTAssertEqual(manager.state, .active)
        XCTAssertEqual(manager.displayedContentIdentity, "Some App")
    }

    /// Lets queued event-handling tasks run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { await Task.yield() }
    }
}
