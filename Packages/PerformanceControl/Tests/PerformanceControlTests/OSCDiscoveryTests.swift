// OSC-011-T04: the pure discovery rules and the receiver's advertisement (OSC-011-R1, R4 to R9; contract D1).
// Linux-safe: no networking.
@testable import PerformanceControl
import Synchronization
import XCTest

/// A transport that records `advertise` calls (and otherwise behaves like `FakeTransport`).
final class AdvertisingSpyTransport: OSCDatagramTransport, Sendable {
    private let calls = Mutex<[String?]>([])
    private let handler = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)
    var advertised: [String?] { calls.withLock { $0 } }

    func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) { handler.withLock { $0 = events } }
    func stop() { handler.withLock { $0 }?(.cancelled) }
    func advertise(_ name: String?) { calls.withLock { $0.append(name) } }
}

final class OSCDiscoveryTests: XCTestCase {
    func testServiceTypeAndDomainAreTheOneLocalType() {
        XCTAssertEqual(OSCDiscovery.serviceType, "_projectm-osc._udp")
        XCTAssertEqual(OSCDiscovery.domain, "local.")
        XCTAssertEqual(OSCDiscovery.maximumPeers, 16)
    }

    func testAnnouncedNameIsGenericWithFourHexDigits() {
        XCTAssertEqual(OSCDiscovery.announcedName(suffix: 0x0A1F), "projectM 0A1F")
        XCTAssertEqual(OSCDiscovery.announcedName(suffix: 0), "projectM 0000")
        XCTAssertEqual(OSCDiscovery.announcedName(suffix: 0xFFFF), "projectM FFFF")
        let random: String = OSCDiscovery.randomAnnouncedName()
        XCTAssertNotNil(random.wholeMatch(of: /projectM [0-9A-F]{4}/), random)
    }

    func testCleanNameDropsControlCharactersAndCaps() {
        XCTAssertEqual(OSCDiscovery.cleanName("  Desk\u{0}\n\u{7}Mixer \u{202E} "), "DeskMixer")
        XCTAssertEqual(OSCDiscovery.cleanName(""), OSCDiscovery.unnamed)
        XCTAssertEqual(OSCDiscovery.cleanName("\u{1B}\u{9}"), OSCDiscovery.unnamed)
        XCTAssertEqual(OSCDiscovery.cleanName(String(repeating: "é", count: 200)).count, 63)
        // A few fuzz-style inputs from a fixed seed: never empty, never over 63, never a control character.
        var seed: UInt64 = 0x5EED
        for _ in 0..<200 {
            var scalars: [Unicode.Scalar] = []
            for _ in 0..<Int(seed % 90) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                if let s = Unicode.Scalar(UInt32(truncatingIfNeeded: seed >> 33) % 0x3000) { scalars.append(s) }
            }
            let name: String = OSCDiscovery.cleanName(String(String.UnicodeScalarView(scalars)))
            XCTAssertFalse(name.isEmpty)
            XCTAssertLessThanOrEqual(name.count, 63)
            XCTAssertFalse(name.unicodeScalars.contains { $0.properties.generalCategory == .control })
        }
    }

    func testActivityNeedsSwitchOSCAndForeground() {
        XCTAssertEqual(OSCDiscovery.activity(browse: false, advertise: false, oscEnabled: true, appActive: true), .none)
        XCTAssertEqual(OSCDiscovery.activity(browse: true, advertise: true, oscEnabled: false, appActive: true), .none)
        XCTAssertEqual(OSCDiscovery.activity(browse: true, advertise: true, oscEnabled: true, appActive: false), .none)
        XCTAssertEqual(OSCDiscovery.activity(browse: true, advertise: false, oscEnabled: true, appActive: true),
                       OSCDiscovery.Activity(browse: true, advertise: false))
        XCTAssertEqual(OSCDiscovery.activity(browse: false, advertise: true, oscEnabled: true, appActive: true),
                       OSCDiscovery.Activity(browse: false, advertise: true))
    }

    func testPeersDropNonLocalOwnNameAndCap() {
        let raw: [OSCDiscoveredPeer] = [
            OSCDiscoveredPeer(name: "Zeta", address: .ipv4(192, 168, 1, 9), port: 9000),
            OSCDiscoveredPeer(name: "Public", address: .ipv4(8, 8, 8, 8), port: 9000),
            OSCDiscoveredPeer(name: "projectM 0A1F", address: .ipv4(192, 168, 1, 2), port: 9000),
            OSCDiscoveredPeer(name: "alpha\n", address: nil, port: nil),
        ]
        let shown: [OSCDiscoveredPeer] = OSCDiscovery.peers(raw, excluding: "projectM 0A1F")
        XCTAssertEqual(shown.map(\.name), ["alpha", "Zeta"])
        XCTAssertNil(shown[0].destination)
        XCTAssertEqual(shown[1].destination, OSCSendDestination(host: .ipv4(192, 168, 1, 9), port: 9000))
        XCTAssertEqual(shown[1].addressText, "192.168.1.9:9000")
        let many: [OSCDiscoveredPeer] = (0..<40).map { (i: Int) -> OSCDiscoveredPeer in OSCDiscoveredPeer(name: "Peer \(i)") }
        XCTAssertEqual(OSCDiscovery.peers(many, excluding: nil).count, 16)
    }

    func testLinkLocalIPv6PeerIsListedWithoutDestination() {
        var bytes: [UInt8] = Array(repeating: 0, count: 16)
        bytes[0] = 0xFE; bytes[1] = 0x80; bytes[15] = 1
        let peer = OSCDiscoveredPeer(name: "v6", address: .ipv6(bytes), port: 9000)
        XCTAssertEqual(OSCDiscovery.peers([peer], excluding: nil).count, 1)
        XCTAssertNil(peer.destination, "OSC-005 cannot send to IPv6 link-local")
    }

    func testReceiverAdvertisementReachesCurrentAndLaterTransports() throws {
        let made = Mutex<[AdvertisingSpyTransport]>([])
        let receiver = OSCReceiver(makeTransport: { () -> (any OSCDatagramTransport)? in
            let t = AdvertisingSpyTransport()
            made.withLock { $0.append(t) }
            return t
        })
        XCTAssertNil(receiver.advertisement, "nothing is announced by default")
        receiver.start(port: 9000)
        let first = try XCTUnwrap(made.withLock { $0.first })
        XCTAssertEqual(first.advertised, [], "no announcement without a request")
        receiver.setAdvertisement("projectM 0A1F")
        XCTAssertEqual(first.advertised, ["projectM 0A1F"])
        receiver.start(port: 9001)   // port change: a new transport keeps announcing
        let second = try XCTUnwrap(made.withLock { $0.last })
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.advertised, ["projectM 0A1F"])
        receiver.setAdvertisement(nil)
        XCTAssertEqual(second.advertised, ["projectM 0A1F", nil])
        receiver.stop()
        receiver.setAdvertisement("projectM 0A1F")   // stored, but no transport runs
        XCTAssertEqual(second.advertised, ["projectM 0A1F", nil])
    }
}
