// OSC-012-T08: peer cue sync over real UDP on loopback (OSC-012-S5). The leader is a leader model plus `OSCSender` over
// the real `NetworkOSCSender`; the follower is an `OSCReceiver` over the real `NetworkDatagramTransport` with the allow
// list on and 127.0.0.1 approved, whose message tap feeds an inbox drained into a follower model. macOS host and
// simulator only (Linux compiles this out); positive waits use generous ceilings.
#if canImport(Network)
import Foundation
@testable import PerformanceControl
import Synchronization
import XCTest

final class OSCCueSyncLoopbackTests: XCTestCase {
    func testLeaderCueReachesAnApprovedFollowerOverUDP() throws {
        let clock = OSCMonotonicClock.continuous()
        // Follower: the real listener on a free port, allow list on, loopback approved.
        let receiver = OSCReceiver(makeTransport: { NetworkDatagramTransport() })
        let ready = expectation(description: "listening")
        ready.assertForOverFulfill = false
        let failed = Mutex(false)
        receiver.onStateChange { (state: OSCReceiverState) -> Void in
            switch state {
            case .listening: ready.fulfill()
            case .failed:
                failed.withLock { $0 = true }
                ready.fulfill()
            default: break
            }
        }
        receiver.peerAllowlist.setEnabled(true)
        XCTAssertEqual(receiver.peerAllowlist.approve(.ipv4(127, 0, 0, 1)), .approved)
        receiver.start(port: 0)
        wait(for: [ready], timeout: 5)
        defer { receiver.stop() }
        guard !failed.withLock({ $0 }), case .listening(let port) = receiver.state else {
            throw XCTSkip("the loopback listener could not open here; the sandbox may forbid it")
        }
        let inbox = OSCCueSyncInbox()
        let arrived = expectation(description: "cue arrived")
        arrived.assertForOverFulfill = false
        receiver.dispatcher.setMessageTap(address: OSCCueSyncMessage.address) { (message: OSCMessage) -> Void in
            _ = inbox.offer(OSCCueSyncReceipt(message: message, receivedAt: clock.now()))
            arrived.fulfill()
        }

        // Leader: the reviewed sender to 127.0.0.1, then one cue change and its burst.
        let sender = OSCSender(transport: NetworkOSCSender(), clock: clock)
        sender.configure(destination: try XCTUnwrap(OSCSendDestination(host: .ipv4(127, 0, 0, 1), port: port)))
        var leader = OSCCueSyncLeader(session: 5)
        let cue = "0C1D2E3F-0000-4000-8000-00000000000A"
        let start: UInt64 = clock.now()
        leader.cueChanged(cue, startedAt: start, now: start)
        let first = try XCTUnwrap(leader.due(now: start))
        XCTAssertEqual(sender.postCue(first), .sent)
        wait(for: [arrived], timeout: 5)

        var follower = OSCCueSyncFollower()
        var decisions: [OSCCueSyncDecision] = []
        for receipt in inbox.take() {
            decisions.append(follower.receive(receipt.message, approved: receiver.peerAllowlist.isEnabled, now: receipt.receivedAt,
                                              hasCue: { (id: String) -> Bool in id == cue }))
        }
        guard case .apply(let applied, let alignedStart)? = decisions.first else { return XCTFail("applied: \(decisions)") }
        XCTAssertEqual(applied, cue)
        XCTAssertLessThanOrEqual(alignedStart, clock.now())
        XCTAssertEqual(receiver.counters.tapped, 1)
        sender.configure(destination: nil)
    }
}
#endif
