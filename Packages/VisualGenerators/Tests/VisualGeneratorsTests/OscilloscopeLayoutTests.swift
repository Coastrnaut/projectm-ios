// OscilloscopeLayoutTests.swift — VIS-003-T06: the oscilloscope's geometry on the CPU (VIS-003-R6 to
// R9, S3; data-model.md): configuration clamping, points across the width, sample mapping and
// sanitizing, rectangles with bevel joins, tessellation, fixed storage, and the 17 area levels against
// an independent supersampled integration. Pure Swift (Linux too); representative cases only.
import FlashSafety
import XCTest
@testable import VisualGenerators

final class OscilloscopeLayoutTests: XCTestCase {
    private let sine = WaveformSignal(shape: .sine, frequency: 440)

    func testConfigurationDefaultsAndClamping() {
        let c = OscilloscopeConfiguration()
        XCTAssertEqual(c.windowMilliseconds, 20)
        XCTAssertEqual(c.windowSamples, 882)
        XCTAssertEqual(c.lineThickness, 0.008)
        XCTAssertEqual(c.amplitude, 0.9)
        XCTAssertEqual(c.palette, .spectrum)
        XCTAssertEqual(OscilloscopeConfiguration(windowMilliseconds: 10).windowSamples, 441)
        XCTAssertEqual(OscilloscopeConfiguration(windowMilliseconds: 40).windowSamples, 1_764)
        let clamped = OscilloscopeConfiguration(windowMilliseconds: 500, lineThickness: 1, amplitude: 0)
        XCTAssertEqual(clamped.windowMilliseconds, 40)
        XCTAssertEqual(clamped.lineThickness, 0.05)
        XCTAssertEqual(clamped.amplitude, 0.1)
        let low = OscilloscopeConfiguration(windowMilliseconds: 1, lineThickness: 0, amplitude: 9)
        XCTAssertEqual(low.windowMilliseconds, 5)
        XCTAssertEqual(low.lineThickness, 0.001)
        XCTAssertEqual(low.amplitude, 1)
        let bad = OscilloscopeConfiguration(windowMilliseconds: .nan, lineThickness: .infinity, amplitude: -.infinity)
        XCTAssertEqual(bad, OscilloscopeConfiguration())
    }

    func testPointsSpanTheWidthAndMapSamples() {
        let layout = OscilloscopeLayout()
        let width = 390, height = 844
        // A ramp from −1.5 to 1.5 with NaN and ∞ entries, drawn from a known start (no trigger).
        var samples = (0..<4_096).map { (i: Int) -> Float in Float(i) / 4_095 * 3 - 1.5 }
        samples[3_300] = .nan
        samples[3_400] = .infinity
        samples.withUnsafeBufferPointer { layout.layout(samples: $0, start: 3_000, width: width, height: height) }
        XCTAssertEqual(layout.pointCount, 882)
        XCTAssertEqual(layout.segmentCount, 881)
        XCTAssertEqual(layout.point(0).x, 0)
        XCTAssertEqual(layout.point(881).x, Double(width), accuracy: 1e-9)
        let half = Double(height) / 2
        for j in 0..<layout.pointCount {
            let p = layout.point(j)
            XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            XCTAssertTrue(p.y >= half - 0.9 * half - 1e-9 && p.y <= half + 0.9 * half + 1e-9, "point \(j) inside the amplitude band")
        }
        // Sample 3,000 → point 0: s = 3000/4095·3 − 1.5 ≈ 0.698.
        let s0 = Double(samples[3_000])
        XCTAssertEqual(layout.point(0).y, half - s0 * 0.9 * half, accuracy: 1e-3)
        // The NaN sample reads 0 (point at 300 samples into the window, step 881/881 = 1).
        XCTAssertEqual(layout.point(300).y, half, accuracy: 1e-9)
        // Clamped: a sample above 1 never goes above the band.
        samples = [Float](repeating: 5, count: 4_096)
        samples.withUnsafeBufferPointer { layout.layout(samples: $0, start: 0, width: width, height: height) }
        XCTAssertEqual(layout.point(10).y, half - 0.9 * half, accuracy: 1e-9)
        // 40 ms: 1,764 samples drawn as 1,024 points.
        layout.configuration.windowMilliseconds = 40
        samples.withUnsafeBufferPointer { layout.layout(samples: $0, start: 0, width: width, height: height) }
        XCTAssertEqual(layout.pointCount, OscilloscopeLayout.maximumPoints)
    }

    func testRectanglesAndBevels() {
        let layout = OscilloscopeLayout(configuration: OscilloscopeConfiguration(lineThickness: 0.02))
        let width = 400, height = 300
        let samples = sine.history(endingAt: 30_000)
        samples.withUnsafeBufferPointer { layout.layout(samples: $0, width: width, height: height) }
        let t = layout.thicknessPixels
        XCTAssertEqual(t, 0.02 * 300, accuracy: 1e-12)
        var bevels = 0
        for k in 0..<layout.segmentCount {
            let a = layout.point(k), b = layout.point(k + 1)
            let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            XCTAssertEqual(layout.flashRegionArea(k), length * t, accuracy: 1e-9, "segment \(k) is a length × T rectangle")
            var n = 0
            layout.forEachFlashQuad(ofRegion: k) { ax, ay, bx, by, cx, cy, dx, dy in
                n += 1
                // Its corners are T/2 from the segment's ends (butt ends).
                for (x, y, ox, oy) in [(ax, ay, a.x, a.y), (bx, by, b.x, b.y), (cx, cy, b.x, b.y), (dx, dy, a.x, a.y)] {
                    XCTAssertEqual(((x - ox) * (x - ox) + (y - oy) * (y - oy)).squareRoot(), t / 2, accuracy: 1e-9)
                }
            }
            XCTAssertEqual(n, 1)
        }
        for j in 0..<(layout.pointCount - 2) {
            let area = layout.flashRegionArea(layout.segmentCount + j)
            XCTAssertGreaterThanOrEqual(area, 0)
            XCTAssertLessThanOrEqual(area, t * t / 2 + 1e-9, "a bevel is at most half a T × T square")
            if area > 0 { bevels += 1 }
        }
        XCTAssertGreaterThan(bevels, 0, "a sine turns")
        XCTAssertEqual(layout.flashRegionCount, layout.segmentCount + layout.pointCount - 2)
        // A straight line has no bevel.
        let flat = [Float](repeating: 0.2, count: 4_096)
        flat.withUnsafeBufferPointer { layout.layout(samples: $0, width: width, height: height) }
        for j in 0..<(layout.pointCount - 2) { XCTAssertEqual(layout.flashRegionArea(layout.segmentCount + j), 0) }
    }

    func testTessellationColorsAndZeroSize() {
        let layout = OscilloscopeLayout()
        let samples = sine.history(endingAt: 30_000)
        samples.withUnsafeBufferPointer { layout.layout(samples: $0, width: 200, height: 100) }
        let out = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: OscilloscopeLayout.maximumVertexCount)
        defer { out.deallocate() }
        let count = layout.tessellate(into: out, capacity: OscilloscopeLayout.maximumVertexCount, gain: 0.5)
        var bevels = 0
        for j in 0..<(layout.pointCount - 2) where layout.flashRegionArea(layout.segmentCount + j) > 0 { bevels += 1 }
        XCTAssertEqual(count, 6 * layout.segmentCount + 3 * bevels)
        for i in 0..<count {
            XCTAssertTrue(abs(out[i].x) <= 1.05 && abs(out[i].y) <= 1, "vertex \(i) in NDC")
        }
        let first = layout.flashRegionColor(0)
        XCTAssertEqual(first, VisualPalette.spectrum.color(bar: 0, of: layout.segmentCount))
        XCTAssertEqual(out[0].r, first.red * 0.5, accuracy: 1e-6, "gain scales the premultiplied color")
        XCTAssertEqual(layout.flashRegionColor(layout.segmentCount - 1),
                       VisualPalette.spectrum.color(bar: layout.segmentCount - 1, of: layout.segmentCount))
        samples.withUnsafeBufferPointer { layout.layout(samples: $0, width: 0, height: 100) }
        XCTAssertEqual(layout.tessellate(into: out, capacity: OscilloscopeLayout.maximumVertexCount, gain: 1), 0)
    }

    /// VIS-003-S3: 300 frames of trigger, layout, tessellation and area levels keep every buffer where it
    /// was (300, not 1,000: the area model costs about 4 ms per frame in a Debug build; owner rule 7).
    func testThreeHundredFramesKeepFixedStorage() {
        let layout = OscilloscopeLayout()
        let before = layout.storageAddresses
        let out = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: OscilloscopeLayout.maximumVertexCount)
        defer { out.deallocate() }
        var samples = [Float](repeating: 0, count: 4_096)
        var end: Int64 = 50_000
        var levels = [FlashLevels](repeating: .zero, count: FlashZones.count)
        for f in 0..<300 {
            end += WaveformFrames.advance(frame: f)
            for i in 0..<4_096 { samples[i] = sine.value(at: end - 4_096 + Int64(i)) }
            layout.configuration.windowMilliseconds = [10.0, 20.0, 40.0][f % 3]
            samples.withUnsafeBufferPointer { layout.layout(samples: $0, width: 390, height: 844) }
            _ = layout.tessellate(into: out, capacity: OscilloscopeLayout.maximumVertexCount, gain: 1)
            levels.withUnsafeMutableBufferPointer { layout.meanLevels(gain: 1, transfer: IdentityLuminanceTransfer(), into: $0) }
        }
        XCTAssertEqual(layout.storageAddresses, before)
        XCTAssertEqual(layout.lastTrigger.mode, .triggered)
    }

    /// The 17 levels against an independent integration: every region supersampled 4 × 4 per pixel.
    func testAreaLevelsMatchASupersampledIntegration() {
        let width = 80, height = 60   // tiles 20 × 15
        let layout = OscilloscopeLayout(configuration: OscilloscopeConfiguration(windowMilliseconds: 10, lineThickness: 0.05))
        let samples = WaveformSignal(shape: .sine, frequency: 330).history(endingAt: 30_000)
        samples.withUnsafeBufferPointer { layout.layout(samples: $0, width: width, height: height) }
        let gain: Float = 0.8
        var got = [FlashLevels](repeating: .zero, count: FlashZones.count)
        got.withUnsafeMutableBufferPointer { layout.meanLevels(gain: gain, transfer: IdentityLuminanceTransfer(), into: $0) }
        var expected = [Double](repeating: 0, count: FlashZones.count)
        let tileArea = Double(width * height) / 16
        let step = 0.25
        for k in 0..<layout.flashRegionCount where layout.flashRegionArea(k) > 0 {
            var corners: [(Double, Double)] = []
            layout.forEachFlashQuad(ofRegion: k) { ax, ay, bx, by, cx, cy, dx, dy in
                corners = [(ax, ay), (bx, by), (cx, cy), (dx, dy)]
            }
            let y = Double(layout.flashRegionColor(k).relativeLuminance * gain)
            let xs = corners.map { (p: (Double, Double)) -> Double in p.0 }, ys = corners.map { (p: (Double, Double)) -> Double in p.1 }
            var sy = (ys.min()! / step).rounded(.down) * step + step / 2
            while sy < ys.max()! {
                var sx = (xs.min()! / step).rounded(.down) * step + step / 2
                while sx < xs.max()! {
                    if sx >= 0, sx < Double(width), sy >= 0, sy < Double(height), Self.inside(corners, sx, sy) {
                        let z = Int(sy / 15) * 4 + Int(sx / 20)
                        expected[z] += step * step * y / tileArea
                    }
                    sx += step
                }
                sy += step
            }
        }
        for z in 0..<FlashZones.tileCount {
            // The model counts overlaps twice (conservative); the supersampled sum counts them too.
            XCTAssertEqual(got[z].luminance, expected[z], accuracy: max(0.03 * expected[z], 2e-4), "tile \(z)")
        }
        XCTAssertGreaterThan(got[FlashZones.wholeFrame].luminance, 0)
    }

    /// Point in a convex polygon (any winding; a repeated vertex is a zero-length edge).
    private static func inside(_ p: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
        var sign = 0.0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            let cross: Double = (b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0)
            if (b.0 - a.0) == 0 && (b.1 - a.1) == 0 { continue }
            if cross != 0 {
                if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
            }
        }
        return true
    }
}
