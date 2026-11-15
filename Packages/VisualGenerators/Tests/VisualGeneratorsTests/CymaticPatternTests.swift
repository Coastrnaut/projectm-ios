// CymaticPatternTests.swift — VIS-019-T04 on the CPU mirror (VIS-019-R2 to R7, R9; S1, S2, S4): the nine modes' nodal
// masks differ pairwise; a lit band in each part settles to that part's mode; pure tones through the real ANL-002 reducer
// (AUD-016 sines → SpectrumBandFeed) settle to different modes whose masks differ in ≥ 50% of their combined line pixels, the same tone
// twice gives the same state; ties, hysteresis and band ranges; silence reaches the exact rest state within the settle
// time (not before the slews allow); Reduce Motion halves blends and widening; time backwards and gaps are bounded; extreme
// inputs stay finite. Injected clocks only. Pure Swift (Linux too).
import AnalysisFeatures
import AudioCore
import XCTest
@testable import VisualBandFeed
@testable import VisualGenerators

enum CymaticFixture {
    static let width = 96
    static let height = 72

    /// The nodal mask of `weights` on a `width × height` grid (pixel centres), rows top first.
    static func mask(_ weights: SIMD16<Float>, width: Int = width, height: Int = height) -> [Bool] {
        var out: [Bool] = []
        out.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let q = CymaticField.plate(pixel: SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5), width: width, height: height)
                out.append(CymaticField.onMask(CymaticField.blended(at: q, weights: weights)))
            }
        }
        return out
    }

    /// The share of the two masks' combined line pixels where they differ: |A △ B| / |A ∪ B| (VIS-019 Clarifications Q2).
    static func difference(_ a: [Bool], _ b: [Bool]) -> Double {
        let differing: Int = zip(a, b).filter { (p: (Bool, Bool)) -> Bool in p.0 != p.1 }.count
        let union: Int = zip(a, b).filter { (p: (Bool, Bool)) -> Bool in p.0 || p.1 }.count
        return Double(differing) / Double(max(union, 1))
    }

    static let threshold = 0.5

    static func nanoseconds(_ frame: Int) -> UInt64 { UInt64(frame) * 1_000_000_000 / 60 }

    /// Advances `drive` through `frames` 60 Hz frames of `bands` starting at frame `start`; returns the next frame index.
    @discardableResult
    static func run(_ drive: inout CymaticDrive, bands: [Float], range: CymaticBandRange = .all, from start: Int = 0, frames: Int,
                    reduceMotion: Bool = false) -> Int {
        for f in start..<(start + frames) {
            bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
                drive.advance(bands: b, range: range, timeNanoseconds: nanoseconds(f), reduceMotion: reduceMotion)
            }
        }
        return start + frames
    }

    /// 64 bands, `level` at index `i`, 0 elsewhere.
    static func lit(_ i: Int, level: Float = 0.8, count: Int = 64) -> [Float] {
        var b = [Float](repeating: 0, count: count)
        b[i] = level
        return b
    }

    /// The 64 ANL-002 bands of one second of an AUD-016 sine at `frequency` (the real reducer).
    static func toneBands(_ frequency: Double) throws -> [Float] {
        let feed = try SpectrumBandFeed(barCount: .b64)
        XCTAssertTrue(feed.pull(from: ArrayPCMReader(try BandFeedFixture.sine(frequency))))
        return Array(feed.bands)
    }
}

final class CymaticPatternTests: XCTestCase {
    func testTheModesNodalMasksDifferPairwise() {
        let masks: [[Bool]] = (0..<CymaticField.modeCount).map { (k: Int) -> [Bool] in CymaticFixture.mask(CymaticField.one(k)) }
        var smallest = 1.0
        for a in 0..<masks.count {
            XCTAssertGreaterThan(masks[a].filter { $0 }.count, 100, "mode \(a) draws lines")
            for b in (a + 1)..<masks.count {
                let d = CymaticFixture.difference(masks[a], masks[b])
                smallest = min(smallest, d)
                XCTAssertGreaterThanOrEqual(d, CymaticFixture.threshold, "modes \(a) and \(b)")
            }
        }
        print("VIS-019 nodal masks: smallest pairwise difference \(String(format: "%.1f", smallest * 100))% of the combined line pixels (96 × 72)")
    }

    func testALitBandInEachPartSettlesToThatPartsMode() {
        for part in 0..<CymaticField.drivenCount {
            var drive = CymaticDrive()
            CymaticFixture.run(&drive, bands: CymaticFixture.lit(part * 8 + 3), frames: 61)
            XCTAssertEqual(drive.target, part + 1)
            XCTAssertEqual(drive.weights, CymaticField.one(part + 1), "part \(part) settled")
            XCTAssertEqual(drive.amplitude, 0.8)
            XCTAssertEqual(drive.frame.brightness, 0.35 + 0.45 * 0.8, accuracy: 1e-6)
        }
    }

    /// The acceptance on the CPU: two pure tones through ANL-002 settle to different figures; the same tone repeats exactly.
    func testPureTonesThroughANL002ChangeTheNodalPattern() throws {
        let low = try CymaticFixture.toneBands(100)
        let high = try CymaticFixture.toneBands(1_000)
        var a = CymaticDrive(), b = CymaticDrive(), again = CymaticDrive()
        CymaticFixture.run(&a, bands: low, frames: 61)
        CymaticFixture.run(&b, bands: high, frames: 61)
        CymaticFixture.run(&again, bands: try CymaticFixture.toneBands(100), frames: 61)
        XCTAssertNotEqual(a.target, CymaticField.restIndex)
        XCTAssertNotEqual(b.target, CymaticField.restIndex)
        XCTAssertNotEqual(a.target, b.target, "different parts, different modes")
        XCTAssertEqual(a.weights, CymaticField.one(a.target))
        XCTAssertEqual(b.weights, CymaticField.one(b.target))
        XCTAssertEqual(a, again, "the same tone gives the same state")
        let d = CymaticFixture.difference(CymaticFixture.mask(a.weights), CymaticFixture.mask(b.weights))
        XCTAssertGreaterThanOrEqual(d, CymaticFixture.threshold)
        let rest = CymaticFixture.difference(CymaticFixture.mask(a.weights), CymaticFixture.mask(CymaticField.restWeights))
        XCTAssertGreaterThanOrEqual(rest, CymaticFixture.threshold, "a tone moves the figure off the rest cross")
        print("VIS-019 pure tones (ANL-002, 64 bands): 100 Hz → mode \(a.target), 1 kHz → mode \(b.target); masks differ in \(String(format: "%.1f", d * 100))% of their line pixels, 100 Hz vs rest \(String(format: "%.1f", rest * 100))%")
    }

    func testTiesPickTheLowestBandAndHysteresisHoldsTheFigure() {
        var tie = [Float](repeating: 0, count: 64)
        tie[3] = 0.5; tie[45] = 0.5
        var drive = CymaticDrive()
        CymaticFixture.run(&drive, bands: tie, frames: 2)
        XCTAssertEqual(drive.target, 1, "the lowest band wins a tie")
        var close = tie
        close[45] = 0.6   // < 1.25 × 0.5
        CymaticFixture.run(&drive, bands: close, from: 2, frames: 2)
        XCTAssertEqual(drive.target, 1, "not clearly louder: kept")
        close[45] = 0.7
        CymaticFixture.run(&drive, bands: close, from: 4, frames: 2)
        XCTAssertEqual(drive.target, 6, "clearly louder: switched")
    }

    func testTheRangeSelectsWhichBandsDrive() {
        var drive = CymaticDrive()
        CymaticFixture.run(&drive, bands: CymaticFixture.lit(50), range: .low, frames: 61)
        XCTAssertTrue(drive.isAtRest, "a high tone is silence for Low")
        CymaticFixture.run(&drive, bands: CymaticFixture.lit(20), range: .low, from: 61, frames: 61)
        XCTAssertEqual(drive.target, 20 * 8 / 21 + 1, "band 20 of Low's 21")
        XCTAssertEqual(CymaticBandRange.low.indices(count: 64), 0..<21)
        XCTAssertEqual(CymaticBandRange.mid.indices(count: 64), 21..<42)
        XCTAssertEqual(CymaticBandRange.high.indices(count: 64), 42..<64)
        XCTAssertEqual(CymaticBandRange.all.indices(count: 16), 0..<16)
        XCTAssertEqual(CymaticBandRange(rawValue: "everything"), nil)
    }

    /// The acceptance's second half on the CPU: exact rest within 1 s (2 s with Reduce Motion), and not earlier than the slews.
    func testSilenceSettlesExactlyToRestWithinTheSettleTime() {
        let silence = [Float](repeating: 0, count: 64)
        for reduceMotion in [false, true] {
            var drive = CymaticDrive()
            var f = CymaticFixture.run(&drive, bands: CymaticFixture.lit(62, level: 1), frames: 120, reduceMotion: reduceMotion)
            XCTAssertEqual(drive.target, 8)
            XCTAssertEqual(drive.amplitude, 1)
            let settle = CymaticDrive.settleSeconds(reduceMotion: reduceMotion)
            let early = Int(settle * 0.4 * 60)   // 40% of the settle time: still blending
            f = CymaticFixture.run(&drive, bands: silence, from: f, frames: early, reduceMotion: reduceMotion)
            XCTAssertFalse(drive.isAtRest, "Reduce Motion \(reduceMotion): blending at \(early) frames")
            CymaticFixture.run(&drive, bands: silence, from: f, frames: Int(settle * 60) - early, reduceMotion: reduceMotion)
            XCTAssertTrue(drive.isAtRest, "Reduce Motion \(reduceMotion): at rest after \(settle) s")
            XCTAssertEqual(drive.frame, CymaticFrame.rest)
            XCTAssertEqual(drive.target, CymaticField.restIndex)
        }
        var below = CymaticDrive()
        CymaticFixture.run(&below, bands: [Float](repeating: CymaticDrive.silenceFloor * 0.9, count: 64), frames: 30)
        XCTAssertTrue(below.isAtRest, "below the floor is silence")
    }

    func testReduceMotionHalvesBlendSpeedAndWidening() {
        for reduceMotion in [false, true] {
            var drive = CymaticDrive()
            CymaticFixture.run(&drive, bands: CymaticFixture.lit(19, level: 1), frames: 16, reduceMotion: reduceMotion)   // 0.25 s
            XCTAssertEqual(drive.weights[3], reduceMotion ? 0.25 : 0.5, accuracy: 1e-5)
            CymaticFixture.run(&drive, bands: CymaticFixture.lit(19, level: 1), from: 16, frames: 120, reduceMotion: reduceMotion)
            XCTAssertEqual(drive.frame.width, reduceMotion ? 0.11 : 0.14, accuracy: 1e-6)
        }
    }

    func testTimeNeverRunsBackwardsAndGapsAreBounded() {
        var drive = CymaticDrive()
        let bands = CymaticFixture.lit(19, level: 1)
        CymaticFixture.run(&drive, bands: bands, frames: 1)
        let anchored = drive
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            drive.advance(bands: b, range: .all, timeNanoseconds: 0, reduceMotion: false)
            XCTAssertEqual(drive, anchored, "the same time: nothing moves")
            drive.advance(bands: b, range: .all, timeNanoseconds: 10_000_000_000, reduceMotion: false)
        }
        XCTAssertEqual(drive.weights[3], 0.5, accuracy: 1e-6, "a 10 s gap moves at most 0.25 s")
        bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Void in
            let before = drive
            drive.advance(bands: b, range: .all, timeNanoseconds: 5_000_000_000, reduceMotion: false)
            XCTAssertEqual(drive.weights, before.weights, "backwards: nothing moves")
        }
    }

    func testExtremeInputsStayFiniteAndBelowFullWhite() {
        var bands = [Float](repeating: 1e6, count: 128)
        bands[0] = .nan; bands[1] = .infinity; bands[2] = -.infinity; bands[3] = -5
        for count in [0, 16, 32, 64, 128] {
            for range in CymaticBandRange.allCases {
                var drive = CymaticDrive()
                CymaticFixture.run(&drive, bands: Array(bands.prefix(count)), range: range, frames: 30)
                let frame = drive.frame
                XCTAssertTrue((0..<16).allSatisfy { (k: Int) -> Bool in frame.weights[k].isFinite }, "\(count) \(range)")
                XCTAssertTrue(frame.amplitude <= 1 && frame.brightness <= 0.8 && frame.width.isFinite)
                if count == 0 { XCTAssertTrue(drive.isAtRest, "no bands: rest") }
            }
        }
        let garbage = CymaticField.frame(weights: SIMD16<Float>(repeating: .nan), amplitude: .infinity, reduceMotion: true)
        XCTAssertEqual(garbage.weights, CymaticField.restWeights, "no usable weight: rest")
        let stops: [LinearColor] = (0..<16).map { (_: Int) -> LinearColor in LinearColor(red: 1, green: 1, blue: 1, alpha: 1) }
        let loud = CymaticField.frame(weights: CymaticField.one(5), amplitude: 1, reduceMotion: false)
        let points: [SIMD2<Float>] = [SIMD2(.nan, 0.3), SIMD2(.infinity, -.infinity), SIMD2(1e30, -1e30), SIMD2(0.5, 0.5), SIMD2(0.13, 0.71)]
        stops.withUnsafeBufferPointer { (p: UnsafeBufferPointer<LinearColor>) -> Void in
            for q in points {
                for frame in [loud, garbage, CymaticFrame.rest] {
                    let c = CymaticField.shade(q, frame: frame, stops: p.baseAddress!)
                    for v in [c.red, c.green, c.blue] { XCTAssertTrue(v.isFinite && v >= 0 && v <= 0.8 + 1e-6, "\(q): \(c)") }
                }
            }
        }
    }

    func testConfigurationTurnsTheOtherModesOff() {
        var c = NoiseFieldConfiguration.signedDistance(.default)
        c.cymatic = CymaticSettings(bands: .mid)
        c.wedges = 6
        let clamped = c.clamped()
        XCTAssertNil(clamped.signedDistance)
        XCTAssertEqual(clamped.wedges, 0)
        XCTAssertEqual(NoiseFieldConfiguration.cymatic(CymaticSettings(bands: .high)).cymatic?.bands, .high)
        XCTAssertNil(NoiseFieldConfiguration().cymatic)
    }
}
