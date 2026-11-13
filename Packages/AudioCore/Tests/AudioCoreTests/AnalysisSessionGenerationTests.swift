// AnalysisSessionGenerationTests.swift — ANL-016-T02: the normalized ring's session generation, the
// capture-restart signal the analysis event bus reads through the tap (ANL-016-R9; research
// ANL-016-D1).
import XCTest
@testable import AudioCore

final class AnalysisSessionGenerationTests: XCTestCase {
    private func write(_ ring: NormalizedPCMRing, frames: Int) {
        let data = [Float](repeating: 0.25, count: frames * 2)
        data.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: frames) }
    }

    func testResetIncreasesTheGenerationAfterEmptyingTheTap() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 1_000)
        let tap = try XCTUnwrap(ring.analysisTap as? any AnalysisSessionReporting)
        XCTAssertEqual(ring.analysisSessionGeneration, 0)
        XCTAssertEqual(tap.analysisSessionGeneration, 0)
        write(ring, frames: 100)
        ring.reset()
        XCTAssertEqual(ring.analysisSessionGeneration, 1)
        XCTAssertEqual(tap.analysisSessionGeneration, 1)
        XCTAssertEqual(ring.analysisTapAvailableFrames, 0, "the tap is empty once the new generation is visible")
        ring.reset()
        XCTAssertEqual(tap.analysisSessionGeneration, 2)
    }

    func testDiscardBufferedIsNotANewSession() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 1_000)
        write(ring, frames: 100)
        ring.discardBuffered()
        XCTAssertEqual(ring.analysisSessionGeneration, 0)
        XCTAssertEqual(ring.analysisTapAvailableFrames, 0)
    }

    func testRingWithoutTapStillCounts() {
        let ring = NormalizedPCMRing()
        ring.reset()
        XCTAssertEqual(ring.analysisSessionGeneration, 1)
        XCTAssertNil(ring.analysisTap)
    }
}
