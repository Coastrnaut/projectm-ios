// FX-018-T03: the scanline value and line rule (plain Swift; also runs in the Linux shape). Ranges and clamping, the
// effective thickness, inactive cases, the rule anchored at index 0 for every spacing, zero intensity is identity, and
// finite output for finite and HDR input (FX-018-R2 to R5, R12).
import Compositor
import XCTest

final class ScanlinesModelTests: XCTestCase {
    func testScanlinesDefaultsAndClamps() {
        let off = Scanlines.off
        XCTAssertFalse(off.isEnabled)
        XCTAssertEqual(off.spacing, 3)
        XCTAssertEqual(off.thickness, 1)
        XCTAssertEqual(off.intensity, 0.5)
        XCTAssertFalse(off.isVertical)
        XCTAssertEqual(Scanlines.clampSpacing(1), 2)
        XCTAssertEqual(Scanlines.clampSpacing(99), 16)
        XCTAssertEqual(Scanlines.clampSpacing(Double.nan), 3)
        XCTAssertEqual(Scanlines.clampSpacing(Double.infinity), 16)
        XCTAssertEqual(Scanlines.clampSpacing(4.6), 5, "rounded to whole pixels")
        XCTAssertEqual(Scanlines.clampThickness(0), 1)
        XCTAssertEqual(Scanlines.clampThickness(-Double.infinity), 1)
        XCTAssertEqual(Scanlines.clampThickness(Double.nan), 1)
        XCTAssertEqual(Scanlines.clampThickness(30), 15)
        XCTAssertEqual(Scanlines.clampIntensity(-1), 0)
        XCTAssertEqual(Scanlines.clampIntensity(Double.nan), 0.5)
        XCTAssertEqual(Scanlines(spacing: 40, thickness: 0, intensity: 3).clamped,
                       Scanlines(spacing: 16, thickness: 1, intensity: 1))
    }

    func testScanlinesThicknessIsAtMostSpacingMinusOne() {
        XCTAssertEqual(Scanlines(spacing: 2, thickness: 15).effectiveThickness, 1)
        XCTAssertEqual(Scanlines(spacing: 8, thickness: 8).effectiveThickness, 7)
        XCTAssertEqual(Scanlines(spacing: 8, thickness: 3).effectiveThickness, 3)
        XCTAssertEqual(Scanlines(spacing: 16, thickness: 15).effectiveThickness, 15)
        let b: Scanlines.Block = Scanlines(isEnabled: true, spacing: 5, thickness: 9, intensity: 0.25, isVertical: true).block
        XCTAssertEqual(b, Scanlines.Block(period: 5, thickness: 4, vertical: 1, factor: 0.75))
        XCTAssertEqual(MemoryLayout<Scanlines.Block>.stride, 16, "CMPScanlines is 16 bytes")
        XCTAssertEqual(Scanlines(isEnabled: false, intensity: 1).block.factor, 1, "disabled is the identity factor")
    }

    func testScanlinesInactiveCases() {
        XCTAssertFalse(Scanlines(isEnabled: false, intensity: 1).isActive(width: 64, height: 64))
        XCTAssertFalse(Scanlines(isEnabled: true, intensity: 0).isActive(width: 64, height: 64))
        XCTAssertFalse(Scanlines(isEnabled: true, intensity: 1).isActive(width: 1, height: 64))
        XCTAssertFalse(Scanlines(isEnabled: true, intensity: 1).isActive(width: 64, height: 1))
        XCTAssertTrue(Scanlines(isEnabled: true, intensity: 0.01).isActive(width: 2, height: 2))
    }

    func testScanlinesRuleIsAnchoredAtIndexZeroForEverySpacing() {
        for p in Scanlines.spacingRange {
            for t in [1, p / 2, p - 1] where t >= 1 {
                let b: Scanlines.Block = Scanlines(isEnabled: true, spacing: p, thickness: t, intensity: 1).block
                let rows: [Int] = (0..<100).filter { (y: Int) -> Bool in Scanlines.isDark(x: 7, y: y, block: b) }
                XCTAssertEqual(rows, (0..<100).filter { (y: Int) -> Bool in y % p < t }, "spacing \(p), thickness \(t)")
                XCTAssertTrue(Scanlines.isDark(x: 5, y: 0, block: b), "row 0 is dark")
                XCTAssertFalse(Scanlines.isDark(x: 0, y: t, block: b), "row t is the first untouched row")
                let starts: [Int] = rows.filter { (y: Int) -> Bool in y == 0 || !rows.contains(y - 1) }
                for (a, n) in zip(starts, starts.dropFirst()) { XCTAssertEqual(n - a, p, "pitch = spacing") }
            }
        }
        let vertical: Scanlines.Block = Scanlines(isEnabled: true, spacing: 4, thickness: 2, intensity: 1, isVertical: true).block
        XCTAssertEqual((0..<9).map { (x: Int) -> Bool in Scanlines.isDark(x: x, y: 3, block: vertical) },
                       [true, true, false, false, true, true, false, false, true], "columns when vertical")
    }

    func testScanlinesZeroIntensityIsIdentityAndOutputStaysFinite() {
        let w = 9, h = 7
        let pixels: [SIMD4<Float>] = (0..<(w * h)).map { (i: Int) -> SIMD4<Float> in
            SIMD4<Float>(Float(i % 5) / 5, Float(i % 3) / 3, 60_000, 1)
        }
        XCTAssertEqual(Scanlines(isEnabled: true, intensity: 0).reference(pixels, width: w, height: h), pixels)
        XCTAssertEqual(Scanlines.off.reference(pixels, width: w, height: h), pixels)
        let b: Scanlines.Block = Scanlines(isEnabled: true, intensity: 0).block
        XCTAssertEqual(b.factor, 1)
        for y in 0..<h {
            for x in 0..<w { XCTAssertEqual(Scanlines.referencePixel(pixels[y * w + x], x: x, y: y, block: b), pixels[y * w + x]) }
        }
        let lines = Scanlines(isEnabled: true, spacing: 2, intensity: 0.8)
        let out: [SIMD4<Float>] = lines.reference(pixels, width: w, height: h)
        for (i, p) in out.enumerated() {
            for ch in 0..<4 {
                XCTAssertTrue(p[ch].isFinite)
                XCTAssertLessThanOrEqual(p[ch], pixels[i][ch], "never brighter")
            }
            XCTAssertEqual(p.w, pixels[i].w, "alpha kept")
            if (i / w) % 2 == 1 { XCTAssertEqual(p, pixels[i], "odd rows untouched") }
        }
    }
}
