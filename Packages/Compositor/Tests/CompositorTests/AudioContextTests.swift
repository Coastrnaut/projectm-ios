// CMP-001-T04: the audio context and its preallocated buffer (CMP-001-R4; research CMP-001-D3).
// CPU only; every host.
import XCTest
import AnalysisFeatures
@testable import Compositor

/// A mailbox standing in for `AnalysisSubscription` (same two calls).
final class FakeMailbox: AnalysisMailbox {
    var frame: AnalysisFrame?
    var bands: [Float] = []
    var queued: [AnalysisEvent] = []

    func nextEvent() -> AnalysisEvent? { queued.isEmpty ? nil : queued.removeFirst() }

    func latestFrame(into destination: UnsafeMutablePointer<Float>, capacity: Int) -> AnalysisFrame? {
        guard let f = frame else { return nil }
        frame = nil
        for k in 0..<min(f.bandCount, capacity, bands.count) { destination[k] = bands[k] }
        return f
    }
}

func testTimestamp(_ sample: Int64) -> AnalysisTimestamp {
    AnalysisTimestamp(session: 1, sessionSample: sample, timelineSample: sample, hostNanoseconds: UInt64(sample) * 1000)
}

func testEvent(_ id: UInt64) -> AnalysisEvent {
    AnalysisEvent(id: id, time: testTimestamp(Int64(id)), eventSample: Int64(id), kind: .onset(strength: Float(id), threshold: 0.5))
}

func testFrame(id: UInt64, bands: Int) -> AnalysisFrame {
    AnalysisFrame(id: id, time: testTimestamp(Int64(id)), bandCount: bands, onsetFlux: 0.25, bpm: 120, beatConfidence: 0.8)
}

final class AudioContextTests: XCTestCase {
    func testEmptyContext() {
        let empty = LayerAudioContext.empty
        XCTAssertNil(empty.frame)
        XCTAssertEqual(empty.bands.count, 0)
        XCTAssertEqual(empty.events.count, 0)
        XCTAssertEqual(empty.droppedEvents, 0)
        let buffer = LayerAudioBuffer()
        XCTAssertNil(buffer.context.frame)
        XCTAssertEqual(buffer.context.bands.count, 0)
        XCTAssertEqual(buffer.context.events.count, 0)
    }

    func testSetCopiesValuesExactly() {
        let buffer = LayerAudioBuffer()
        let bands = (0..<32).map { Float($0) / 31 }
        let events = [testEvent(7), testEvent(8)]
        let frame = testFrame(id: 9, bands: 32)
        buffer.set(frame: frame, bands: bands, events: events)
        let c = buffer.context
        XCTAssertEqual(c.frame, frame)
        XCTAssertEqual(Array(c.bands), bands)
        XCTAssertEqual(Array(c.events), events)
        XCTAssertEqual(c.droppedEvents, 0)
    }

    func testBandsAreBoundedAt128() {
        let buffer = LayerAudioBuffer()
        buffer.set(frame: testFrame(id: 1, bands: 128), bands: [Float](repeating: 0.5, count: 200), events: [])
        XCTAssertEqual(buffer.context.bands.count, LayerAudioBuffer.bandCapacity)
        XCTAssertEqual(LayerAudioBuffer.bandCapacity, 128)
    }

    func testEventOverflowKeepsTheNewest64OldestFirst() {
        let buffer = LayerAudioBuffer()
        buffer.set(frame: nil, bands: [], events: (1...70).map { testEvent(UInt64($0)) })
        let c = buffer.context
        XCTAssertEqual(LayerAudioBuffer.eventCapacity, 64)
        XCTAssertEqual(c.events.map(\.id), (7...70).map { UInt64($0) })
        XCTAssertEqual(c.droppedEvents, 6)
    }

    func testUpdateFromMailboxDeliversLatestFrameAndEventsSinceThePreviousFrame() {
        let buffer = LayerAudioBuffer()
        let mailbox = FakeMailbox()
        mailbox.frame = testFrame(id: 3, bands: 16)
        mailbox.bands = (0..<16).map { Float($0) / 15 }
        mailbox.queued = (1...70).map { testEvent(UInt64($0)) }
        buffer.update(from: mailbox)
        var c = buffer.context
        XCTAssertEqual(c.frame?.id, 3)
        XCTAssertEqual(Array(c.bands), mailbox.bands)
        XCTAssertEqual(c.events.map(\.id), (7...70).map { UInt64($0) })
        XCTAssertEqual(c.droppedEvents, 6)
        XCTAssertTrue(mailbox.queued.isEmpty)

        // The next frame: no new frame (the last one stays), no new events.
        buffer.update(from: mailbox)
        c = buffer.context
        XCTAssertEqual(c.frame?.id, 3, "the latest frame is kept when no new one arrived")
        XCTAssertEqual(c.bands.count, 16)
        XCTAssertEqual(c.events.count, 0)
        XCTAssertEqual(c.droppedEvents, 0)

        mailbox.queued = [testEvent(71)]
        buffer.update(from: mailbox)
        XCTAssertEqual(buffer.context.events.map(\.id), [71])
    }

    func testClearForgetsEverything() {
        let buffer = LayerAudioBuffer()
        buffer.set(frame: testFrame(id: 1, bands: 4), bands: [1, 2, 3, 4], events: [testEvent(1)])
        buffer.clear()
        XCTAssertNil(buffer.context.frame)
        XCTAssertEqual(buffer.context.bands.count, 0)
        XCTAssertEqual(buffer.context.events.count, 0)
    }
}
