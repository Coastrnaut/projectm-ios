// OSC-008-T05 to T07: the peer allowlist (specs/200-osc-008-peer-allowlist, contract A1-A3).
// The roadmap acceptance, "Unapproved source address cannot change a scene", goes through the receiver with a fake
// transport: encoded datagrams carrying a peer host, a fake clock, the OSC-003 glow route and the test route.
// No networking; Linux-safe.
import ParameterGraph
@testable import PerformanceControl
import XCTest

final class OSCPeerAllowlistTests: XCTestCase {
    private static let intensity: ParameterID = "effect.bloom.intensity"
    private static let glowAlias = "/projectm/param/glow.intensity"
    private static let approvedHost = OSCPeerAddress.ipv4(192, 168, 1, 20)
    private static let otherHost = OSCPeerAddress.ipv4(192, 168, 1, 30)

    // MARK: Rule and text (T05)

    func testMappedIPv4IsTheSameHostAndTextRoundTrips() throws {
        let mapped = OSCPeerAddress.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 192, 168, 1, 20])
        XCTAssertEqual(mapped.normalized, Self.approvedHost)
        XCTAssertEqual(Self.approvedHost.text, "192.168.1.20")
        let linkLocal = OSCPeerAddress.ipv6([0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0x12, 0x34, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(linkLocal.text, "fe80::1234:0:0:1")
        XCTAssertEqual(linkLocal.storageText, "fe80:0:0:0:1234:0:0:1")
        let loopback6 = OSCPeerAddress.ipv6(Array(repeating: 0, count: 15) + [1])
        XCTAssertEqual(loopback6.text, "::1")
        for host in [Self.approvedHost, linkLocal, loopback6, OSCPeerAddress.ipv4(10, 0, 0, 255)] {
            XCTAssertEqual(OSCPeerAddress(text: host.storageText), host, host.storageText)
            XCTAssertEqual(OSCPeerAddress(text: host.text), host, host.text)
        }
        for bad in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "1..2.3", "a.b.c.d", "fe80:::1", "1:2:3:4:5:6:7:8:9",
                    "1::2::3", "12345::", "fe80::1%en0", "::ffff:1.2.3.4", "g::1", "1:2:3:4:5:6:7"] {
            XCTAssertNil(OSCPeerAddress(text: bad), bad)
        }
    }

    func testApproveRefusesNonLocalDuplicatesAndAFullList() {
        let list = OSCPeerAllowlist()
        XCTAssertFalse(list.isEnabled, "off by default (OSC-008-R1)")
        XCTAssertEqual(list.approve(.ipv4(8, 8, 8, 8)), .notLocal)
        XCTAssertEqual(list.approve(Self.approvedHost), .approved)
        XCTAssertEqual(list.approve(.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 192, 168, 1, 20])), .alreadyApproved)
        for i in 1..<OSCPeerAllowlist.maximumApproved { XCTAssertEqual(list.approve(.ipv4(10, 0, 0, UInt8(i))), .approved) }
        XCTAssertEqual(list.approve(.ipv4(10, 0, 1, 1)), .full, "a full list refuses; nothing is evicted")
        XCTAssertEqual(list.approved.count, OSCPeerAllowlist.maximumApproved)
        list.remove(Self.approvedHost)
        XCTAssertEqual(list.approve(.ipv4(10, 0, 1, 1)), .approved)

        list.setApproved([.ipv4(8, 8, 8, 8), Self.otherHost, Self.otherHost, .ipv4(172, 32, 0, 1)])
        XCTAssertEqual(list.approved, [Self.otherHost], "non-local and duplicate entries are dropped on load")
    }

    func testRecentlyBlockedKeepsFourDistinctHostsMostRecentFirst() {
        let list = OSCPeerAllowlist()
        XCTAssertTrue(list.admits(.ipv4(10, 0, 0, 1)), "off: everyone, nothing recorded")
        XCTAssertEqual(list.recentlyBlocked, [])
        list.setEnabled(true)
        for i in 1...5 { XCTAssertFalse(list.admits(.ipv4(10, 0, 0, UInt8(i)))) }
        XCTAssertFalse(list.admits(.ipv4(10, 0, 0, 3)))
        XCTAssertFalse(list.admits(nil), "an unknown host is refused (fail closed)")
        XCTAssertEqual(list.recentlyBlocked, [.ipv4(10, 0, 0, 3), .ipv4(10, 0, 0, 5), .ipv4(10, 0, 0, 4), .ipv4(10, 0, 0, 2)])
        XCTAssertEqual(list.approve(.ipv4(10, 0, 0, 5)), .approved)
        XCTAssertEqual(list.recentlyBlocked.count, 3, "an approved host leaves the blocked list")
        XCTAssertTrue(list.admits(.ipv4(10, 0, 0, 5)))
        list.setEnabled(false)
        XCTAssertEqual(list.recentlyBlocked, [], "turning the allowlist off forgets blocked hosts")
    }

    // MARK: Acceptance (T06)

    private struct Fixture {
        let receiver: OSCReceiver
        let transport: FakeTransport
    }

    private func makeFixture() throws -> Fixture {
        let group = ParameterGroup(id: "effect.bloom", displayName: "Glow")
        let intensity = ParameterDescriptor(id: Self.intensity, displayName: "Intensity", group: group, unit: .normalized,
                                            kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault)
        let registry = try ParameterRegistry(descriptors: [OSCReceiverCatalog.testValueDescriptor, intensity])
        let table = OSCParameterRoutes.table(routable: [intensity], builtInAliases: [(Self.glowAlias, Self.intensity)], userAliases: [])
        let clock = FakeMonotonicClock()
        let factory = FakeTransportFactory()
        let receiver = OSCReceiver(store: ParameterStore(registry: registry), routes: OSCParameterRoutes.active(table, disabled: []),
                                   clock: clock.clock, scheduler: ManualFlushScheduler(clock: clock).scheduler,
                                   makeTransport: { factory.make() })
        receiver.start(port: 9000)
        let transport = try XCTUnwrap(factory.last)
        transport.send(.ready(port: 9000))
        return Fixture(receiver: receiver, transport: transport)
    }

    private func packet(_ address: String, _ value: Float) -> [UInt8] {
        OSCEncoder.encode(OSCMessage(address: address, arguments: [.float(value)]))
    }

    private func snapshot(_ store: ParameterStore) -> [ParameterID: UInt64] {
        var result: [ParameterID: UInt64] = [:]
        for id in store.registry.ids { result[id] = store.double(id)?.bitPattern }
        return result
    }

    func testUnapprovedSourceAddressCannotChangeTheSceneAndAnApprovedOneCan() throws {
        let f = try makeFixture()
        let store = f.receiver.store
        f.receiver.peerAllowlist.setEnabled(true)
        XCTAssertEqual(f.receiver.peerAllowlist.approve(Self.approvedHost), .approved)
        let before = snapshot(store)

        // An unapproved host: a glow route, the test route and a bundle change nothing and are never decoded.
        f.transport.send(.datagram(packet(Self.glowAlias, 1), source: OSCSourceID(rawValue: 1), peer: Self.otherHost))
        f.transport.send(.datagram(packet(OSCReceiverCatalog.testAddress, 0.9), source: OSCSourceID(rawValue: 1), peer: Self.otherHost))
        f.transport.send(.datagram(packet(Self.glowAlias, 1), peer: nil))
        XCTAssertEqual(snapshot(store), before, "every parameter value is bit-identical")
        XCTAssertEqual(f.receiver.dispatcher.liveValues, [:], "no live value reaches the visual")
        var counters = f.receiver.counters
        XCTAssertEqual(counters.droppedUnapproved, 3)
        XCTAssertEqual(counters.received, 0, "dropped before the limiter and the decoder")
        XCTAssertEqual(f.receiver.peerAllowlist.recentlyBlocked, [Self.otherHost])

        // The approved host (as an IPv4-mapped IPv6 address from another connection) applies.
        let mapped = OSCPeerAddress.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 192, 168, 1, 20])
        f.transport.send(.datagram(packet(Self.glowAlias, 0.25), source: OSCSourceID(rawValue: 2), peer: mapped))
        XCTAssertEqual(store.double(Self.intensity), 0.25)
        XCTAssertEqual(f.receiver.dispatcher.liveValues[Self.intensity], 0.25)
        counters = f.receiver.counters
        XCTAssertEqual(counters.applied, 1)

        // Removing the host applies from the next datagram, without a restart (OSC-008-R8).
        f.receiver.peerAllowlist.remove(Self.approvedHost)
        f.transport.send(.datagram(packet(Self.glowAlias, 0.75), source: OSCSourceID(rawValue: 2), peer: Self.approvedHost))
        XCTAssertEqual(store.double(Self.intensity), 0.25)
        XCTAssertEqual(f.receiver.counters.droppedUnapproved, 4)
    }

    func testWithTheAllowlistOffEveryLocalHostAppliesAsBefore() throws {
        let f = try makeFixture()
        f.transport.send(.datagram(packet(Self.glowAlias, 0.25), peer: Self.otherHost))
        f.transport.send(.datagram(packet(OSCReceiverCatalog.testAddress, 0.5), peer: nil))
        XCTAssertEqual(f.receiver.store.double(Self.intensity), 0.25)
        XCTAssertEqual(f.receiver.testValue, 0.5)
        XCTAssertEqual(f.receiver.counters.droppedUnapproved, 0)
        XCTAssertEqual(f.receiver.peerAllowlist.recentlyBlocked, [])
    }

    // MARK: Seeded fuzz (T07)

    /// SplitMix64: a fixed seed gives the same run on every host.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testSeededFuzzOfMalformedAndForeignSourcePacketsNeverChangesTheScene() throws {
        let f = try makeFixture()
        let allowlist = f.receiver.peerAllowlist
        allowlist.setEnabled(true)
        allowlist.approve(Self.approvedHost)
        var rng = SeededGenerator(state: 0x05C8_0008)
        let foreign: [OSCPeerAddress?] = [nil, Self.otherHost, .ipv4(8, 8, 8, 8), .ipv4(127, 0, 0, 1),
                                          .ipv6([0xFE, 0x80] + Array(repeating: 0, count: 13) + [2]), .ipv6([1, 2, 3])]
        var unapproved = 0
        for i in 0..<500 {
            let valid = packet(i % 2 == 0 ? Self.glowAlias : OSCReceiverCatalog.testAddress, Float(i % 100) / 100)
            var bytes: [UInt8]
            switch rng.next() % 3 {
            case 0: bytes = valid
            case 1:   // flip a few bytes of a valid packet
                bytes = valid
                for _ in 0..<Int(rng.next() % 4 + 1) { bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: rng.next()) }
            default:  // random bytes, sometimes empty
                bytes = (0..<Int(rng.next() % 64)).map { (_: Int) -> UInt8 in UInt8(truncatingIfNeeded: rng.next()) }
            }
            let fromApproved = rng.next() % 4 == 0
            let peer: OSCPeerAddress? = fromApproved ? Self.approvedHost : foreign[Int(rng.next() % UInt64(foreign.count))]
            let before = snapshot(f.receiver.store)
            let countersBefore = f.receiver.counters
            f.transport.send(.datagram(bytes, source: OSCSourceID(rawValue: UInt64(i % 5 + 1)), peer: peer))
            if !fromApproved {
                unapproved += 1
                XCTAssertEqual(snapshot(f.receiver.store), before, "datagram \(i) from \(String(describing: peer)) changed a value")
                XCTAssertEqual(f.receiver.counters.received, countersBefore.received, "datagram \(i) reached the dispatcher")
            }
        }
        let counters = f.receiver.counters
        XCTAssertEqual(counters.droppedUnapproved, unapproved)
        XCTAssertEqual(counters.received, 500 - unapproved, "only the approved host's datagrams reached the dispatcher")
        XCTAssertGreaterThan(unapproved, 300)
        XCTAssertGreaterThan(counters.applied, 0, "approved valid packets still apply")
        XCTAssertLessThanOrEqual(allowlist.recentlyBlocked.count, OSCPeerAllowlist.maximumRecentlyBlocked)
        XCTAssertFalse(allowlist.recentlyBlocked.contains(Self.approvedHost))
    }
}
