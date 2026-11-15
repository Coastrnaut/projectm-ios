// OSC-012-T07, T14, T15: peer cue sync's pure parts (specs/291-osc-012-peer-cue-sync, contract C1 to C5): the wire
// message, the leader's bounded schedule, the follower's newest-seq rule, the inbox, the dispatcher's message tap
// behind the allow list, and `OSCSender.postCue`. Every time is an argument or an injected clock; runs on every host.
@testable import PerformanceControl
import Synchronization
import XCTest

final class OSCCueSyncTests: XCTestCase {
    static let cueA = "0C1D2E3F-0000-4000-8000-00000000000A"
    static let cueB = "0C1D2E3F-0000-4000-8000-00000000000B"
    static let ms: UInt64 = 1_000_000

    private func message(_ cue: String, seq: Int32, offset: Int32 = 0, session: Int32 = 7) -> OSCMessage {
        OSCCueSyncMessage(cueID: cue, seq: seq, offsetMilliseconds: offset, session: session)!.oscMessage
    }

    // MARK: C1 message

    func testWireBytesAndRoundTrip() throws {
        let cue = try XCTUnwrap(OSCCueSyncMessage(cueID: "A", seq: 2, offsetMilliseconds: 1500, session: 9))
        let bytes = OSCEncoder.encode(cue.oscMessage)
        XCTAssertEqual(bytes, Array("/projectm/cue".utf8) + [0, 0, 0] + Array(",siii".utf8) + [0, 0, 0]
                       + [0x41, 0, 0, 0] + [0, 0, 0, 2] + [0, 0, 0x05, 0xDC] + [0, 0, 0, 9])
        guard case .success(.message(let decoded)) = OSCDecoder.decodePacket(bytes) else { return XCTFail("decodes") }
        XCTAssertEqual(OSCCueSyncMessage(decoded), cue)
    }

    func testMalformedMessagesAreRefused() {
        XCTAssertNil(OSCCueSyncMessage(cueID: "", seq: 1, offsetMilliseconds: 0, session: 1))
        XCTAssertNil(OSCCueSyncMessage(cueID: String(repeating: "x", count: 65), seq: 1, offsetMilliseconds: 0, session: 1))
        XCTAssertNotNil(OSCCueSyncMessage(cueID: String(repeating: "x", count: 64), seq: 1, offsetMilliseconds: 0, session: 1))
        XCTAssertNil(OSCCueSyncMessage(cueID: "A", seq: 0, offsetMilliseconds: 0, session: 1))
        XCTAssertNil(OSCCueSyncMessage(cueID: "A", seq: 1, offsetMilliseconds: -1, session: 1))
        let address = OSCCueSyncMessage.address
        XCTAssertNil(OSCCueSyncMessage(OSCMessage(address: address, arguments: [.string("A"), .int(1), .int(0)])))
        XCTAssertNil(OSCCueSyncMessage(OSCMessage(address: address, arguments: [.string("A"), .float(1), .int(0), .int(1)])))
        XCTAssertNil(OSCCueSyncMessage(OSCMessage(address: "/projectm/scene", arguments: [.string("A"), .int(1), .int(0), .int(1)])))
        XCTAssertEqual(OSCCueSyncMessage.milliseconds(from: 5, to: 2), 0)
        XCTAssertEqual(OSCCueSyncMessage.milliseconds(from: 0, to: UInt64.max), Int32.max)
    }

    // MARK: C2 leader

    func testLeaderBurstThenHeartbeat() throws {
        var leader = OSCCueSyncLeader(session: 3)
        XCTAssertNil(leader.nextDue, "nothing due without a cue")
        leader.cueChanged(Self.cueA, startedAt: 1_000 * Self.ms, now: 1_000 * Self.ms)
        var sent: [(UInt64, OSCCueSyncMessage)] = []
        var now: UInt64 = 1_000 * Self.ms
        while now <= 6_000 * Self.ms {   // 5 s in 10 ms ticks
            if let m = leader.due(now: now) { sent.append((now, m)) }
            now += 10 * Self.ms
        }
        let times: [UInt64] = sent.map { $0.0 / Self.ms }
        XCTAssertEqual(times, [1_000, 1_100, 1_300, 3_300, 5_300])
        XCTAssertEqual(sent.map { $0.1.seq }, [1, 1, 1, 1, 1])
        XCTAssertEqual(sent.map { $0.1.offsetMilliseconds }, [0, 100, 300, 2_300, 4_300])
        XCTAssertEqual(leader.burstSendsSinceChange, 3)

        // A newer change cancels the old burst; a late tick collapses overdue slots into one send.
        leader.cueChanged(Self.cueB, startedAt: 7_000 * Self.ms, now: 7_000 * Self.ms)
        let late = try XCTUnwrap(leader.due(now: 7_350 * Self.ms))
        XCTAssertEqual(late.cueID, Self.cueB)
        XCTAssertEqual(late.seq, 2)
        XCTAssertEqual(leader.nextDue, 9_350 * Self.ms, "all three slots were overdue: heartbeat next")
        XCTAssertEqual(leader.burstSendsSinceChange, 1)

        leader.stop()
        XCTAssertNil(leader.due(now: 20_000 * Self.ms))
        XCTAssertNil(leader.nextDue)
        leader.cueChanged("", startedAt: 0, now: 0)
        XCTAssertNil(leader.nextDue, "an invalid cue ID stops")
    }

    // MARK: C3 follower

    func testFollowerAppliesNewestOnlyAndAligns() {
        var follower = OSCCueSyncFollower()
        let has: (String) -> Bool = { (id: String) -> Bool in id == Self.cueA || id == Self.cueB }
        let now: UInt64 = 10_000 * Self.ms
        XCTAssertEqual(follower.receive(message(Self.cueA, seq: 2, offset: 1_500), approved: true, now: now, hasCue: has),
                       .apply(cueID: Self.cueA, alignedStart: 8_500 * Self.ms))
        XCTAssertEqual(follower.receive(message(Self.cueA, seq: 2, offset: 3_500), approved: true, now: now, hasCue: has), .duplicate)
        XCTAssertEqual(follower.receive(message(Self.cueB, seq: 1), approved: true, now: now, hasCue: has), .duplicate, "older seq")
        XCTAssertEqual(follower.receive(message(Self.cueB, seq: 3, offset: 20_000), approved: true, now: now, hasCue: has),
                       .apply(cueID: Self.cueB, alignedStart: 0), "an offset beyond the clock clamps to 0")
        // A restarted leader (new session, seq 1) is accepted.
        XCTAssertEqual(follower.receive(message(Self.cueA, seq: 1, session: 8), approved: true, now: now, hasCue: has),
                       .apply(cueID: Self.cueA, alignedStart: now))
        XCTAssertEqual(follower.counters.applied, 3)
        XCTAssertEqual(follower.counters.duplicates, 2)
        XCTAssertEqual(follower.state, .following(cueID: Self.cueA, alignedStart: now))
    }

    func testUnknownUnapprovedAndMalformedNeverApply() {
        var follower = OSCCueSyncFollower()
        let has: (String) -> Bool = { (id: String) -> Bool in id == Self.cueA }
        XCTAssertEqual(follower.receive(message(Self.cueA, seq: 1), approved: false, now: 0, hasCue: has), .unapproved)
        XCTAssertEqual(follower.receive(OSCMessage(address: OSCCueSyncMessage.address, arguments: [.string(Self.cueA)]),
                                        approved: true, now: 0, hasCue: has), .malformed)
        XCTAssertNil(follower.lastSession, "neither changes the last accepted seq")
        XCTAssertEqual(follower.receive(message(Self.cueB, seq: 4), approved: true, now: 0, hasCue: has), .unknownCue(Self.cueB))
        XCTAssertEqual(follower.receive(message(Self.cueB, seq: 4), approved: true, now: 0, hasCue: has), .duplicate,
                       "the heartbeat of an unknown cue is not reported again")
        XCTAssertEqual(follower.state, .unknownCue(Self.cueB))
        XCTAssertEqual(follower.counters, {
            var c = OSCCueSyncFollowerCounters()
            c.unapproved = 1; c.malformed = 1; c.unknown = 1; c.duplicates = 1
            return c
        }())
        follower.reset()
        XCTAssertEqual(follower.state, .waiting)
        XCTAssertEqual(follower.receive(message(Self.cueA, seq: 1), approved: true, now: 0, hasCue: has),
                       .apply(cueID: Self.cueA, alignedStart: 0))
    }

    // MARK: R13 inbox

    func testInboxKeepsEightAndAsksForOneHop() {
        let inbox = OSCCueSyncInbox()
        var hops = 0
        for i in 0..<20 where inbox.offer(OSCCueSyncReceipt(message: message(Self.cueA, seq: Int32(i + 1)), receivedAt: UInt64(i))) {
            hops += 1
        }
        XCTAssertEqual(hops, 1, "one hop while one is pending")
        XCTAssertEqual(inbox.count, OSCCueSyncInbox.capacity)
        let taken = inbox.take()
        XCTAssertEqual(taken.map(\.receivedAt), Array(12..<20).map(UInt64.init), "the newest 8, in order")
        XCTAssertFalse(inbox.isHopPending)
        XCTAssertTrue(inbox.offer(OSCCueSyncReceipt(message: message(Self.cueA, seq: 30), receivedAt: 30)))
    }

    // MARK: C4 receive path

    func testTapReceivesOnlyAllowedMessages() throws {
        let factory = FakeTransportFactory()
        let receiver = OSCReceiver(makeTransport: { factory.make() })
        receiver.start(port: 9000)
        let transport = try XCTUnwrap(factory.last)
        transport.send(.ready(port: 9000))
        let approved = OSCPeerAddress.ipv4(192, 168, 1, 20)
        let stranger = OSCPeerAddress.ipv4(192, 168, 1, 99)
        let bytes = OSCEncoder.encode(message(Self.cueA, seq: 1))

        // No tap: an unknown address, as before OSC-012.
        transport.send(.datagram(bytes, peer: approved))
        XCTAssertEqual(receiver.counters.unknownAddresses, 1)

        let tapped = Mutex<[OSCMessage]>([])
        receiver.dispatcher.setMessageTap(address: OSCCueSyncMessage.address) { (m: OSCMessage) -> Void in tapped.withLock { $0.append(m) } }
        XCTAssertEqual(receiver.dispatcher.messageTapAddress, OSCCueSyncMessage.address)
        receiver.peerAllowlist.setEnabled(true)
        XCTAssertEqual(receiver.peerAllowlist.approve(approved), .approved)
        transport.send(.datagram(bytes, source: OSCSourceID(rawValue: 1), peer: stranger))
        XCTAssertEqual(tapped.withLock { $0.count }, 0, "an unapproved host never reaches the tap")
        transport.send(.datagram(bytes, source: OSCSourceID(rawValue: 2), peer: approved))
        XCTAssertEqual(tapped.withLock { $0 }, [message(Self.cueA, seq: 1)])
        XCTAssertEqual(receiver.counters.tapped, 1)
        XCTAssertEqual(receiver.counters.unknownAddresses, 1, "a tapped message is not unknown")

        receiver.dispatcher.setMessageTap(address: OSCCueSyncMessage.address, handler: nil)
        XCTAssertNil(receiver.dispatcher.messageTapAddress)
        transport.send(.datagram(bytes, source: OSCSourceID(rawValue: 2), peer: approved))
        XCTAssertEqual(tapped.withLock { $0.count }, 1)
        receiver.stop()
    }

    // MARK: C5 send path

    func testPostCueUsesTheDestinationAndTheCapButNotTheKinds() throws {
        let clock = FakeMonotonicClock()
        let transport = FakeSendTransport()
        let sender = OSCSender(transport: transport, clock: clock.clock)
        let cue = try XCTUnwrap(OSCCueSyncMessage(cueID: Self.cueA, seq: 1, offsetMilliseconds: 0, session: 1))
        XCTAssertEqual(sender.postCue(cue), .inactive)
        sender.setOptions(kinds: [], includeSceneNames: false)
        sender.configure(destination: OSCSendDestination(host: .ipv4(192, 168, 1, 20), port: 9001))
        XCTAssertEqual(sender.postCue(cue), .sent, "no kind choice is needed")
        XCTAssertEqual(transport.sent, [OSCEncoder.encode(cue.oscMessage)])
        for _ in 1..<OSCSendRateCap.defaultLimit { XCTAssertEqual(sender.postCue(cue), .sent) }
        XCTAssertEqual(sender.postCue(cue), .rateLimited, "the 60/s cap applies")
        sender.configure(destination: nil)
        XCTAssertEqual(sender.postCue(cue), .inactive)
    }
}
