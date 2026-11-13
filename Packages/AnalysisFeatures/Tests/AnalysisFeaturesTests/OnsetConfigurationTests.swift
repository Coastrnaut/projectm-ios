// OnsetConfigurationTests.swift — defaults, validation and derived values of the onset detector's
// configuration, and the event's seconds (ANL-004-T03; ANL-004-R9, R13; data-model.md).
import XCTest
@testable import AnalysisFeatures

final class OnsetConfigurationTests: XCTestCase {
    func testDefaults() throws {
        let c = try OnsetDetectorConfiguration()
        XCTAssertEqual(c.sampleRate, 44_100)
        XCTAssertEqual(c.bandCount, .b64)
        XCTAssertEqual(c.floorDecibels, -70)
        XCTAssertEqual(c.thresholdOffset, 0.06)
        XCTAssertEqual(c.thresholdMultiplier, 1.5)
        XCTAssertEqual(c.thresholdWindowSeconds, 0.1)
        XCTAssertEqual(c.minimumInterOnsetSeconds, 0.05)
        XCTAssertEqual(OnsetDetectorConfiguration.standard, c)
        XCTAssertEqual(OnsetDetectorConfiguration.maximumHistoryFrames, 128)
    }

    private func rejects(_ expected: OnsetDetectorConfigurationError,
                         _ make: () throws(OnsetDetectorConfigurationError) -> OnsetDetectorConfiguration,
                         file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try make()
            XCTFail("accepted, expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    func testEveryFieldIsValidated() throws {
        for rate in [7_999.0, 0, -1, .nan, .infinity] {
            rejects(.invalidSampleRate(rate)) { () throws(OnsetDetectorConfigurationError) in try OnsetDetectorConfiguration(sampleRate: rate) }
        }
        XCTAssertNoThrow(try OnsetDetectorConfiguration(sampleRate: 8_000))
        for floor: Float in [-120.5, -19.5, .nan, -.infinity] {
            rejects(.invalidFloor(floor)) { () throws(OnsetDetectorConfigurationError) in try OnsetDetectorConfiguration(floorDecibels: floor) }
        }
        XCTAssertNoThrow(try OnsetDetectorConfiguration(floorDecibels: -120))
        XCTAssertNoThrow(try OnsetDetectorConfiguration(floorDecibels: -20))
        for offset: Float in [0, 1, -0.1, .nan, .infinity] {
            rejects(.invalidThresholdOffset(offset)) { () throws(OnsetDetectorConfigurationError) in try OnsetDetectorConfiguration(thresholdOffset: offset) }
        }
        for multiplier: Float in [-0.01, 10.01, .nan] {
            rejects(.invalidThresholdMultiplier(multiplier)) { () throws(OnsetDetectorConfigurationError) in try OnsetDetectorConfiguration(thresholdMultiplier: multiplier) }
        }
        XCTAssertNoThrow(try OnsetDetectorConfiguration(thresholdMultiplier: 0))
        XCTAssertNoThrow(try OnsetDetectorConfiguration(thresholdMultiplier: 10))
        for window in [0, 2.01, -1, .nan, .infinity] {
            rejects(.invalidThresholdWindow(window)) { () throws(OnsetDetectorConfigurationError) in try OnsetDetectorConfiguration(thresholdWindowSeconds: window) }
        }
        XCTAssertNoThrow(try OnsetDetectorConfiguration(thresholdWindowSeconds: 2))
        for interval in [-0.001, 2.001, .nan, .infinity] {
            rejects(.invalidMinimumInterOnsetInterval(interval)) { () throws(OnsetDetectorConfigurationError) in try OnsetDetectorConfiguration(minimumInterOnsetSeconds: interval) }
        }
        XCTAssertNoThrow(try OnsetDetectorConfiguration(minimumInterOnsetSeconds: 0))
    }

    func testDerivedFrameAndSampleCounts() throws {
        let c44 = try OnsetDetectorConfiguration()
        XCTAssertEqual(c44.historyFrames(hop: 1_024), 4)        // 4.31
        XCTAssertEqual(c44.historyFrames(hop: 8_192), 1)        // 0.54 → at least 1
        XCTAssertEqual(c44.historyFrames(hop: 16), 128)         // 275.6 → capped
        XCTAssertEqual(c44.minimumInterOnsetSamples, 2_205)
        let c48 = try OnsetDetectorConfiguration(sampleRate: 48_000)
        XCTAssertEqual(c48.historyFrames(hop: 64), 75)
        XCTAssertEqual(c48.minimumInterOnsetSamples, 2_400)
    }

    func testEventSeconds() {
        let event = OnsetEvent(sequence: 1, sampleIndex: 24_000, frameIndex: 22_464, strength: 0.5,
                               threshold: 0.06, sampleRate: 48_000, timestampNanoseconds: 0)
        XCTAssertEqual(event.seconds, 0.5)
    }
}
