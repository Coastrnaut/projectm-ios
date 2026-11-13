// LinearSpectrumLayoutTests.swift — VIS-002-T03: the roadmap acceptance on the CPU ("Reference
// spectrum yields correct bar count and bounded height"; VIS-002-R2 to R5, R8; VIS-002-S1, S2).
// The expected rectangles are recomputed here from the documented formulas (data-model.md), not
// read from the layout. Representative cases only (owner rule 7). No Metal: runs on Linux.
import XCTest
@testable import VisualGenerators

final class LinearSpectrumLayoutTests: XCTestCase {
    private static let sizes: [(width: Int, height: Int)] = [(390, 844), (844, 390), (128, 128)]

    /// A ramp (k + 1)/N with NaN, −1, 2, +∞ and −∞ at bands 1…5.
    static func referenceSpectrum(_ n: Int) -> [Float] {
        var v = (0..<n).map { Float($0 + 1) / Float(n) }
        v[1] = .nan; v[2] = -1; v[3] = 2; v[4] = .infinity; v[5] = -.infinity
        return v
    }

    /// VIS-001-R8.
    static func sanitized(_ v: Float) -> Double { v.isNaN || v <= 0 ? 0 : Double(min(v, 1)) }

    /// The oracle's bar rectangle (pixels, y down) for value v (data-model.md).
    static func expectedBar(k: Int, n: Int, v: Double, c: LinearSpectrumConfiguration, width: Int, height: Int)
        -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let vertical = c.orientation == .vertical
        let cross = Double(vertical ? width : height), length = Double(vertical ? height : width)
        let p = cross / Double(n)
        // Cross-axis edges rounded to whole pixels (VIS-002-R4).
        let c0 = (Double(k) * p + c.spacing * p / 2).rounded(), c1 = (Double(k) * p + c.spacing * p / 2 + (1 - c.spacing) * p).rounded()
        let l = v * c.lengthScale * length
        return vertical ? (c0, length - l, c1, length) : (0, c0, l, c1)
    }

    func testConfigurationDefaultsAndClamping() {
        let d = LinearSpectrumConfiguration()
        XCTAssertEqual(d.barCount, .b64)
        XCTAssertEqual(d.orientation, .vertical)
        XCTAssertEqual(d.spacing, 0.2)
        XCTAssertEqual(d.capThickness, 0.015)
        XCTAssertEqual(d.lengthScale, 0.9)
        XCTAssertEqual(d.peakHoldSeconds, 0.5)
        XCTAssertEqual(d.peakFallPerSecond, 1.0)
        XCTAssertEqual(d.palette, .spectrum)
        XCTAssertEqual(d.background, .opaqueBlack)
        XCTAssertEqual(LinearSpectrumOrientation.allCases.map(\.rawValue), ["vertical", "horizontal"])
        let high = LinearSpectrumConfiguration(spacing: 2, capThickness: 1, lengthScale: 5, peakHoldSeconds: 60, peakFallPerSecond: 100)
        XCTAssertEqual(high.spacing, 0.9, "spacing 0…0.9")
        XCTAssertEqual(high.capThickness, 0.05, "capThickness 0…0.05")
        XCTAssertEqual(high.lengthScale, 0.95, accuracy: 1e-12, "lengthScale 0…(1 − t)")
        XCTAssertEqual(high.peakHoldSeconds, 5, "peakHoldSeconds 0…5")
        XCTAssertEqual(high.peakFallPerSecond, 10, "peakFallPerSecond 0.1…10")
        let low = LinearSpectrumConfiguration(spacing: -1, capThickness: -1, lengthScale: -1, peakHoldSeconds: -1, peakFallPerSecond: 0)
        XCTAssertEqual([low.spacing, low.capThickness, low.lengthScale, low.peakHoldSeconds, low.peakFallPerSecond], [0, 0, 0, 0, 0.1])
        let nan = LinearSpectrumConfiguration(spacing: .nan, capThickness: .infinity, lengthScale: .nan,
                                              peakHoldSeconds: .nan, peakFallPerSecond: -.infinity)
        XCTAssertEqual([nan.spacing, nan.capThickness, nan.lengthScale, nan.peakHoldSeconds, nan.peakFallPerSecond],
                       [0.2, 0.015, 0.9, 0.5, 1.0], "non-finite → default")
        var later = LinearSpectrumConfiguration()
        later.spacing = 7
        XCTAssertEqual(later.clamped().spacing, 0.9)
    }

    func testReferenceSpectrumYieldsNBarsOfBoundedHeightInBothOrientations() {
        var checked = 0
        var worst = 0.0
        for orientation in LinearSpectrumOrientation.allCases {
            for n in SpectrumBarCount.allCases {
                let c = LinearSpectrumConfiguration(barCount: n, orientation: orientation)
                let layout = LinearSpectrumLayout(configuration: c)
                let input = Self.referenceSpectrum(n.rawValue)
                for size in Self.sizes {
                    layout.resetPeaks()
                    layout.layout(input, frameTime: 1.0 / 60, width: size.width, height: size.height)
                    XCTAssertEqual(layout.barCount, n.rawValue, "N slots")
                    var lit = 0
                    for k in 0..<n.rawValue {
                        let v = Self.sanitized(input[k])
                        let e = Self.expectedBar(k: k, n: n.rawValue, v: v, c: c, width: size.width, height: size.height)
                        let rects = layout.rectangles(ofBar: k)
                        XCTAssertEqual(Double(layout.value(ofBar: k)), v, accuracy: 1e-7)
                        guard v > 0 else {
                            XCTAssertNil(rects.bar, "\(orientation) N=\(n.rawValue) k=\(k): a zero band draws no bar")
                            XCTAssertNil(rects.cap, "no cap at 0")
                            continue
                        }
                        lit += 1
                        guard let bar = rects.bar, let cap = rects.cap else {
                            XCTFail("\(orientation) N=\(n.rawValue) k=\(k): bar and cap expected"); continue
                        }
                        for (got, want) in [(bar.minX, e.minX), (bar.minY, e.minY), (bar.maxX, e.maxX), (bar.maxY, e.maxY)] {
                            worst = max(worst, abs(got - want))
                            XCTAssertEqual(got, want, accuracy: 0.001, "\(orientation) N=\(n.rawValue) k=\(k) \(size)")
                        }
                        // Bounded: the bar's length never exceeds λ·L; bar and cap stay inside the output.
                        let length = orientation == .vertical ? bar.height : bar.width
                        let axis = Double(orientation == .vertical ? size.height : size.width)
                        XCTAssertGreaterThanOrEqual(length, 0)
                        XCTAssertLessThanOrEqual(length, c.lengthScale * axis + 1e-9)
                        for r in [bar, cap] {
                            XCTAssertTrue([r.minX, r.minY, r.maxX, r.maxY].allSatisfy(\.isFinite))
                            XCTAssertGreaterThanOrEqual(r.minX, 0); XCTAssertGreaterThanOrEqual(r.minY, 0)
                            XCTAssertLessThanOrEqual(r.maxX, Double(size.width) + 1e-9)
                            XCTAssertLessThanOrEqual(r.maxY, Double(size.height) + 1e-9)
                        }
                        // The cap sits on the bar's end (first frame: peak = value), t·L thick.
                        if orientation == .vertical {
                            XCTAssertEqual(cap.maxY, bar.minY, accuracy: 1e-9)
                            XCTAssertEqual(cap.height, c.capThickness * axis, accuracy: 1e-9)
                            XCTAssertEqual(bar.maxY, Double(size.height), "rises from the bottom edge")
                        } else {
                            XCTAssertEqual(cap.minX, bar.maxX, accuracy: 1e-9)
                            XCTAssertEqual(cap.width, c.capThickness * axis, accuracy: 1e-9)
                            XCTAssertEqual(bar.minX, 0, "grows from the left edge")
                        }
                        checked += 1
                    }
                    XCTAssertEqual(lit, n.rawValue - 3, "every band above 0 is lit (NaN, −1 and −∞ are not)")
                }
            }
        }
        print("VIS-002 matrix: \(checked) lit bars checked (2 orientations × 4 bar counts × 3 sizes), worst edge error \(worst) px")
    }

    func testSpacingIsHonored() {
        for spacing in [0.0, 0.2, 0.5] {
            let layout = LinearSpectrumLayout(configuration: LinearSpectrumConfiguration(barCount: .b16, spacing: spacing))
            layout.layout([Float](repeating: 0.5, count: 16), frameTime: 0, width: 320, height: 200)
            let pitch = 320.0 / 16   // 20 px: every edge already falls on a whole pixel
            for k in 0..<16 {
                let bar = try! XCTUnwrap(layout.rectangles(ofBar: k).bar)
                XCTAssertEqual(bar.width, (1 - spacing) * pitch, accuracy: 1e-9, "width (1 − s)·p")
                XCTAssertEqual((bar.minX + bar.maxX) / 2, (Double(k) + 0.5) * pitch, accuracy: 1e-9, "centred in its slot")
                if k > 0 {
                    let previous = try! XCTUnwrap(layout.rectangles(ofBar: k - 1).bar)
                    XCTAssertEqual(bar.minX - previous.maxX, spacing * pitch, accuracy: 1e-9, "gap s·p")
                }
            }
        }
    }

    func testShortInputSilenceAndZeroSize() {
        let layout = LinearSpectrumLayout(configuration: LinearSpectrumConfiguration(barCount: .b32))
        layout.layout([1, 1], frameTime: 0, width: 100, height: 100)
        XCTAssertNotNil(layout.rectangles(ofBar: 1).bar)
        XCTAssertNil(layout.rectangles(ofBar: 2).bar, "missing bands read 0")
        let vertices = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: LinearSpectrumLayout.maximumVertexCount)
        defer { vertices.deallocate() }
        let silent = LinearSpectrumLayout()
        silent.layout([Float](repeating: 0, count: 64), frameTime: 0, width: 100, height: 100)
        XCTAssertEqual(silent.tessellate(into: vertices, capacity: LinearSpectrumLayout.maximumVertexCount, gain: 1), 0, "silence draws nothing")
        let empty = LinearSpectrumLayout()
        empty.layout([Float](repeating: 1, count: 64), frameTime: 0, width: 0, height: 0)
        XCTAssertEqual(empty.tessellate(into: vertices, capacity: LinearSpectrumLayout.maximumVertexCount, gain: 1), 0, "zero size")
        empty.layout([Float](repeating: 1, count: 64), frameTime: 0, width: 1, height: 1)
        // 1 × 1: slots narrower than a pixel round to nothing or to the one pixel; never outside.
        let drawn = (0..<64).compactMap { empty.rectangles(ofBar: $0).bar }
        XCTAssertTrue(drawn.allSatisfy { $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 1 && $0.maxY <= 1 }, "tiny output stays inside")
    }

    func testTessellationStaysInsideAndScalesColors() {
        let layout = LinearSpectrumLayout(configuration: LinearSpectrumConfiguration(barCount: .b128, orientation: .horizontal))
        layout.layout([Float](repeating: 1, count: 128), frameTime: 0, width: 200, height: 640)
        let capacity = LinearSpectrumLayout.maximumVertexCount
        XCTAssertEqual(capacity, 128 * 12, "bars and caps of 128 bars fit")
        let vertices = UnsafeMutablePointer<SpectrumVertex>.allocate(capacity: capacity)
        defer { vertices.deallocate() }
        let count = layout.tessellate(into: vertices, capacity: capacity, gain: 0.5)
        XCTAssertEqual(count, 128 * 12, "6 vertices per bar and per cap")
        for i in 0..<count {
            XCTAssertTrue((-1...1).contains(vertices[i].x) && (-1...1).contains(vertices[i].y), "vertex \(i) inside NDC")
        }
        let expected = VisualPalette.spectrum.color(bar: 0, of: 128)
        XCTAssertEqual(vertices[0].r, expected.red * 0.5, accuracy: 1e-6, "premultiplied, × gain")
        XCTAssertEqual(vertices[0].g, expected.green * 0.5, accuracy: 1e-6)
        XCTAssertEqual(vertices[0].a, 1)
        // The first bar of a horizontal layout starts at the top-left corner: NDC x = −1, y = 1.
        let xs = (0..<6).map { vertices[$0].x }, ys = (0..<6).map { vertices[$0].y }
        XCTAssertEqual(xs.min()!, -1, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(ys.max()!, 1)
        XCTAssertEqual(layout.tessellate(into: vertices, capacity: 11, gain: 1), 6, "whole rectangles only")
    }
}
