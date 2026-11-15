// OSC-005-T06, T10: the acceptance criterion over real UDP on loopback (OSC-005-S1, S2):
// "Loopback fixture receives expected payload and disable stops traffic."
//
// The fixture is the receiver's own listener (`NetworkDatagramTransport`, public) on a free port of 127.0.0.1; the
// sender is `OSCSender` over the real `NetworkOSCSender`. macOS host and simulator only (Linux compiles this out).
// The only real-time wait is the short negative window after disable; positive checks use generous ceilings.
#if canImport(Network)
import Foundation
@testable import PerformanceControl
import Synchronization
import XCTest

final class OSCSendLoopbackTests: XCTestCase {
    /// Collects every datagram the fixture receives.
    final class Fixture: @unchecked Sendable {
        let transport = NetworkDatagramTransport()
        let received = Mutex<[[UInt8]]>([])
        let port = Mutex<UInt16?>(nil)
        var onDatagram: (@Sendable ([UInt8]) -> Void)?
    }

    private func openFixture() throws -> (Fixture, UInt16) {
        let fixture = Fixture()
        let ready = expectation(description: "fixture ready")
        ready.assertForOverFulfill = false
        let failed = Mutex(false)
        fixture.transport.start(port: 0) { (event: OSCTransportEvent) -> Void in
            switch event {
            case .ready(let port):
                fixture.port.withLock { $0 = port }
                ready.fulfill()
            case .failed:
                failed.withLock { $0 = true }
                ready.fulfill()
            case .datagram(let bytes, _, _):
                fixture.received.withLock { $0.append(bytes) }
                fixture.onDatagram?(bytes)
            default:
                break
            }
        }
        wait(for: [ready], timeout: 5)
        guard !failed.withLock({ $0 }), let port = fixture.port.withLock({ $0 }) else {
            throw XCTSkip("the loopback fixture could not open here; the sandbox may forbid it")
        }
        return (fixture, port)
    }

    private func waitForCount(_ fixture: Fixture, _ count: Int) {
        let done = expectation(description: "\(count) datagrams")
        done.assertForOverFulfill = false
        fixture.onDatagram = { _ in if fixture.received.withLock({ $0.count }) >= count { done.fulfill() } }
        if fixture.received.withLock({ $0.count }) >= count { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testLoopbackFixtureReceivesExpectedPayloadAndDisableStopsTraffic() throws {
        let (fixture, port) = try openFixture()
        defer { fixture.transport.stop() }
        let sender = OSCSender(transport: NetworkOSCSender())
        sender.setOptions(kinds: [.scene, .beat, .status], includeSceneNames: true)
        let destination = try XCTUnwrap(OSCSendDestination(host: .ipv4(127, 0, 0, 1), port: port))
        sender.configure(destination: destination)

        XCTAssertEqual(sender.post(.scene(name: "Intro")), .sent)
        waitForCount(fixture, 1)
        XCTAssertEqual(sender.post(.beat(1)), .sent)
        waitForCount(fixture, 2)
        let received = fixture.received.withLock { $0 }
        XCTAssertEqual(received[0], Array("/projectm/scene".utf8) + [0, 0x2C, 0x73, 0, 0] + Array("Intro".utf8) + [0, 0, 0])
        XCTAssertEqual(received[1], Array("/projectm/beat".utf8) + [0, 0, 0x2C, 0x69, 0, 0, 0, 0, 0, 1])

        // Disable: queue more sends right before turning it off, then keep posting; nothing more may arrive.
        sender.configure(destination: nil)
        for i in 0..<20 { XCTAssertEqual(sender.post(.beat(Int32(i))), .inactive) }
        let quiet = expectation(description: "quiet window")
        quiet.isInverted = true
        fixture.onDatagram = { _ in quiet.fulfill() }
        wait(for: [quiet], timeout: 0.3)
        XCTAssertEqual(fixture.received.withLock { $0.count }, 2)
    }

    /// R5 at the transport: sends queued and then closed in the same breath are dropped unrun.
    func testCloseDropsQueuedSends() throws {
        let (fixture, port) = try openFixture()
        defer { fixture.transport.stop() }
        let transport = NetworkOSCSender()
        let ready = expectation(description: "ready")
        ready.assertForOverFulfill = false
        transport.open(host: .ipv4(127, 0, 0, 1), port: port) { if $0 == .ready { ready.fulfill() } }
        wait(for: [ready], timeout: 5)
        for _ in 0..<10 { transport.send([0x2F, 0x78, 0, 0, 0x2C, 0, 0, 0]) }
        transport.close()
        for _ in 0..<10 { transport.send([0x2F, 0x79, 0, 0, 0x2C, 0, 0, 0]) }
        let quiet = expectation(description: "quiet window")
        quiet.isInverted = true
        fixture.onDatagram = { _ in quiet.fulfill() }
        wait(for: [quiet], timeout: 0.3)
        XCTAssertEqual(fixture.received.withLock { $0.count }, 0)
    }
}
#endif
