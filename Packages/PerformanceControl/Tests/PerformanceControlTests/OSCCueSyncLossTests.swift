// OSC-012-T13: the roadmap acceptance, "Packet loss fixture recovers next cue without infinite retransmission"
// (specs/291-osc-012-peer-cue-sync, OSC-012-S1, S2). A leader and a follower run on one simulated monotonic clock in
// 10 ms ticks; every message the leader hands out is encoded, passed through a lossy link (seeded random loss, a
// burst loss or an outage window) and, when it survives, decoded and given to the follower. Pure and deterministic:
// a 60 s run takes milliseconds of real time.
@testable import PerformanceControl
import XCTest

final class OSCCueSyncLossTests: XCTestCase {
    static let ms: UInt64 = 1_000_000
    static let tick: UInt64 = 10 * ms
    static let cues = ["CUE-A", "CUE-B", "CUE-C", "CUE-D"]

    /// Decides per packet (index from 0, send time) whether it is lost.
    typealias Loss = (_ index: Int, _ time: UInt64) -> Bool

    /// One simulated leader → link → follower pair.
    struct Simulation {
        var leader = OSCCueSyncLeader(session: 42)
        var follower = OSCCueSyncFollower()
        var now: UInt64 = 0
        var packets = 0
        var delivered = 0
        /// (time, cue) of every apply on the follower.
        var applies: [(UInt64, String)] = []
        /// Send times of every message the leader handed out.
        var sendTimes: [UInt64] = []
        let loss: Loss

        init(loss: @escaping Loss) { self.loss = loss }

        mutating func change(to cue: String) { leader.cueChanged(cue, startedAt: now, now: now) }

        /// Runs ticks until `end` (inclusive).
        mutating func run(until end: UInt64) {
            while now <= end {
                if let message = leader.due(now: now) {
                    sendTimes.append(now)
                    let bytes: [UInt8] = OSCEncoder.encode(message.oscMessage)
                    let lost: Bool = loss(packets, now)
                    packets += 1
                    if !lost, case .success(.message(let decoded)) = OSCDecoder.decodePacket(bytes) {
                        delivered += 1
                        let decision = follower.receive(decoded, approved: true, now: now,
                                                        hasCue: { (id: String) -> Bool in OSCCueSyncLossTests.cues.contains(id) })
                        if case let .apply(cueID, _) = decision { applies.append((now, cueID)) }
                    }
                }
                now += OSCCueSyncLossTests.tick
            }
        }

        var followerCue: String? {
            if case let .following(cueID, _) = follower.state { return cueID }
            return nil
        }

        /// Messages handed out in [from, to).
        func sends(from: UInt64, to: UInt64) -> Int { sendTimes.filter { $0 >= from && $0 < to }.count }
    }

    /// A small seeded generator (SplitMix64), the same sequence on every host.
    struct Seeded {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// R5 bound for one change observed for `duration` ns: 3 burst sends plus one heartbeat per 2 s.
    private func bound(_ duration: UInt64) -> Int { 3 + Int(duration / OSCCueSyncLeader.heartbeatInterval) + 1 }

    func testFiftyPercentRandomLossConverges() {
        var rng = Seeded(state: 2026_11_15)
        var lost = Set<Int>()
        for i in 0..<400 where rng.next() % 2 == 0 { lost.insert(i) }
        var sim = Simulation(loss: { (index: Int, _: UInt64) -> Bool in lost.contains(index) })
        for (n, cue) in Self.cues.enumerated() {
            let start: UInt64 = UInt64(n) * 10_000 * Self.ms
            sim.change(to: cue)
            sim.run(until: start + 9_990 * Self.ms)
            XCTAssertEqual(sim.followerCue, cue, "converged on \(cue) before the next change")
            let firstDelivery: UInt64? = sim.applies.first { $0.1 == cue }?.0
            XCTAssertNotNil(firstDelivery)
            XCTAssertLessThanOrEqual(sim.sends(from: start, to: start + 10_000 * Self.ms), bound(10_000 * Self.ms),
                                     "bounded sends for \(cue)")
        }
        XCTAssertGreaterThan(sim.packets - sim.delivered, sim.packets / 3, "the fixture really dropped about half")
        XCTAssertEqual(sim.applies.map(\.1), Self.cues, "each cue applied once, in order: no stale or repeated apply")
    }

    func testBurstLossOfTheFirstThreePacketsRecoversAtTheHeartbeat() {
        var sim = Simulation(loss: { (index: Int, _: UInt64) -> Bool in index < 3 })
        sim.change(to: "CUE-A")
        sim.run(until: 2_290 * Self.ms)
        XCTAssertNil(sim.followerCue, "the whole burst was lost")
        sim.run(until: 2_300 * Self.ms)
        XCTAssertEqual(sim.followerCue, "CUE-A", "the first heartbeat (300 ms + 2 s) recovers it")
        XCTAssertEqual(sim.leader.burstSendsSinceChange, 3)
        XCTAssertEqual(sim.packets, 4, "3 burst sends and 1 heartbeat; nothing else was retransmitted")
    }

    func testFiveSecondOutageRecoversTheLatestCue() {
        let outage: ClosedRange<UInt64> = (1_000 * Self.ms)...(6_000 * Self.ms)
        var sim = Simulation(loss: { (_: Int, time: UInt64) -> Bool in outage.contains(time) })
        sim.change(to: "CUE-A")
        sim.run(until: 990 * Self.ms)
        XCTAssertEqual(sim.followerCue, "CUE-A")
        sim.run(until: 2_000 * Self.ms)
        sim.change(to: "CUE-B")   // both changes happen during the outage
        sim.run(until: 3_000 * Self.ms)
        sim.change(to: "CUE-C")
        sim.run(until: 6_000 * Self.ms)
        XCTAssertEqual(sim.followerCue, "CUE-A", "nothing arrives during the outage")
        sim.run(until: 8_000 * Self.ms)   // the loss ends at 6 s; the next heartbeat is at most 2 s later
        XCTAssertEqual(sim.followerCue, "CUE-C", "the latest cue, by the first heartbeat after the outage")
        XCTAssertEqual(sim.applies.map(\.1), ["CUE-A", "CUE-C"], "the superseded cue B is never applied")
        XCTAssertLessThanOrEqual(sim.applies[1].0, 8_000 * Self.ms)
        XCTAssertEqual(sim.leader.seq, 3)
    }

    func testSendsStayBoundedOverSixtySecondsWithoutChanges() {
        var sim = Simulation(loss: { (_: Int, _: UInt64) -> Bool in true })   // total loss: nothing is ever acknowledged
        sim.change(to: "CUE-A")
        sim.run(until: 60_300 * Self.ms)
        let burst: Int = sim.sends(from: 0, to: 300 * Self.ms + 1)
        let heartbeats: Int = sim.sends(from: 300 * Self.ms + 1, to: 60_300 * Self.ms + 1)
        XCTAssertEqual(burst, 3)
        XCTAssertEqual(heartbeats, 30, "one per 2 s over 60 s")
        XCTAssertLessThanOrEqual(heartbeats, 31)
        XCTAssertEqual(sim.leader.sendsSinceChange, 33)
        for (a, b) in zip(sim.sendTimes.dropFirst(3), sim.sendTimes.dropFirst(4)) {
            XCTAssertGreaterThanOrEqual(b - a, OSCCueSyncLeader.heartbeatInterval, "heartbeats at least 2 s apart")
        }
    }
}
