// PlaybackTapGateTests.swift — the lock-free gate in front of the playback tap (AUD-006-T04;
// AUD-006-R10, R28). After `close()` returns, no write that entered with an older token is still
// in flight, and none can start.
import Foundation
import Synchronization
import XCTest
@testable import CaptureKit

final class PlaybackTapGateTests: XCTestCase {
    func testCurrentTokenEntersAndAnOldOneDoesNot() {
        let gate = PlaybackTapGate()
        let first = gate.token
        XCTAssertTrue(gate.enter(first))
        gate.leave()
        let second = gate.close()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(gate.token, second)
        XCTAssertFalse(gate.enter(first), "a tap installed before the cut may not write")
        gate.leave()                                   // harmless after a refused enter
        XCTAssertTrue(gate.enter(second))
        gate.leave()
    }

    func testEveryCloseReturnsANewToken() {
        let gate = PlaybackTapGate()
        var seen: Set<PlaybackTapGate.Token> = [gate.token]
        for _ in 0..<100 { XCTAssertTrue(seen.insert(gate.close()).inserted) }
    }

    func testCloseDoesNotWaitWhenNothingIsWriting() {
        let gate = PlaybackTapGate()
        let start = Date()
        for _ in 0..<10_000 { gate.close() }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testNoStaleWriteIsInFlightAfterClose() {
        let gate = PlaybackTapGate()
        let inside = Atomic<UInt64>(0)                 // the token of the write in flight, 0 = none
        let done = Atomic<Bool>(false)
        let writes = Atomic<Int>(0)
        let writer = Thread {
            while !done.load(ordering: .relaxed) {
                let token = gate.token                 // like a newly installed tap
                if gate.enter(token) {
                    inside.store(token, ordering: .sequentiallyConsistent)
                    writes.add(1, ordering: .relaxed)
                    inside.store(0, ordering: .sequentiallyConsistent)
                }
                gate.leave()
            }
        }
        writer.start()
        var stale = 0
        for _ in 0..<2_000 {
            let current = gate.close()
            let seen = inside.load(ordering: .sequentiallyConsistent)
            if seen != 0 && seen < current { stale += 1 }
        }
        done.store(true, ordering: .relaxed)
        while !writer.isFinished { usleep(1_000) }
        XCTAssertEqual(stale, 0, "a write with an old token was still in flight after close() returned")
        XCTAssertGreaterThan(writes.load(ordering: .relaxed), 0, "the writer did run")
    }
}
