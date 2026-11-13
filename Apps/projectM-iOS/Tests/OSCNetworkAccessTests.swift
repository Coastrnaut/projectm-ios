// OSC-007-T02, T06, T08, T09: the OSC network access switch (specs/038-osc-007-osc-network-access-switch).
// * The listener badge rule over every receiver state (OSC-007-R2, R3, S3).
// * Stop from the badge (R4, R5).
// * A fresh install opens no listener at launch or across a background-foreground cycle (R1, S1).
// * The app's toggle moves the real system listener ready ↔ cancelled and releases the port (R8, S2),
//   over the simulator's loopback; skipped (never passed) when the sandbox refuses the port.
// No networking API is used here (FR-068): the real transport is OSC-001's `OSCReceiver.system()`.
// Owner rule 7: each test about a second or less; ceilings are generous, never asserted as timings.
import PerformanceControl
import Synchronization
import XCTest
@testable import projectM_iOS

/// Counts transports created and what they were asked to do. `ready`/`cancelled` are immediate.
private final class CountingTransportFactory: Sendable {
    private let log = Mutex<[String]>([])
    var entries: [String] { log.withLock { $0 } }
    var created: Int { entries.filter { $0 == "make" }.count }

    func make() -> any OSCDatagramTransport {
        log.withLock { $0.append("make") }
        return Transport(factory: self)
    }

    fileprivate func append(_ entry: String) { log.withLock { $0.append(entry) } }

    private final class Transport: OSCDatagramTransport, Sendable {
        private let factory: CountingTransportFactory
        private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)
        init(factory: CountingTransportFactory) { self.factory = factory }

        func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
            factory.append("start \(port)")
            self.events.withLock { $0 = events }
            events(.ready(port: port))
        }

        func stop() {
            factory.append("stop")
            let handler: (@Sendable (OSCTransportEvent) -> Void)? = events.withLock { $0 }
            handler?(.cancelled)
        }
    }
}

@MainActor
final class OSCNetworkAccessTests: XCTestCase {
    private func makeSettings() throws -> (AppSettings, UserDefaults, () -> Void) {
        let suite = "OSCNetworkAccessTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (AppSettings(defaults: defaults, systemReduceMotion: false), defaults,
                { defaults.removePersistentDomain(forName: suite) })
    }

    private func makeCoordinator(_ settings: AppSettings, _ factory: CountingTransportFactory) -> OSCReceiverCoordinator {
        OSCReceiverCoordinator(settings: settings, receiver: OSCReceiver(makeTransport: { factory.make() }))
    }

    // MARK: OSC-007-T02: badge rule (S3)

    func testBadgeIsShownOnlyWhileListening() {
        typealias C = OSCReceiverCoordinator
        XCTAssertEqual(C.listenerBadgePort(for: .listening(port: 9000)), 9000)
        XCTAssertEqual(C.listenerBadgePort(for: .listening(port: 47124)), 47124)
        let hidden: [OSCReceiverState] = [
            .off, .starting(port: 9000), .stopping,
            .failed(port: 9000, .portInUse), .failed(port: 9000, .localNetworkDenied),
            .failed(port: 9000, .unavailable), .failed(port: 9000, .other("posix 1")),
        ]
        for state in hidden { XCTAssertNil(C.listenerBadgePort(for: state), "\(state)") }
        XCTAssertEqual(C.badgeText(port: 9000), "OSC listening on port 9000")
        XCTAssertEqual(C.badgeAccessibilityValue(port: 47124), "Port 47124")
    }

    func testBadgeFollowsTheListenerNotTheToggle() throws {
        let (settings, _, cleanup) = try makeSettings()
        defer { cleanup() }
        let factory = CountingTransportFactory()
        let osc = makeCoordinator(settings, factory)
        XCTAssertNil(osc.badgePort)
        osc.setEnabled(true)
        XCTAssertEqual(osc.badgePort, 9000)
        osc.sceneBecame(active: false)
        XCTAssertTrue(osc.isEnabled)
        XCTAssertNil(osc.badgePort, "no badge while paused in the background (R3)")
        osc.sceneBecame(active: true)
        XCTAssertEqual(osc.badgePort, 9000)
        osc.setEnabled(false)
        XCTAssertNil(osc.badgePort)
    }

    // MARK: OSC-007-T06: Stop (R4, R5)

    func testStopFromBadgeTurnsTheSettingOffAndClosesTheListener() throws {
        let (settings, defaults, cleanup) = try makeSettings()
        defer { cleanup() }
        let factory = CountingTransportFactory()
        let osc = makeCoordinator(settings, factory)
        osc.setEnabled(true)
        XCTAssertTrue(osc.submitPort("8000"))
        let valueBefore = osc.testValue

        osc.stopFromBadge()
        XCTAssertFalse(settings.oscEnabled)
        XCTAssertFalse(defaults.bool(forKey: AppSettings.oscEnabledKey), "stored off, as the Settings toggle does")
        XCTAssertEqual(osc.state, .off)
        XCTAssertNil(osc.badgePort)
        XCTAssertEqual(settings.oscPort, 8000, "the port is unchanged")
        XCTAssertEqual(osc.testValue, valueBefore, "the test value is unchanged")
        XCTAssertEqual(factory.entries, ["make", "start 9000", "stop", "make", "start 8000", "stop"])

        osc.stopFromBadge()                       // a second tap does nothing
        osc.sceneBecame(active: false)
        osc.sceneBecame(active: true)             // and nothing reopens it
        XCTAssertEqual(factory.entries.count, 6)
        XCTAssertEqual(osc.state, .off)
    }

    // MARK: OSC-007-T08: fresh install (R1, S1)

    func testFreshInstallOpensNoListenerAcrossAForegroundCycle() throws {
        let (settings, defaults, cleanup) = try makeSettings()
        defer { cleanup() }
        XCTAssertNil(defaults.object(forKey: AppSettings.oscEnabledKey), "no stored OSC setting")
        let factory = CountingTransportFactory()
        let osc = makeCoordinator(settings, factory)
        osc.sceneBecame(active: false)
        osc.sceneBecame(active: true)
        osc.sceneBecame(active: true)
        XCTAssertEqual(factory.created, 0, "no transport was ever created")
        XCTAssertEqual(osc.state, .off)
        XCTAssertNil(osc.badgePort)
    }

    // MARK: OSC-007-T09: the toggle against the real system listener (R8, S2)

    /// Polls the main-actor state (copied from the receiver's queue) until `condition` holds.
    private func waitFor(_ osc: OSCReceiverCoordinator, ceiling: Duration = .seconds(5),
                         _ condition: (OSCReceiverState) -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: ceiling)
        while !condition(osc.state) {
            if clock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    private static func listeningOrFailed(_ state: OSCReceiverState) -> Bool {
        if case .failed = state { return true }
        return state.isListening
    }

    func testToggleMovesTheRealListenerBetweenReadyAndCancelled() async throws {
        let (settings, _, cleanup) = try makeSettings()
        defer { cleanup() }
        let port = UInt16.random(in: 49152...65000)
        settings.oscPort = Int(port)
        let osc = OSCReceiverCoordinator(settings: settings, receiver: .system())
        XCTAssertEqual(osc.state, .off)

        osc.setEnabled(true)
        let settled = try await waitFor(osc, Self.listeningOrFailed)
        XCTAssertTrue(settled, "state: \(osc.state)")
        if case .failed(_, let failure) = osc.state {
            osc.setEnabled(false)
            throw XCTSkip("the system listener could not open port \(port) here (\(failure)); not verified")
        }
        XCTAssertEqual(osc.state, .listening(port: port), "the system reported the socket ready")
        XCTAssertEqual(osc.badgePort, port)

        osc.setEnabled(false)
        XCTAssertNil(osc.badgePort, "the badge goes at once (stopping)")
        let off = try await waitFor(osc) { $0 == .off }
        XCTAssertTrue(off, "off is reported only after the system cancelled the listener; state: \(osc.state)")

        // The socket was released: an independent listener binds the same port.
        let (otherSettings, _, otherCleanup) = try makeSettings()
        defer { otherCleanup() }
        otherSettings.oscPort = Int(port)
        let second = OSCReceiverCoordinator(settings: otherSettings, receiver: .system())
        second.setEnabled(true)
        let rebound = try await waitFor(second, Self.listeningOrFailed)
        XCTAssertTrue(rebound)
        XCTAssertEqual(second.state, .listening(port: port), "the same port binds again after off")
        second.setEnabled(false)
        _ = try await waitFor(second) { $0 == .off }
    }
}
