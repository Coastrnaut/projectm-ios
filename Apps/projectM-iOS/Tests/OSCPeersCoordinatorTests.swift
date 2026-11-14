// OSC-008-T10: Approved Devices in the app (OSC-008-R1, R5, R8, R10, R11; contract A4) with a fake transport. No networking.
import PerformanceControl
import Synchronization
import XCTest
@testable import projectM_iOS

/// Reports `ready` and `cancelled` at once and lets the test deliver datagrams.
private final class PeerTestTransport: OSCDatagramTransport, Sendable {
    private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)

    func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
        self.events.withLock { $0 = events }
        events(.ready(port: port))
    }

    func stop() { events.withLock { $0 }?(.cancelled) }

    func send(_ event: OSCTransportEvent) { events.withLock { $0 }?(event) }
}

@MainActor
final class OSCPeersCoordinatorTests: XCTestCase {
    private static let host = OSCPeerAddress.ipv4(192, 168, 1, 20)

    private func makeDefaults() throws -> (UserDefaults, () -> Void) {
        let suite = "OSCPeersCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    /// Waits (bounded, no timing assertion) for the gated main-actor refresh.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testOffByDefaultAndInvalidStoredEntriesAreDroppedOnLoad() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        defaults.set(["192.168.1.20", "8.8.8.8", "not an address", "fe80:0:0:0:0:0:0:1", "192.168.1.20"],
                     forKey: OSCPeersCoordinator.approvedKey)
        let allowlist = OSCPeerAllowlist()
        let peers = OSCPeersCoordinator(allowlist: allowlist, defaults: defaults)
        XCTAssertFalse(peers.isEnabled, "absent → off (OSC-008-R1)")
        XCTAssertEqual(peers.summaryText, "Off")
        XCTAssertEqual(peers.approved.map(\.text), ["192.168.1.20", "fe80::1"])
        XCTAssertEqual(defaults.stringArray(forKey: OSCPeersCoordinator.approvedKey), ["192.168.1.20", "fe80:0:0:0:0:0:0:1"],
                       "what could not be read is removed from the store")
        XCTAssertEqual(allowlist.approved.count, 2)
    }

    func testABlockedHostIsAllowedRemovedAndForgottenWhenOSCIsTurnedOff() async throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let transport = PeerTestTransport()
        let receiver = OSCReceiver(makeTransport: { transport })
        let osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
        let peers = OSCPeersCoordinator(allowlist: osc.peerAllowlist, defaults: defaults)
        osc.peers = peers
        peers.setEnabled(true)
        XCTAssertEqual(defaults.object(forKey: OSCPeersCoordinator.enabledKey) as? Bool, true)
        osc.setEnabled(true)

        let packet = OSCEncoder.encode(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(0.25)]))
        transport.send(.datagram(packet, peer: Self.host))
        await settle { peers.blockedCount == 1 }
        XCTAssertEqual(peers.blockedCount, 1)
        XCTAssertEqual(peers.recentlyBlocked, [Self.host])
        XCTAssertEqual(receiver.testValue, 0, "the unapproved host changed nothing")

        XCTAssertEqual(peers.allow(Self.host), .approved)
        XCTAssertEqual(peers.summaryText, "1 approved")
        XCTAssertEqual(peers.recentlyBlocked, [])
        XCTAssertEqual(defaults.stringArray(forKey: OSCPeersCoordinator.approvedKey), ["192.168.1.20"])
        transport.send(.datagram(packet, peer: Self.host))
        XCTAssertEqual(receiver.testValue, 0.25, "applies from the next datagram, no restart (OSC-008-R8)")

        peers.remove(Self.host)
        XCTAssertEqual(defaults.stringArray(forKey: OSCPeersCoordinator.approvedKey), [])
        transport.send(.datagram(packet, peer: .ipv4(10, 0, 0, 9)))
        await settle { peers.blockedCount == 2 }
        XCTAssertEqual(peers.recentlyBlocked, [.ipv4(10, 0, 0, 9)])

        osc.setEnabled(false)
        XCTAssertEqual(peers.recentlyBlocked, [], "OSC off forgets blocked hosts (OSC-008-R11)")
        XCTAssertEqual(peers.blockedCount, 0)
        XCTAssertTrue(peers.isEnabled, "the allowlist switch itself is kept")
    }

    func testAFullListRefusesAnotherHost() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let peers = OSCPeersCoordinator(allowlist: OSCPeerAllowlist(), defaults: defaults)
        for i in 1...OSCPeerAllowlist.maximumApproved { XCTAssertEqual(peers.allow(.ipv4(10, 0, 0, UInt8(i))), .approved) }
        XCTAssertTrue(peers.isFull)
        XCTAssertEqual(peers.allow(.ipv4(10, 0, 1, 1)), .full)
        XCTAssertEqual(defaults.stringArray(forKey: OSCPeersCoordinator.approvedKey)?.count, OSCPeerAllowlist.maximumApproved)
    }
}
