// PRE-009-T03: the comparison's shared timeline and mailbox (research PRE-009-D3, D4; data-model.md). Pure.
import XCTest
@testable import Rendering

final class PresetComparisonTimelineTests: XCTestCase {
    private func block(_ frames: Int, _ value: Float) -> [Float] { [Float](repeating: value, count: frames * 2) }

    func testTicksHaveContiguousIndexesSampleRangesAndFrameTimes() {
        var timeline = PresetComparisonTimeline(rate: 30)
        let first = timeline.stamp(block(1_470, 0.1))
        let second = timeline.stamp(block(1_000, 0.2))
        let third = timeline.stamp(block(0, 0))
        XCTAssertEqual([first.index, second.index, third.index], [0, 1, 2])
        XCTAssertEqual([first.firstSample, second.firstSample, third.firstSample], [0, 1_470, 2_470])
        XCTAssertEqual(second.frameTime, 1.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(third.frameTime, 2.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(timeline.nextSample, 2_470)
        // An odd count (half a stereo frame) loses its last value, so ranges stay whole frames.
        let odd = timeline.stamp([0.5, 0.5, 0.5])
        XCTAssertEqual(odd.frameCount, 1)
        XCTAssertEqual(timeline.nextSample, 2_471)
    }

    func testTakeJoinsWaitingTicksInOrderWithTheLastFrameTime() {
        var timeline = PresetComparisonTimeline(rate: 30)
        let mailbox = PresetComparisonMailbox()
        XCTAssertNil(mailbox.take())
        for value in [Float(1), 2, 3] { mailbox.post(timeline.stamp(block(2, value))) }
        let batch = try! XCTUnwrap(mailbox.take())
        XCTAssertEqual(batch.firstTick, 0)
        XCTAssertEqual(batch.lastTick, 2)
        XCTAssertEqual(batch.frameTime, 2.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(batch.firstSample, 0)
        XCTAssertEqual(batch.samples, block(2, 1) + block(2, 2) + block(2, 3))
        XCTAssertEqual(batch.droppedTicks, 0)
        XCTAssertTrue(mailbox.isEmpty)
        XCTAssertNil(mailbox.take())
    }

    func testAboveCapacityTheOldestTicksAreDroppedAndCounted() {
        var timeline = PresetComparisonTimeline(rate: 30)
        let mailbox = PresetComparisonMailbox(capacity: 6)
        for index in 0..<9 { mailbox.post(timeline.stamp(block(10, Float(index)))) }
        let batch = try! XCTUnwrap(mailbox.take())
        XCTAssertEqual(batch.firstTick, 3)
        XCTAssertEqual(batch.lastTick, 8)
        XCTAssertEqual(batch.firstSample, 30)
        XCTAssertEqual(batch.frameCount, 60)
        XCTAssertEqual(batch.droppedTicks, 3)
        XCTAssertEqual(mailbox.totalDropped, 3)
        mailbox.post(timeline.stamp(block(10, 9)))
        XCTAssertEqual(mailbox.take()?.droppedTicks, 0, "the count restarts with each batch")
    }

    func testADeliveryDescribesItsBatchAndTheChecksumSeesEverySample() {
        var timeline = PresetComparisonTimeline(rate: 15)
        let mailbox = PresetComparisonMailbox()
        mailbox.post(timeline.stamp([0.25, -0.25, 0.5, -0.5]))
        let delivery = PresetComparisonDelivery(try! XCTUnwrap(mailbox.take()))
        XCTAssertEqual(delivery.frameCount, 2)
        XCTAssertEqual(delivery.firstSample, 0)
        XCTAssertEqual(delivery.frameTime, 0)
        XCTAssertNotEqual(PresetComparisonDelivery.checksum([0.25, -0.25, 0.5, -0.5]), PresetComparisonDelivery.checksum([0.25, -0.25, 0.5, 0.5]))
        XCTAssertNotEqual(PresetComparisonDelivery.checksum([1, 2]), PresetComparisonDelivery.checksum([2, 1]))
    }

    func testTheRecorderKeepsEachSideApart() {
        let recorder = PresetComparisonRecorder()
        var timeline = PresetComparisonTimeline(rate: 30)
        let mailbox = PresetComparisonMailbox()
        mailbox.post(timeline.stamp(block(1, 1)))
        let delivery = PresetComparisonDelivery(try! XCTUnwrap(mailbox.take()))
        recorder.record(delivery, side: .a)
        XCTAssertEqual(recorder.deliveries(.a), [delivery])
        XCTAssertEqual(recorder.deliveries(.b), [])
    }
}
