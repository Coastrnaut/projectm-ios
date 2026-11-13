// FlashAnalysisTests.swift — FX-019-T03: the independent measurement (FX-019-R1, R2) and the WCAG
// color helpers (FX-019-R3) on hand-made inputs with known answers.
import XCTest
@testable import FlashSafety

final class FlashAnalysisTests: XCTestCase {
    private func times(_ n: Int, _ dt: Double) -> [Double] { [Double](repeating: dt, count: n) }

    func testHysteresisCountsOnlyChangesOfAtLeastTheThreshold() {
        let small = FlashAnalysis.analyze([0, 0.09, 0, 0.09, 0], frameTimes: times(5, 0.1), threshold: 0.1)
        XCTAssertEqual(small.transitions, 0, "sub-threshold changes are not transitions")
        let pair = FlashAnalysis.analyze([0, 0.1, 0], frameTimes: times(3, 0.1), threshold: 0.1)
        XCTAssertEqual(pair.transitions, 2, "a change of exactly 0.10 counts (10 % or more)")
        XCTAssertEqual(pair.maxFlashesPerWindow, 1)
        let ramp = FlashAnalysis.analyze((0...20).map { Double($0) / 20 }, frameTimes: times(21, 0.1), threshold: 0.1)
        XCTAssertEqual(ramp.transitions, 1, "a slow ramp is one leg")
        XCTAssertEqual(ramp.maxRise, 0.05, accuracy: 1e-12)
        XCTAssertEqual(ramp.maxFall, 0)
    }

    func testWindowIsHalfOpenOneSecond() {
        // Frames every 0.15 s; a rise at frame 1 and a fall at frame 8 are 1.05 s apart → never in
        // one window. (The exact 1 s boundary is not tested: both sides count it, conservatively.)
        let apart = FlashAnalysis.analyze([0, 1, 1, 1, 1, 1, 1, 1, 0], frameTimes: times(9, 0.15), threshold: 0.1)
        XCTAssertEqual(apart.transitions, 2)
        XCTAssertEqual(apart.maxTransitionsPerWindow, 1)
        // A fall at frame 7 is 0.9 s after the rise → one window holds both.
        let close = FlashAnalysis.analyze([0, 1, 1, 1, 1, 1, 1, 0], frameTimes: times(8, 0.15), threshold: 0.1)
        XCTAssertEqual(close.maxTransitionsPerWindow, 2)
    }

    func testFlashesRoundUp() {
        let three = FlashAnalysis.analyze([0, 1, 0, 1], frameTimes: times(4, 1.0 / 60), threshold: 0.1)
        XCTAssertEqual(three.transitions, 3)
        XCTAssertEqual(three.maxFlashesPerWindow, 2, "a lone transition counts as a flash")
    }

    func testNonFiniteValuesReadAsDark() {
        let r = FlashAnalysis.analyze([1, .nan, 1], frameTimes: times(3, 0.1), threshold: 0.1)
        XCTAssertEqual(r.transitions, 2)
    }

    func testWCAGColor() {
        XCTAssertEqual(FlashColor.decodeSRGB(0), 0)
        XCTAssertEqual(FlashColor.decodeSRGB(0.04045), 0.04045 / 12.92, accuracy: 1e-12)
        XCTAssertEqual(FlashColor.decodeSRGB(0.5), 0.21404, accuracy: 1e-5)
        XCTAssertEqual(FlashColor.decodeSRGB(1), 1, accuracy: 1e-12)
        XCTAssertEqual(FlashColor.encodeSRGB(FlashColor.decodeSRGB(0.7)), 0.7, accuracy: 1e-9)
        XCTAssertEqual(FlashColor.relativeLuminance(red: 1, green: 1, blue: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(FlashColor.relativeLuminance(red: 1, green: 0, blue: 0), 0.2126, accuracy: 1e-12)
        XCTAssertEqual(FlashColor.redness(red: 1, green: 0, blue: 0), 1)
        XCTAssertEqual(FlashColor.redness(red: 1, green: 1, blue: 1), 0)
        XCTAssertEqual(FlashColor.redness(red: 1, green: 0, blue: 1), 0)
    }

    func testTileLevelsOfAnImage() {
        // 8 × 8 RGBA8, top row first; the top-left 2 × 2 tile is white, the rest black.
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for y in 0..<2 { for x in 0..<2 { for c in 0..<3 { pixels[(y * 8 + x) * 4 + c] = 255 } } }
        let top = FlashColor.tileLevels(rgba: pixels, width: 8, height: 8, bottomRowFirst: false)
        XCTAssertEqual(top.count, FlashZones.count)
        XCTAssertEqual(top[0].luminance, 1, accuracy: 1e-12)
        XCTAssertEqual(top[1].luminance, 0)
        XCTAssertEqual(top[FlashZones.wholeFrame].luminance, 1.0 / 16, accuracy: 1e-12)
        let bottom = FlashColor.tileLevels(rgba: pixels, width: 8, height: 8, bottomRowFirst: true)
        XCTAssertEqual(bottom[12].luminance, 1, accuracy: 1e-12, "read-back rows start at the bottom")
    }
}
