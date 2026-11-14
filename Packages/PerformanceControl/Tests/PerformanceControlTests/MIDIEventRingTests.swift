// MIDI-002-T06 (MIDI-002-R4, R5, S4): the bounded queue. Drop newest when full (counted), clock and active
// sensing counted and never stored, discard on stop, and fixed storage over 10,000 messages through the
// callback path (decode into the ring; the VIS-003 "storage addresses unchanged" pattern).
import PerformanceControl
import XCTest

final class MIDIEventRingTests: XCTestCase {
    private func cc(_ value: UInt32) -> MIDIEvent { MIDIEvent(kind: .controlChange, number: 7, value: value) }

    func testDrainsInOrderAndDropsTheNewestWhenFull() {
        let ring = MIDIEventRing(capacity: 4)
        for value in 0..<6 { ring.push(cc(UInt32(value))) }
        XCTAssertEqual(ring.availableToRead, 4)
        XCTAssertEqual(ring.dropped, 2, "the two that did not fit")
        var out: [MIDIEvent] = []
        XCTAssertEqual(ring.drain(into: &out, maxCount: 3), 3)
        XCTAssertEqual(out.map { (e: MIDIEvent) -> UInt32 in e.value }, [0, 1, 2], "oldest first; the oldest are kept")
        ring.push(cc(10))
        ring.push(cc(11))
        ring.push(cc(12))
        XCTAssertEqual(ring.dropped, 2, "room again after the drain")
        out.removeAll()
        XCTAssertEqual(ring.drain(into: &out, maxCount: 100), 4)
        XCTAssertEqual(out.map { (e: MIDIEvent) -> UInt32 in e.value }, [3, 10, 11, 12], "wraps around")
        XCTAssertEqual(ring.drain(into: &out, maxCount: 100), 0, "empty")
    }

    func testClockAndActiveSensingAreCountedNotStored() {
        let ring = MIDIEventRing(capacity: 8)
        for _ in 0..<24 { ring.push(MIDIEvent(kind: .clock)) }
        ring.push(MIDIEvent(kind: .activeSensing))
        ring.push(MIDIEvent(kind: .start))
        XCTAssertEqual(ring.clockCount, 24)
        XCTAssertEqual(ring.activeSensingCount, 1)
        XCTAssertEqual(ring.availableToRead, 1, "only the start is stored")
        XCTAssertEqual(ring.dropped, 0, "counted messages never fill the queue")
    }

    func testDiscardAllEmptiesTheQueue() {
        let ring = MIDIEventRing(capacity: 8)
        for value in 0..<5 { ring.push(cc(UInt32(value))) }
        ring.discardAll()
        XCTAssertEqual(ring.availableToRead, 0)
        ring.push(cc(9))
        var out: [MIDIEvent] = []
        ring.drain(into: &out, maxCount: 8)
        XCTAssertEqual(out, [cc(9)])
    }

    func testTenThousandMessagesThroughTheCallbackPathKeepFixedStorage() {
        let ring = MIDIEventRing()
        let address: UInt = ring.storageAddress
        XCTAssertEqual(ring.capacity, 512)
        var decoder = MIDIUMPDecoder()
        var sink: MIDIEventRing = ring
        let packet: [UInt32] = [0x20B0_0764, 0x2090_3C64, 0x10F8_0000, 0x2080_3C00]
        var drained: [MIDIEvent] = []
        drained.reserveCapacity(512)
        packet.withUnsafeBufferPointer { (words: UnsafeBufferPointer<UInt32>) -> Void in
            for round in 0..<2_500 {
                decoder.decode(words, timestamp: UInt64(round), into: &sink)
                if round % 100 == 99 {
                    drained.removeAll(keepingCapacity: true)
                    ring.drain(into: &drained, maxCount: 512)
                }
            }
        }
        XCTAssertEqual(ring.storageAddress, address, "the callback path never reallocates the queue")
        XCTAssertEqual(ring.clockCount, 2_500)
        XCTAssertEqual(ring.dropped, 0, "300 stored per 100 rounds fits 512")
        // A flood with no drain: memory stays fixed and the excess is counted.
        let flood = MIDIEventRing(capacity: 512)
        var floodSink: MIDIEventRing = flood
        packet.withUnsafeBufferPointer { (words: UnsafeBufferPointer<UInt32>) -> Void in
            for round in 0..<1_000 { decoder.decode(words, timestamp: UInt64(round), into: &floodSink) }
        }
        XCTAssertEqual(flood.availableToRead, 512)
        XCTAssertEqual(flood.dropped, 3_000 - 512)
    }
}
