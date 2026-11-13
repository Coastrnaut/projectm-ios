// LiveBandAnalyzerSubscriptionTests.swift — the SHOW-011 hook: other consumers subscribe to the
// circular spectrum's pipeline while it is the analysis tap's only reader (research SHOW-011-D3).
import AnalysisFeatures
import VisualBandFeed
import VisualGenerators
import XCTest

final class LiveBandAnalyzerSubscriptionTests: XCTestCase {
    func testExtraSubscriptionsAndSampleRate() throws {
        let analyzer = try LiveBandAnalyzer(barCount: .b32)
        XCTAssertEqual(analyzer.sampleRate, 44_100)
        let subscription = try analyzer.subscribe(eventCapacity: 8)
        XCTAssertEqual(subscription.eventCapacity, 8)
        XCTAssertFalse(subscription.isCancelled)
        analyzer.unsubscribe(subscription)
        XCTAssertTrue(subscription.isCancelled)
    }
}
