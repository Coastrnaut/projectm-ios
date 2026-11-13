// SessionRecoveryTests.swift — PERF-010-T02, T07: the session marker's state machine (clean exit,
// kill, crash loop, harness suppression) and the launch policy (no OSC listener and no camera after
// an abnormal exit, the offer, Start fresh defaults, Reopen). In-memory UserDefaults suites and a fake
// OSC transport; no networking, no files. Budget: about 1 s for the class (owner rule 7).
import PerformanceControl
import Synchronization
import VisualEffects
import XCTest
@testable import projectM_iOS

/// Counts starts; reports `ready` at once (as OSCReceiverCoordinatorTests' transport).
private final class CountingTransport: OSCDatagramTransport, Sendable {
    private let starts = Mutex(0)
    private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)
    var startCount: Int { starts.withLock { $0 } }

    func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
        starts.withLock { $0 += 1 }
        self.events.withLock { $0 = events }
        events(.ready(port: port))
    }

    func stop() {
        let events = self.events.withLock { $0 }
        events?(.cancelled)
    }
}

final class SessionRecoveryPolicyTests: XCTestCase {
    private typealias Policy = SessionRecoveryPolicy

    func testCleanExitThenLaunchIsClean() {
        var record = Policy.launch(SessionRecord(), suppressed: false).record
        XCTAssertTrue(record.open, "launch opens the session")
        record = Policy.ended(record)
        let launch = Policy.launch(record, suppressed: false)
        XCTAssertEqual(launch.decision, .clean)
        XCTAssertFalse(launch.offersRecovery)
    }

    func testKillWithoutBackgroundIsAbnormal() {
        let first = Policy.launch(SessionRecord(), suppressed: false).record
        let launch = Policy.launch(first, suppressed: false)   // never ended: killed
        XCTAssertEqual(launch.decision, .abnormal(crashLoop: false))
        XCTAssertTrue(launch.offersRecovery)
    }

    func testBackgroundThenForegroundThenKillIsAbnormal() {
        var record = Policy.launch(SessionRecord(), suppressed: false).record
        record = Policy.ended(record)
        XCTAssertFalse(record.open)
        record = Policy.resumed(record)
        XCTAssertEqual(Policy.launch(record, suppressed: false).decision, .abnormal(crashLoop: false))
    }

    func testCrashInTheReopenedSessionOrTheNextIsACrashLoop() {
        let reopened = Policy.reopened(Policy.launch(SessionRecord(open: true), suppressed: false).record)
        XCTAssertEqual(reopened.sessionsSinceReopen, 0)
        XCTAssertEqual(Policy.launch(reopened, suppressed: false).decision, .abnormal(crashLoop: true), "same session")

        let next = Policy.launch(Policy.ended(reopened), suppressed: false)   // clean: session 1
        XCTAssertEqual(next.decision, .clean)
        XCTAssertEqual(next.record.sessionsSinceReopen, 1)
        let loop = Policy.launch(next.record, suppressed: false)              // killed in session 1
        XCTAssertEqual(loop.decision, .abnormal(crashLoop: true))
        XCTAssertNil(loop.record.sessionsSinceReopen)
        XCTAssertNil(loop.record.heldVisual, "nothing to reopen in a crash loop")
    }

    func testTwoCleanSessionsAfterReopenClearTheGuard() {
        var record = Policy.reopened(SessionRecord(open: true))
        record = Policy.launch(Policy.ended(record), suppressed: false).record   // session 1
        record = Policy.launch(Policy.ended(record), suppressed: false).record   // session 2: dropped
        XCTAssertNil(record.sessionsSinceReopen)
        XCTAssertEqual(Policy.launch(record, suppressed: false).decision, .abnormal(crashLoop: false))
    }

    func testUnansweredOfferIsOfferedAgainAfterACleanExit() {
        let record = SessionRecord(open: false, sessionsSinceReopen: nil, heldVisual: "circularSpectrum")
        let launch = Policy.launch(record, suppressed: false)
        XCTAssertEqual(launch.decision, .clean)
        XCTAssertTrue(launch.offersRecovery)
        XCTAssertNil(Policy.startedFresh(launch.record).heldVisual)
    }

    func testHarnessLaunchesAreSuppressedUnlessATestAsks() {
        XCTAssertFalse(Policy.isSuppressed(arguments: ["app", "-uitestDiagnostics"], environment: [:], harness: false), "Release decides")
        XCTAssertTrue(Policy.isSuppressed(arguments: ["app", "-uitestUnlocked", "NO"], environment: [:], harness: true))
        XCTAssertTrue(Policy.isSuppressed(arguments: ["app", "-autostart", "inAppPlayback"], environment: [:], harness: true))
        XCTAssertTrue(Policy.isSuppressed(arguments: ["app"], environment: ["PROJECTM_AUTORUN": "sc101"], harness: true))
        XCTAssertTrue(Policy.isSuppressed(arguments: ["app"], environment: ["XCTestConfigurationFilePath": "x"], harness: true))
        XCTAssertFalse(Policy.isSuppressed(arguments: ["app", "-uitestDiagnostics", Policy.testArgument], environment: [:], harness: true))
        XCTAssertFalse(Policy.isSuppressed(arguments: ["app"], environment: [:], harness: true), "a plain launch decides")

        let killed = SessionRecord(open: true)
        let launch = Policy.launch(killed, suppressed: true)
        XCTAssertEqual(launch.decision, .suppressed)
        XCTAssertFalse(launch.offersRecovery)
        XCTAssertTrue(launch.record.open, "the marker is still kept")
    }
}

@MainActor
final class SessionRecoveryLaunchTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, () -> Void) {
        let suite = "SessionRecoveryLaunchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    /// The app's launch order (contract C1): decide and prepare, then create the OSC receiver.
    private func launch(_ defaults: UserDefaults, transport: CountingTransport)
        -> (SessionRecoveryCoordinator, AppSettings, OSCReceiverCoordinator, Bool) {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let recovery = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)
        let holds = recovery.prepare(settings: settings)
        let osc = OSCReceiverCoordinator(settings: settings, receiver: OSCReceiver(makeTransport: { transport }))
        return (recovery, settings, osc, holds)
    }

    private func editedSession(_ defaults: UserDefaults) {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.oscEnabled = true
        settings.visual = .circularSpectrum
        settings.circularSpectrumBars = 16
        settings.glowEnabled = true
        settings.visual = .camera   // session only: the stored visual stays Circular Spectrum
    }

    func testAbnormalExitNeverReopensTheOSCListenerAndTurnsTheToggleOff() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        _ = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)   // session 1 opens
        editedSession(defaults)                                                 // ... and is killed
        let transport = CountingTransport()
        let (recovery, settings, osc, holds) = launch(defaults, transport: transport)
        XCTAssertEqual(recovery.decision, .abnormal(crashLoop: false))
        XCTAssertEqual(transport.startCount, 0, "no listener without consent (PERF-010-R2)")
        XCTAssertEqual(osc.state, .off)
        XCTAssertFalse(osc.isListenerOpen)
        XCTAssertFalse(settings.oscEnabled)
        XCTAssertFalse(defaults.bool(forKey: AppSettings.oscEnabledKey), "the stored toggle is off")
        XCTAssertTrue(recovery.oscTurnedOff)
        XCTAssertTrue(holds)
        XCTAssertEqual(recovery.offer, .pending)
        XCTAssertFalse(settings.visual.usesCamera, "the camera is never chosen by a launch (PERF-010-R3)")

        // A later normal launch still opens nothing until the user turns OSC on.
        recovery.sessionEnded()
        let again = CountingTransport()
        let (_, _, oscAgain, _) = launch(defaults, transport: again)
        XCTAssertEqual(again.startCount, 0)
        oscAgain.setEnabled(true)
        XCTAssertEqual(again.startCount, 1, "the user's toggle opens it")
    }

    func testNormalExitKeepsOSCAsStored() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let first = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)
        editedSession(defaults)
        first.sessionEnded()   // background
        let transport = CountingTransport()
        let (recovery, settings, _, holds) = launch(defaults, transport: transport)
        XCTAssertEqual(recovery.decision, .clean)
        XCTAssertEqual(recovery.offer, .none)
        XCTAssertFalse(holds, "SCN-002 restores silently after a normal exit")
        XCTAssertEqual(transport.startCount, 1, "OSC-001-R15 unchanged after a normal exit")
        XCTAssertEqual(settings.visual, .circularSpectrum)
    }

    func testPendingOfferShowsTheFreshSceneAndHoldsTheVisual() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        _ = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)
        editedSession(defaults)
        let (recovery, settings, _, _) = launch(defaults, transport: CountingTransport())
        XCTAssertEqual(settings.visual, .projectM)
        XCTAssertEqual(settings.circularSpectrumBars, AppSettings.defaultCircularSpectrumBars)
        XCTAssertFalse(settings.glowEnabled)
        XCTAssertEqual(settings.glowIntensity, Double(BloomParameters.defaultIntensity))
        XCTAssertEqual(recovery.heldVisual, .circularSpectrum)
        XCTAssertEqual(defaults.string(forKey: SessionRecoveryCoordinator.heldVisualKey), "circularSpectrum")

        XCTAssertFalse(recovery.offersReopen, "no committed scene held yet")
        recovery.hold(nil)
        XCTAssertFalse(recovery.offersReopen, "nothing to reopen without a committed scene")
        XCTAssertEqual(recovery.message, "Starting with a fresh scene.")
    }

    func testKilledAgainBeforeAnsweringOffersTheSameVisual() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        _ = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)
        editedSession(defaults)
        _ = launch(defaults, transport: CountingTransport())          // pending, killed again
        let (recovery, settings, _, _) = launch(defaults, transport: CountingTransport())
        XCTAssertEqual(recovery.offer, .pending)
        XCTAssertEqual(recovery.heldVisual, .circularSpectrum, "PERF-010-R8")
        XCTAssertEqual(settings.visual, .projectM)
    }

    func testStartFreshKeepsDefaultsAndEndsTheOffer() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        _ = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)
        editedSession(defaults)
        let (recovery, settings, _, _) = launch(defaults, transport: CountingTransport())
        recovery.markStartedFresh()
        XCTAssertEqual(recovery.offer, .fresh)
        XCTAssertNil(defaults.string(forKey: SessionRecoveryCoordinator.heldVisualKey))
        XCTAssertEqual(settings.visual, .projectM)
        XCTAssertEqual(settings.circularSpectrumBars, AppSettings.defaultCircularSpectrumBars)
        XCTAssertFalse(settings.oscEnabled, "Start fresh does not turn OSC on")

        recovery.sessionEnded()
        let (next, _, _, holds) = launch(defaults, transport: CountingTransport())
        XCTAssertEqual(next.offer, .none, "answered: no offer after a normal exit")
        XCTAssertFalse(holds)
    }

    func testCrashLoopOffersStartFreshOnly() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        SessionRecoveryCoordinator.write(SessionRecord(open: true, sessionsSinceReopen: 0, heldVisual: nil), to: defaults)
        let (recovery, settings, _, holds) = launch(defaults, transport: CountingTransport())
        XCTAssertEqual(recovery.decision, .abnormal(crashLoop: true))
        XCTAssertTrue(holds, "the scene is not restored silently")
        XCTAssertNil(recovery.heldVisual)
        recovery.hold(nil)
        XCTAssertFalse(recovery.offersReopen)
        XCTAssertEqual(recovery.title, "projectM closed unexpectedly again.")
        XCTAssertEqual(settings.visual, .projectM)
        XCTAssertNil(recovery.markReopened(), "Reopen is refused")
    }

    func testSuppressedLaunchChangesNothing() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        _ = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)
        editedSession(defaults)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let recovery = SessionRecoveryCoordinator(defaults: defaults, suppressed: true)
        XCTAssertFalse(recovery.prepare(settings: settings))
        XCTAssertEqual(recovery.decision, .suppressed)
        XCTAssertTrue(settings.oscEnabled)
        XCTAssertEqual(settings.visual, .circularSpectrum)
        XCTAssertEqual(recovery.probe(oscListening: false), "decision=suppressed offer=none reopen=0 osc=off")
    }

    func testResetForgetsTheSession() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        _ = SessionRecoveryCoordinator(defaults: defaults, suppressed: false)
        SessionRecoveryCoordinator.reset(defaults)
        XCTAssertEqual(SessionRecoveryCoordinator(defaults: defaults, suppressed: false).decision, .clean)
    }
}
