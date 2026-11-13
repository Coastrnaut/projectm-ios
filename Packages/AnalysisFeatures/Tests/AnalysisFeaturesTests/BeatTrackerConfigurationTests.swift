// BeatTrackerConfigurationTests.swift — ANL-005-T02: defaults and validation of the beat tracker
// configuration (ANL-005-R14; data-model.md). Fast: no audio.
import XCTest
@testable import AnalysisFeatures

final class BeatTrackerConfigurationTests: XCTestCase {
    func testDefaultsAndStandard() throws {
        let c = try BeatTrackerConfiguration()
        XCTAssertEqual(c, BeatTrackerConfiguration.standard)
        XCTAssertEqual(c.sampleRate, 44_100)
        XCTAssertEqual(c.minimumBPM, 60)
        XCTAssertEqual(c.maximumBPM, 200)
        XCTAssertEqual(c.preferredBPM, 120)
        XCTAssertEqual(c.windowSeconds, 6)
        XCTAssertEqual(c.timingToleranceSeconds, 0.035)
        XCTAssertEqual(c.silenceTimeoutSeconds, 4)
        XCTAssertEqual(BeatTrackerConfiguration.maximumOnsets, 64)
        XCTAssertEqual(BeatTrackerConfiguration.gridStepBPM, 0.25)
        XCTAssertEqual(AdaptiveBeatTracker.highConfidence, 0.5)
        let event = BeatEvent(sequence: 1, sampleIndex: 22_050, bpm: 120, periodSamples: 22_050, confidence: 1,
                              sampleRate: 44_100)
        XCTAssertEqual(event.seconds, 0.5)
    }

    func testEachRuleRejectsWithItsNamedError() {
        func rejects(_ expected: BeatTrackerConfigurationError, _ make: () throws -> BeatTrackerConfiguration,
                     line: UInt = #line) {
            do { _ = try make(); XCTFail("accepted", line: line) } catch {
                XCTAssertEqual(error as? BeatTrackerConfigurationError, expected, line: line)
            }
        }
        rejects(.invalidSampleRate(7_999)) { try BeatTrackerConfiguration(sampleRate: 7_999) }
        rejects(.invalidSampleRate(.nan)) { try BeatTrackerConfiguration(sampleRate: .nan) }
        rejects(.invalidSampleRate(.infinity)) { try BeatTrackerConfiguration(sampleRate: .infinity) }
        rejects(.invalidTempoRange(29, 200)) { try BeatTrackerConfiguration(minimumBPM: 29) }
        rejects(.invalidTempoRange(60, 301)) { try BeatTrackerConfiguration(maximumBPM: 301) }
        rejects(.invalidTempoRange(100, 149)) { try BeatTrackerConfiguration(minimumBPM: 100, maximumBPM: 149, preferredBPM: 120) }
        rejects(.invalidTempoRange(.nan, 200)) { try BeatTrackerConfiguration(minimumBPM: .nan) }
        rejects(.invalidPreferredTempo(59)) { try BeatTrackerConfiguration(preferredBPM: 59) }
        rejects(.invalidPreferredTempo(201)) { try BeatTrackerConfiguration(preferredBPM: 201) }
        rejects(.invalidWindow(1.99)) { try BeatTrackerConfiguration(windowSeconds: 1.99) }
        rejects(.invalidWindow(16.01)) { try BeatTrackerConfiguration(windowSeconds: 16.01) }
        rejects(.invalidTimingTolerance(0.004)) { try BeatTrackerConfiguration(timingToleranceSeconds: 0.004) }
        rejects(.invalidTimingTolerance(0.101)) { try BeatTrackerConfiguration(timingToleranceSeconds: 0.101) }
        rejects(.invalidSilenceTimeout(0.99)) { try BeatTrackerConfiguration(silenceTimeoutSeconds: 0.99) }
        rejects(.invalidSilenceTimeout(16.01)) { try BeatTrackerConfiguration(silenceTimeoutSeconds: 16.01) }
        // 1.5 periods of 30 BPM = 3 s: a 2 s timeout is too short for that range.
        rejects(.invalidSilenceTimeout(2)) { try BeatTrackerConfiguration(minimumBPM: 30, preferredBPM: 60, silenceTimeoutSeconds: 2) }

        // The edges themselves are valid.
        XCTAssertNoThrow(try BeatTrackerConfiguration(sampleRate: 8_000, minimumBPM: 30, maximumBPM: 300, preferredBPM: 30,
                                                      windowSeconds: 2, timingToleranceSeconds: 0.005,
                                                      silenceTimeoutSeconds: 16))
        XCTAssertNoThrow(try BeatTrackerConfiguration(minimumBPM: 100, maximumBPM: 150, preferredBPM: 150,
                                                      windowSeconds: 16, timingToleranceSeconds: 0.1,
                                                      silenceTimeoutSeconds: 1))
    }
}
