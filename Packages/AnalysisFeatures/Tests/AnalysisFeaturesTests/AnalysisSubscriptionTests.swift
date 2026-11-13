// AnalysisSubscriptionTests.swift — ANL-016-T04: a subscription's latest-wins frame slot and
// bounded drop-oldest event queue, the subscriber limit and configuration validation
// (ANL-016-R10 to R12). No audio; each test runs in milliseconds.
import XCTest
@testable import AnalysisFeatures

final class AnalysisSubscriptionTests: XCTestCase {
    private func time(_ sample: Int64) -> AnalysisTimestamp {
        AnalysisTimestamp(session: 1, sessionSample: sample, timelineSample: sample, hostNanoseconds: UInt64(sample))
    }

    private func event(_ id: UInt64) -> AnalysisEvent {
        AnalysisEvent(id: id, time: time(Int64(id)), eventSample: Int64(id), kind: .onset(strength: 0.5, threshold: 0.1))
    }

    func testEventCapacityIsValidated() {
        XCTAssertThrowsError(try AnalysisSubscription(eventCapacity: 0)) { XCTAssertEqual($0 as? AnalysisBusError, .invalidEventCapacity(0)) }
        XCTAssertThrowsError(try AnalysisSubscription(eventCapacity: 1_025)) { XCTAssertEqual($0 as? AnalysisBusError, .invalidEventCapacity(1_025)) }
        XCTAssertNoThrow(try AnalysisSubscription(eventCapacity: 1))
        XCTAssertNoThrow(try AnalysisSubscription(eventCapacity: 1_024))
        XCTAssertEqual(AnalysisSubscription.defaultEventCapacity, 64)
    }

    func testFullQueueDropsTheOldestAndCounts() throws {
        let subscription = try AnalysisSubscription(eventCapacity: 4)
        for id in 1...10 { subscription.publish(event(UInt64(id))) }
        XCTAssertEqual(subscription.droppedEvents, 6)
        XCTAssertEqual(subscription.drainEvents().map(\.id), [7, 8, 9, 10])
        XCTAssertNil(subscription.nextEvent())
        subscription.publish(event(11))
        XCTAssertEqual(subscription.nextEvent()?.id, 11)
    }

    func testFrameSlotIsLatestWins() throws {
        let subscription = try AnalysisSubscription(eventCapacity: 4)
        var bands = [Float](repeating: 0, count: 128)
        XCTAssertNil(bands.withUnsafeMutableBufferPointer { subscription.latestFrame(into: $0.baseAddress!, capacity: 128) })
        for id in 1...3 {
            let values = [Float](repeating: Float(id), count: 32)
            let frame = AnalysisFrame(id: UInt64(id), time: time(Int64(id) * 512), bandCount: 32, onsetFlux: 0, bpm: nil, beatConfidence: 0)
            values.withUnsafeBufferPointer { subscription.publish(frame, bands: $0) }
        }
        let read = bands.withUnsafeMutableBufferPointer { subscription.latestFrame(into: $0.baseAddress!, capacity: 16) }
        XCTAssertEqual(read?.id, 3)
        XCTAssertEqual(read?.bandCount, 32)
        XCTAssertEqual(Array(bands[0..<16]), [Float](repeating: 3, count: 16), "copies at most the caller's capacity")
        XCTAssertEqual(bands[16], 0)
        XCTAssertEqual(subscription.overwrittenFrames, 2)
        XCTAssertNil(bands.withUnsafeMutableBufferPointer { subscription.latestFrame(into: $0.baseAddress!, capacity: 128) }, "nothing new")
        let frame = AnalysisFrame(id: 4, time: time(4 * 512), bandCount: 32, onsetFlux: 0, bpm: nil, beatConfidence: 0)
        [Float](repeating: 4, count: 32).withUnsafeBufferPointer { subscription.publish(frame, bands: $0) }
        subscription.clearFrame()
        XCTAssertNil(bands.withUnsafeMutableBufferPointer { subscription.latestFrame(into: $0.baseAddress!, capacity: 128) }, "cleared at a session start")
    }

    func testCancelEmptiesAndStopsDelivery() throws {
        let subscription = try AnalysisSubscription(eventCapacity: 4)
        subscription.publish(event(1))
        subscription.cancel()
        subscription.publish(event(2))
        XCTAssertTrue(subscription.isCancelled)
        XCTAssertNil(subscription.nextEvent())
    }

    func testSubscriberLimit() throws {
        let pipeline = AnalysisPipeline()
        var subscriptions: [AnalysisSubscription] = []
        for _ in 0..<AnalysisPipeline.maximumSubscribers { subscriptions.append(try pipeline.subscribe()) }
        XCTAssertEqual(AnalysisPipeline.maximumSubscribers, 16)
        XCTAssertThrowsError(try pipeline.subscribe()) { XCTAssertEqual($0 as? AnalysisBusError, .tooManySubscribers) }
        pipeline.unsubscribe(subscriptions[0])
        XCTAssertNoThrow(try pipeline.subscribe(), "a free slot after unsubscribe")
    }

    func testConfigurationRejectsMismatchedRates() throws {
        XCTAssertNoThrow(try AnalysisPipelineConfiguration())
        let spectrum = try SpectrumConfiguration(size: .n2048, hop: 512, sampleRate: 48_000)
        XCTAssertThrowsError(try AnalysisPipelineConfiguration(spectrum: spectrum)) { XCTAssertEqual($0 as? AnalysisBusError, .sampleRateMismatch) }
        let standard = AnalysisPipelineConfiguration.standard
        XCTAssertEqual(standard.spectrum.size, .n2048)
        XCTAssertEqual(standard.spectrum.hop, 512)
        XCTAssertEqual(standard.bandCount, .b64)
        XCTAssertEqual(standard.bandFloorDecibels, -80)
    }
}
