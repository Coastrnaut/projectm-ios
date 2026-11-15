// FX-012-T03: the mosaic's value, square and hexagon cell assignment and CPU reference (FX-012-R2 to R6, R12; research
// FX-012-D2 to D5). Plain Swift, no GPU: runs on Linux too.
import Compositor
import XCTest

final class MosaicModelTests: XCTestCase {
    func testMosaicClampsAndDefaults() {
        XCTAssertEqual(Mosaic.off, Mosaic(isEnabled: false, blockSize: 8, shape: .square))
        XCTAssertEqual(Mosaic.clampSize(Double.nan), 8)
        XCTAssertEqual(Mosaic.clampSize(0.4), 1)
        XCTAssertEqual(Mosaic.clampSize(3.6), 4, "rounded to whole pixels")
        XCTAssertEqual(Mosaic.clampSize(1000.0), 64)
        XCTAssertEqual(Mosaic.clampSize(-Double.infinity), 1)
        XCTAssertEqual(Mosaic.clampSize(0), 1)
        XCTAssertEqual(Mosaic(isEnabled: true, blockSize: 99, shape: .hexagon).clamped,
                       Mosaic(isEnabled: true, blockSize: 64, shape: .hexagon))
    }

    func testMosaicActiveOnlyWhenOnWithBlocksOfTwoAndTwoPixels() {
        XCTAssertFalse(Mosaic.off.isActive(width: 100, height: 100))
        XCTAssertFalse(Mosaic(isEnabled: true, blockSize: 1).isActive(width: 100, height: 100), "size 1 is the frame")
        XCTAssertFalse(Mosaic(isEnabled: true, blockSize: 1, shape: .hexagon).isActive(width: 100, height: 100))
        XCTAssertFalse(Mosaic(isEnabled: true).isActive(width: 1, height: 100))
        XCTAssertTrue(Mosaic(isEnabled: true, blockSize: 2).isActive(width: 2, height: 2))
    }

    func testMosaicSquareBlocksAnchorTopLeftAndShowTheirCentre() {
        let b = Mosaic(isEnabled: true, blockSize: 8).block(width: 20, height: 10)
        XCTAssertEqual(Mosaic.squareCell(x: 7, y: 7, size: 8), SIMD2(0, 0))
        XCTAssertEqual(Mosaic.squareCell(x: 8, y: 0, size: 8), SIMD2(1, 0))
        XCTAssertEqual(Mosaic.samplePixel(x: 0, y: 0, block: b), SIMD2(4, 4))
        XCTAssertEqual(Mosaic.samplePixel(x: 15, y: 7, block: b), SIMD2(12, 4))
        XCTAssertEqual(Mosaic.samplePixel(x: 19, y: 9, block: b), SIMD2(19, 9), "a partial edge block: centre clamped")
        let odd = Mosaic(isEnabled: true, blockSize: 3).block(width: 9, height: 9)
        XCTAssertEqual(Mosaic.samplePixel(x: 5, y: 3, block: odd), SIMD2(4, 4), "odd sizes: the middle pixel")
    }

    func testMosaicHexCellIsTheNearestPointyTopCentre() {
        let n = 10
        XCTAssertEqual(Mosaic.hexCell(x: 0, y: 0, size: n), SIMD2(0, 0))
        XCTAssertEqual(Mosaic.hexCell(x: 9, y: 0, size: n), SIMD2(1, 0), "nearer (10, 0)")
        XCTAssertEqual(Mosaic.hexCell(x: 5, y: 8, size: n), SIMD2(0, 1), "row 1 is shifted by half a cell")
        XCTAssertEqual(Mosaic.hexCentre(SIMD2(0, 1), size: n).y, 8.660254, accuracy: 1e-4)
        // Brute force: the chosen centre is (within float ties) the nearest of all nearby centres.
        for y in 0..<40 {
            for x in 0..<40 {
                let p = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                let chosen: SIMD2<Float> = Mosaic.hexCentre(Mosaic.hexCell(x: x, y: y, size: n), size: n) - p
                var best: Float = .infinity
                for r in -1...6 {
                    for q in -4...6 {
                        let d: SIMD2<Float> = Mosaic.hexCentre(SIMD2(q, r), size: n) - p
                        best = min(best, (d * d).sum())
                    }
                }
                XCTAssertLessThanOrEqual((chosen * chosen).sum(), best + 1e-3, "(\(x), \(y))")
            }
        }
    }

    func testMosaicSamplesStayInsideTheFrame() {
        let w = 37, h = 29
        for shape in MosaicShape.allCases {
            for size in [2, 7, 64] {
                let b = Mosaic(isEnabled: true, blockSize: size, shape: shape).block(width: w, height: h)
                for y in 0..<h {
                    for x in 0..<w {
                        let p = Mosaic.samplePixel(x: x, y: y, block: b)
                        XCTAssertTrue(p.x >= 0 && p.y >= 0 && p.x < w && p.y < h, "\(shape) \(size): \(p)")
                    }
                }
            }
        }
    }

    func testMosaicReferenceIdentityAndUniformBlocks() {
        let w = 16, h = 16
        let pixels: [Int] = Array(0..<(w * h))
        XCTAssertEqual(Mosaic.off.reference(pixels, width: w, height: h), pixels)
        XCTAssertEqual(Mosaic(isEnabled: true, blockSize: 1, shape: .hexagon).reference(pixels, width: w, height: h), pixels)
        let out: [Int] = Mosaic(isEnabled: true, blockSize: 8).reference(pixels, width: w, height: h)
        XCTAssertEqual(Set(out), [4 * w + 4, 4 * w + 12, 12 * w + 4, 12 * w + 12], "four blocks, each its centre pixel")
    }
}
