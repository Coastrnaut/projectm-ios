// OSC-005-T09, T10, T11: Send OSC in the app (specs/277-osc-005-osc-send, contract S3) over real UDP on loopback.
// The receiver switch runs over the DEBUG stand-in transport (no listener socket); the fixture that receives the sent
// datagrams is the package's own listener (`NetworkDatagramTransport`) on a free port of 127.0.0.1, because test
// files may not use the Network framework. Beats come from a fake grid and clock through `tick(now:)`.
import PerformanceControl
import Synchronization
import XCTest
@testable import projectM_iOS

@MainActor
final class OSCSendCoordinatorTests: XCTestCase {
    /// Collects every datagram the loopback fixture receives.
    private final class Fixture: Sendable {
        let transport = NetworkDatagramTransport()
        let received = Mutex<[[UInt8]]>([])
        let port = Mutex<UInt16?>(nil)
        var count: Int { received.withLock { $0.count } }
    }

    private final class Harness {
        let defaults: UserDefaults
        let settings: AppSettings
        let osc: OSCReceiverCoordinator
        let send: OSCSendCoordinator
        let gridBox: GridBox

        @MainActor init(defaults: UserDefaults, transport: any OSCSendTransport) {
            self.defaults = defaults
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            let routable = OSCRoutesCoordinator.routable()
            let receiver = UITestFakeOSC.makeReceiver(store: OSCRoutesCoordinator.makeStore(routable: routable),
                                                      routes: OSCRoutesCoordinator.initialRoutes(routable: routable, defaults: defaults))
            osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
            let box = GridBox()
            send = OSCSendCoordinator(osc: osc, defaults: defaults, transport: transport, beatGrid: { () -> (anchor: UInt64, period: UInt64)? in box.grid },
                                      clock: { () -> UInt64 in 0 }, pollsBeats: false)
            gridBox = box
            osc.sender = send
        }
    }

    /// Opens nothing: for tests that need no traffic.
    private final class NoTransport: OSCSendTransport, Sendable {
        let sends = Mutex(0)
        func open(host: OSCPeerAddress, port: UInt16, events: @escaping @Sendable (OSCSendTransportEvent) -> Void) {}
        func send(_ bytes: [UInt8]) { sends.withLock { $0 += 1 } }
        func close() {}
    }

    @MainActor private final class GridBox {
        var grid: (anchor: UInt64, period: UInt64)?
    }

    private func makeHarness(_ transport: any OSCSendTransport = NetworkOSCSender()) throws -> Harness {
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: "OSCSendCoordinatorTests-\(UUID().uuidString)"))
        return Harness(defaults: defaults, transport: transport)
    }

    private func openFixture() throws -> (Fixture, UInt16) {
        let fixture = Fixture()
        let ready = expectation(description: "fixture ready")
        ready.assertForOverFulfill = false
        fixture.transport.start(port: 0) { (event: OSCTransportEvent) -> Void in
            switch event {
            case .ready(let port):
                fixture.port.withLock { $0 = port }
                ready.fulfill()
            case .failed:
                ready.fulfill()
            case .datagram(let bytes, _, _):
                fixture.received.withLock { $0.append(bytes) }
            default:
                break
            }
        }
        wait(for: [ready], timeout: 5)
        guard let port = fixture.port.withLock({ $0 }) else { throw XCTSkip("the loopback fixture could not open here") }
        return (fixture, port)
    }

    private func waitFor(_ fixture: Fixture, count: Int) async {
        for _ in 0..<250 where fixture.count < count { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertGreaterThanOrEqual(fixture.count, count)
    }

    /// Nothing more arrives over a short window (the only real-time wait: a negative check on real UDP).
    private func assertQuiet(_ fixture: Fixture, stays count: Int, _ why: String) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fixture.count, count, why)
    }

    /// S1, S2: byte-exact scene and beat at the loopback fixture; Send OSC off, the receiver switch off and the
    /// background each stop traffic.
    func testLoopbackReceivesSceneAndBeatAndEveryDisableStopsTraffic() async throws {
        let h = try makeHarness()
        let (fixture, port) = try openFixture()
        defer { fixture.transport.stop() }
        XCTAssertFalse(h.send.isEnabled, "R2: off by default")
        XCTAssertNil(h.send.destination)

        h.osc.setEnabled(true)
        XCTAssertTrue(h.send.submitDestination(host: "127.0.0.1", port: String(port)))
        h.send.setKind(.beat, on: true)
        h.send.setIncludeSceneNames(true)
        h.send.setEnabled(true)
        XCTAssertEqual(h.send.activeDestination?.port, port)

        h.send.post(.scene(name: "Intro"))
        await waitFor(fixture, count: 1)
        h.gridBox.grid = (anchor: 1_000_000_000, period: 500_000_000)
        h.send.tick(now: 1_100_000_000)   // records the current beat
        h.send.tick(now: 1_510_000_000)   // the next beat
        await waitFor(fixture, count: 2)
        let received = fixture.received.withLock { $0 }
        XCTAssertEqual(received[0], OSCEncoder.encode(OSCMessage(address: "/projectm/scene", arguments: [.string("Intro")])))
        XCTAssertEqual(received[1], OSCEncoder.encode(OSCMessage(address: "/projectm/beat", arguments: [.int(1)])))
        XCTAssertEqual(h.send.sentCount, 2)
        XCTAssertEqual(h.send.countsText, "2 sent, 0 dropped")

        // Send OSC off.
        h.send.setEnabled(false)
        h.send.post(.status(.started))
        h.send.tick(now: 2_010_000_000)
        await assertQuiet(fixture, stays: 2, "Send OSC off stops traffic")

        // The OSC receiver switch (OSC-007) off.
        h.send.setEnabled(true)
        h.send.post(.status(.started))
        await waitFor(fixture, count: 3)
        h.osc.stopFromBadge()
        XCTAssertNil(h.send.activeDestination)
        h.send.post(.status(.stopped))
        await assertQuiet(fixture, stays: 3, "the network switch off stops traffic")

        // The background.
        h.osc.setEnabled(true)
        h.osc.sceneBecame(active: false)
        h.send.post(.status(.stopped))
        await assertQuiet(fixture, stays: 3, "the background stops traffic")
        XCTAssertEqual(h.send.statusText, "Paused while projectM is in the background.")
    }

    /// R3, R4, R10: refused destinations, the allow list and every status text.
    func testDestinationRulesAllowListAndStatusTexts() throws {
        let none = NoTransport()
        let h = try makeHarness(none)
        XCTAssertEqual(h.send.statusText, "Off")
        XCTAssertEqual(h.send.summaryText, "Off")
        h.send.setEnabled(true)
        XCTAssertEqual(h.send.statusText, "Turn on the OSC receiver to send.")
        h.osc.setEnabled(true)
        XCTAssertEqual(h.send.statusText, "Enter a destination address.")
        XCTAssertFalse(h.send.submitDestination(host: "8.8.8.8", port: "9001"))
        XCTAssertEqual(h.send.destinationError, OSCSendDestinationError.notLocal.message)
        XCTAssertFalse(h.send.submitDestination(host: "mixer.local", port: "9001"))
        XCTAssertNil(h.send.destination, "a refused entry stores nothing")
        XCTAssertNil(h.defaults.string(forKey: OSCSendCoordinator.hostKey))
        XCTAssertTrue(h.send.submitDestination(host: "192.168.1.40", port: "9001"))
        XCTAssertNil(h.send.destinationError)
        XCTAssertEqual(h.defaults.string(forKey: OSCSendCoordinator.hostKey), "192.168.1.40")
        XCTAssertEqual(h.defaults.integer(forKey: OSCSendCoordinator.portKey), 9001)
        XCTAssertEqual(h.send.statusText, "Sending to 192.168.1.40:9001")

        // OSC-008: with the allow list on, only an approved destination is sent to.
        h.osc.peerAllowlist.setEnabled(true)
        h.send.post(.status(.started))
        XCTAssertNil(h.send.activeDestination)
        XCTAssertEqual(h.send.statusText, "The destination is not an approved device.")
        XCTAssertEqual(h.send.sentCount, 0)
        XCTAssertEqual(none.sends.withLock { $0 }, 0)
        h.osc.peerAllowlist.setApproved([.ipv4(192, 168, 1, 40)])
        h.send.conditionsChanged()
        XCTAssertNotNil(h.send.activeDestination)
        h.osc.peerAllowlist.setEnabled(false)

        // Stored values come back; the kinds default to scene and status.
        let again = OSCSendCoordinator(osc: h.osc, defaults: h.defaults, transport: NoTransport(),
                                       beatGrid: { () -> (anchor: UInt64, period: UInt64)? in nil }, pollsBeats: false)
        XCTAssertTrue(again.isEnabled)
        XCTAssertEqual(again.destination?.text, "192.168.1.40:9001")
        XCTAssertEqual(again.kinds, [.scene, .status])
        XCTAssertFalse(again.includeSceneNames)
        h.send.setEnabled(false)
        again.setEnabled(false)
    }
}
