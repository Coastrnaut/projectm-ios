// OSC-011-T10: announce and browse over the real Bonjour stack on this host (OSC-011-R1, R7; research OSC-011-D9).
// The receiver's own listener announces a unique name; `NetworkOSCPeerBrowser` must find it with a local address.
// When the host's multicast DNS does not answer within 5 s (sandbox, no network) the test is skipped, never failed;
// the two-device check is OSC-011-T19 {device}. macOS host and simulator only (Linux compiles this out).
#if canImport(Network)
import Foundation
@testable import PerformanceControl
import Synchronization
import XCTest

final class OSCDiscoveryLoopbackTests: XCTestCase {
    func testOwnAnnouncementIsFoundWithALocalAddress() throws {
        let listener = NetworkDatagramTransport()
        let port = Mutex<UInt16?>(nil)
        let ready = expectation(description: "listener ready")
        ready.assertForOverFulfill = false
        listener.start(port: 0) { (event: OSCTransportEvent) -> Void in
            if case .ready(let p) = event { port.withLock { $0 = p } }
            if case .ready = event { ready.fulfill() }
            if case .failed = event { ready.fulfill() }
        }
        wait(for: [ready], timeout: 5)
        defer { listener.stop() }
        guard let listening = port.withLock({ $0 }) else { throw XCTSkip("no UDP listener on this host") }
        let name: String = OSCDiscovery.randomAnnouncedName() + " test"
        listener.advertise(name)

        let browser = NetworkOSCPeerBrowser()
        let found = expectation(description: "own service resolved")
        found.assertForOverFulfill = false
        let match = Mutex<OSCDiscoveredPeer?>(nil)
        browser.start { (event: OSCBrowserEvent) -> Void in
            guard case .peers(let peers) = event, let peer = peers.first(where: { $0.name == name }), peer.isResolved else { return }
            match.withLock { $0 = peer }
            found.fulfill()
        }
        let result = XCTWaiter.wait(for: [found], timeout: 5)
        browser.cancel()
        guard result == .completed, let peer = match.withLock({ $0 }) else {
            throw XCTSkip("multicast DNS did not answer within 5 s on this host")
        }
        XCTAssertEqual(peer.port, listening)
        XCTAssertTrue(peer.address?.isLocal ?? false)
    }
}
#endif
