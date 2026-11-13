// OSC-001-T17: the OSC receiver in the app with a fake transport (OSC-001-R1 to R3, R16;
// contracts/osc-receiver.md C6). No networking.
import PerformanceControl
import Synchronization
import XCTest
@testable import projectM_iOS

/// What the fake transports were asked to do, in order.
private final class TransportLog: Sendable {
    private let entries = Mutex<[String]>([])
    func append(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
}

/// Starts and stops synchronously; `ready` and `cancelled` are reported at once.
private final class ImmediateTransport: OSCDatagramTransport, Sendable {
    private let log: TransportLog
    private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)

    init(log: TransportLog) { self.log = log }

    func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
        log.append("start \(port)")
        self.events.withLock { $0 = events }
        events(.ready(port: port))
    }

    func stop() {
        log.append("stop")
        let events = self.events.withLock { $0 }
        events?(.cancelled)
    }

    func send(_ event: OSCTransportEvent) { events.withLock { $0 }?(event) }
}

private final class LatestTransport: Sendable {
    private let transport = Mutex<ImmediateTransport?>(nil)
    func set(_ t: ImmediateTransport) { transport.withLock { $0 = t } }
    func get() -> ImmediateTransport? { transport.withLock { $0 } }
}

@MainActor
final class OSCReceiverCoordinatorTests: XCTestCase {
    private func makeSettings() throws -> (AppSettings, () -> Void) {
        let suite = "OSCReceiverCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (AppSettings(defaults: defaults, systemReduceMotion: false), { defaults.removePersistentDomain(forName: suite) })
    }

    func testOffByDefaultOpensNothing() throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        let log = TransportLog()
        let osc = OSCReceiverCoordinator(settings: settings, receiver: OSCReceiver(makeTransport: { ImmediateTransport(log: log) }))
        XCTAssertFalse(osc.isEnabled)
        XCTAssertEqual(osc.state, .off)
        XCTAssertEqual(osc.statusText, "Off")
        XCTAssertTrue(log.all.isEmpty, "a fresh install opens no listener (OSC-001-R1)")
    }

    func testListensOnlyWhileEnabledAndActive() throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        let log = TransportLog()
        let osc = OSCReceiverCoordinator(settings: settings, receiver: OSCReceiver(makeTransport: { ImmediateTransport(log: log) }))
        osc.setEnabled(true)
        XCTAssertTrue(settings.oscEnabled)
        XCTAssertEqual(osc.state, .listening(port: 9000))
        XCTAssertEqual(osc.statusText, "Listening on port 9000")

        osc.sceneBecame(active: false)
        XCTAssertEqual(osc.state, .off, "no listener outside the foreground (OSC-001-R3)")
        osc.sceneBecame(active: true)
        XCTAssertEqual(osc.state, .listening(port: 9000))

        osc.setEnabled(false)
        XCTAssertEqual(osc.state, .off)
        XCTAssertEqual(osc.statusText, "Off")
        XCTAssertEqual(log.all, ["start 9000", "stop", "start 9000", "stop"])
    }

    func testPortChangeRestartsAndInvalidPortIsRefused() throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        let log = TransportLog()
        let osc = OSCReceiverCoordinator(settings: settings, receiver: OSCReceiver(makeTransport: { ImmediateTransport(log: log) }))
        osc.setEnabled(true)
        XCTAssertTrue(osc.submitPort("8000"))
        XCTAssertEqual(settings.oscPort, 8000)
        XCTAssertEqual(osc.state, .listening(port: 8000))
        for bad in ["80", "70000", "", "abc"] {
            XCTAssertFalse(osc.submitPort(bad), bad)
            XCTAssertEqual(osc.portError, OSCReceiverCoordinator.portRangeMessage)
        }
        XCTAssertEqual(settings.oscPort, 8000, "the stored port stays")
        XCTAssertTrue(osc.submitPort("8000"))
        XCTAssertNil(osc.portError)
        XCTAssertEqual(log.all, ["start 9000", "stop", "start 8000"], "an unchanged port does not restart")
    }

    func testTestValueReachesTheMainActor() async throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        let latest = LatestTransport()
        let log = TransportLog()
        let receiver = OSCReceiver(makeTransport: {
            let t = ImmediateTransport(log: log)
            latest.set(t)
            return t
        })
        let osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
        osc.setEnabled(true)
        let packet = OSCEncoder.encode(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(0.25)]))
        latest.get()?.send(.datagram(packet))
        for _ in 0..<100 where osc.testValue != 0.25 { await Task.yield() }
        XCTAssertEqual(osc.testValue, 0.25)
        XCTAssertEqual(OSCReceiverCoordinator.testValueText(0.25), "0.25")
    }

    /// OSC-009-T08 (OSC-009-R11, S4 one-pending part): a flood of 10,000 datagrams delivered on the
    /// main actor (so no refresh can run in between) leaves at most one refresh pending; once drained,
    /// a handful of refreshes (not 10,000) showed the final value. The 30-per-second rate is proven
    /// with a fake clock in PerformanceControl's OSCRefreshGateTests.
    func testFloodCoalescesMainActorRefreshes() async throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        let latest = LatestTransport()
        let log = TransportLog()
        let wide = OSCRateLimitConfiguration(perSource: OSCRateLimit(perSecond: 1_000_000, burst: 1_000),
                                             global: OSCRateLimit(perSecond: 1_000_000, burst: 1_000))
        let receiver = OSCReceiver(limits: wide, makeTransport: {
            let t = ImmediateTransport(log: log)
            latest.set(t)
            return t
        })
        let osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
        osc.setEnabled(true)
        let transport = try XCTUnwrap(latest.get())
        // Let the state-change refreshes queued by setEnabled run first: they are not traffic.
        try await Task.sleep(nanoseconds: 100_000_000)
        let before = osc.refreshCount
        let count = 10_000
        for i in 1...count {
            let value = Float(i) / Float(count)
            transport.send(.datagram(OSCEncoder.encode(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(value)]))))
        }
        XCTAssertEqual(osc.refreshCount, before, "nothing ran on the main actor during the flood")
        for _ in 0..<200 where osc.testValue != 1 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(osc.testValue, 1, "the last value sent is shown")
        XCTAssertGreaterThan(receiver.counters.coalesced, 0, "the target limit held values")
        XCTAssertEqual(osc.rateLimitedCount, receiver.counters.rateLimited + receiver.counters.coalesced)
        XCTAssertLessThanOrEqual(osc.refreshCount - before, 3,
                                 "one refresh for the flood, one for the deferred flush, at most one more; not one per message")
    }

    func testRateLimitedText() {
        XCTAssertEqual(OSCReceiverCoordinator.rateLimitedText(0), "0")
        XCTAssertEqual(OSCReceiverCoordinator.rateLimitedText(12345), "12345", "never grouped")
    }

    func testStatusTexts() {
        typealias C = OSCReceiverCoordinator
        XCTAssertEqual(C.statusText(for: .starting(port: 9000), enabled: true), "Starting…")
        XCTAssertEqual(C.statusText(for: .failed(port: 9000, .portInUse), enabled: true), "Port 9000 is in use. Choose another port.")
        XCTAssertEqual(C.statusText(for: .failed(port: 9000, .localNetworkDenied), enabled: true),
                       "Local network access is off for projectM in Settings › Privacy & Security › Local Network.")
        XCTAssertEqual(C.statusText(for: .failed(port: 9000, .unavailable), enabled: true), "OSC isn't available on this device.")
        XCTAssertEqual(C.statusText(for: .failed(port: 9000, .other("posix 1")), enabled: true),
                       "OSC couldn't listen on port 9000. Turn it off and on to try again.")
        XCTAssertEqual(C.statusText(for: .off, enabled: false), "Off")
    }
}
