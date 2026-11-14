// CMP-007-T04: the plain-Swift mask reference (CMP-007-R1 to R5, R8, R13; research CMP-007-D1, D4).
// No GPU; builds and runs on Linux (the Compositor target's CPU part).
import Compositor
import Foundation
import XCTest

final class LayerMaskReferenceTests: XCTestCase {
    private func mask(_ shape: LayerMaskShape, _ transform: LayerMaskTransform = .identity, feather: Double = 0,
                      inverted: Bool = false) throws -> LayerMask {
        try LayerMask(shape: shape, transform: transform, feather: feather, inverted: inverted)
    }

    func testCircleDistanceAndCoverageOnASquarePicture() throws {
        // 100 × 100, scale 1: a circle of radius 50 px centred at (50, 50); band 1 px.
        let g = try mask(.ellipse).geometry(width: 100, height: 100)
        XCTAssertEqual(g.band, 1)
        XCTAssertEqual(g.signedDistance(x: 50, y: 50), -50, accuracy: 1e-9)
        XCTAssertEqual(g.signedDistance(x: 100, y: 50), 0, accuracy: 1e-9)
        XCTAssertEqual(g.signedDistance(x: 50, y: 110), 10, accuracy: 1e-9)
        XCTAssertEqual(g.coverage(x: 50, y: 50), 1)          // exactly 1 inside
        XCTAssertEqual(g.coverage(x: 50, y: 0), 0.5, accuracy: 1e-12)      // on the edge
        XCTAssertEqual(g.coverage(x: 0.5, y: 0.5), 0)        // corner: exactly 0
        XCTAssertEqual(g.coverage(x: 50, y: 100.5), 0)       // d = 0.5 = band/2 → exactly 0
        XCTAssertEqual(g.coverage(x: 50, y: 99.5), 1)        // d = −0.5 → exactly 1
    }

    func testCircleStaysRoundOnWideAndTallPictures() throws {
        for (w, h) in [(160, 90), (90, 160)] {
            let g = try mask(.ellipse, LayerMaskTransform(scale: LayerPoint(x: 0.5, y: 0.5))).geometry(width: w, height: h)
            let r: Double = 0.25 * Double(min(w, h))
            let cx: Double = Double(w) / 2, cy: Double = Double(h) / 2
            for angle in stride(from: 0.0, to: 6.28, by: 0.7) {
                let x: Double = cx + r * cos(angle)
                let y: Double = cy + r * sin(angle)
                XCTAssertEqual(g.signedDistance(x: x, y: y), 0, accuracy: 1e-9, "\(w)×\(h) at \(angle)")
            }
        }
    }

    func testEllipseSignIsExact() throws {
        let g = try mask(.ellipse, LayerMaskTransform(scale: LayerPoint(x: 1, y: 0.4))).geometry(width: 100, height: 100)
        // Half extents 50 × 20.
        XCTAssertLessThan(g.signedDistance(x: 50 + 49.5, y: 50), 0)
        XCTAssertGreaterThan(g.signedDistance(x: 50 + 50.5, y: 50), 0)
        XCTAssertLessThan(g.signedDistance(x: 50, y: 50 + 19.5), 0)
        XCTAssertGreaterThan(g.signedDistance(x: 50, y: 50 + 20.5), 0)
        XCTAssertEqual(g.signedDistance(x: 50, y: 50), -20)
    }

    func testRoundedRectangle() throws {
        // 200 × 100, scale (1, 0.5) of S = 100 → 100 × 50 px box at the centre, radius 0.4 × 50 = 20 px.
        let g = try mask(.rectangle(cornerRadius: 0.4), LayerMaskTransform(scale: LayerPoint(x: 1, y: 0.5)))
            .geometry(width: 200, height: 100)
        XCTAssertEqual(g.cornerRadius, 20, accuracy: 1e-12)
        XCTAssertEqual(g.signedDistance(x: 150, y: 50), 0, accuracy: 1e-9)        // right edge
        XCTAssertEqual(g.signedDistance(x: 100, y: 25), 0, accuracy: 1e-9)        // top edge
        // The corner region is rounded: the box corner (150, 25) is outside by (√2 − 1)·20.
        XCTAssertEqual(g.signedDistance(x: 150, y: 25), (2.0.squareRoot() - 1) * 20, accuracy: 1e-9)
        XCTAssertEqual(g.coverage(x: 148, y: 27), 0)
        // A radius above 0.5 is limited to half the shorter side (a stadium).
        let stadium = try mask(.rectangle(cornerRadius: 3))
        XCTAssertEqual(stadium.shape, .rectangle(cornerRadius: 0.5))
    }

    func testConvexAndConcavePolygons() throws {
        let triangle = try mask(.polygon([LayerPoint(x: -0.5, y: 0.5), LayerPoint(x: 0, y: -0.5), LayerPoint(x: 0.5, y: 0.5)]))
            .geometry(width: 100, height: 100)
        XCTAssertLessThan(triangle.signedDistance(x: 50, y: 70), 0)
        XCTAssertGreaterThan(triangle.signedDistance(x: 10, y: 10), 0)
        XCTAssertEqual(triangle.signedDistance(x: 50, y: 100), 0, accuracy: 1e-9)   // on the base
        XCTAssertEqual(triangle.signedDistance(x: 50, y: 110), 10, accuracy: 1e-9)
        // An L: the top-right quarter is the notch.
        let l = try mask(.polygon(Self.lShape)).geometry(width: 100, height: 100)
        XCTAssertLessThan(l.signedDistance(x: 25, y: 25), 0)
        XCTAssertLessThan(l.signedDistance(x: 75, y: 75), 0)
        XCTAssertGreaterThan(l.signedDistance(x: 75, y: 25), 0)                       // notch
        XCTAssertEqual(l.signedDistance(x: 75, y: 25), 25, accuracy: 1e-9)
        XCTAssertEqual(l.coverage(x: 75, y: 25), 0)
        // Winding direction does not matter.
        let reversed = try mask(.polygon(Self.lShape.reversed())).geometry(width: 100, height: 100)
        XCTAssertEqual(reversed.signedDistance(x: 75, y: 25), l.signedDistance(x: 75, y: 25), accuracy: 1e-12)
        XCTAssertEqual(reversed.signedDistance(x: 25, y: 75), l.signedDistance(x: 25, y: 75), accuracy: 1e-12)
    }

    static let lShape: [LayerPoint] = [LayerPoint(x: -0.5, y: -0.5), LayerPoint(x: 0, y: -0.5), LayerPoint(x: 0, y: 0),
                                       LayerPoint(x: 0.5, y: 0), LayerPoint(x: 0.5, y: 0.5), LayerPoint(x: -0.5, y: 0.5)]

    func testSelfIntersectingStarUsesEvenOdd() throws {
        // A five-pointed star drawn in one stroke: the pentagon in the middle is outside (even-odd).
        var points: [LayerPoint] = []
        for k in 0..<5 {
            let a: Double = -Double.pi / 2 + Double(k) * 4 * Double.pi / 5
            points.append(LayerPoint(x: 0.5 * cos(a), y: 0.5 * sin(a)))
        }
        let g = try mask(.polygon(points)).geometry(width: 100, height: 100)
        XCTAssertGreaterThan(g.signedDistance(x: 50, y: 50), 0, "centre is a hole")
        XCTAssertLessThan(g.signedDistance(x: 50, y: 10), 0, "the top point is filled")
    }

    func testInvertAndFeather() throws {
        let plain = try mask(.ellipse).geometry(width: 100, height: 100)
        let inverted = try mask(.ellipse, inverted: true).geometry(width: 100, height: 100)
        XCTAssertEqual(inverted.coverage(x: 50, y: 50), 0)   // exactly 0 deep inside
        XCTAssertEqual(inverted.coverage(x: 1, y: 1), 1)
        XCTAssertEqual(inverted.coverage(x: 50, y: 0.25) + plain.coverage(x: 50, y: 0.25), 1, accuracy: 1e-12)
        // Feather 0.1 of S = 100 → band 11 px, monotonic from −5.5 to +5.5.
        let soft = try mask(.ellipse, feather: 0.1).geometry(width: 100, height: 100)
        XCTAssertEqual(soft.band, 11, accuracy: 1e-12)
        var previous = 1.0
        for k in 0...60 {
            let y: Double = 50 + 40 + Double(k) * 0.25   // d from −10 to +5
            let c = soft.coverage(x: 50, y: y)
            XCTAssertLessThanOrEqual(c, previous)
            previous = c
        }
        XCTAssertEqual(soft.coverage(x: 50, y: 50 + 50 - 5.5), 1)
        XCTAssertEqual(soft.coverage(x: 50, y: 50 + 50 + 5.5), 0)
        XCTAssertEqual(soft.coverage(x: 50, y: 50 + 50 + 5.4), LayerMaskGeometry.coverage(distance: 5.4, band: 11, inverted: false),
                       accuracy: 1e-12)
        XCTAssertGreaterThan(soft.coverage(x: 50, y: 50 + 50 + 5.4), 0)
    }

    func testMaskTransformMovesScalesAndRotatesTheShape() throws {
        // Centre at (0.25, 0.75) of 200 × 100 → (50, 75) px; scale (0.4, 0.2) of S = 100 → 40 × 20 box;
        // rotated a quarter turn clockwise → the long axis is vertical.
        let t = LayerMaskTransform(center: LayerPoint(x: 0.25, y: 0.75), scale: LayerPoint(x: 0.4, y: 0.2), rotation: Double.pi / 2)
        let g = try mask(.rectangle(cornerRadius: 0), t).geometry(width: 200, height: 100)
        XCTAssertEqual(g.signedDistance(x: 50, y: 75), -10, accuracy: 1e-9)
        XCTAssertEqual(g.signedDistance(x: 50, y: 95), 0, accuracy: 1e-9)    // long axis now vertical (half 20)
        XCTAssertEqual(g.signedDistance(x: 60, y: 75), 0, accuracy: 1e-9)    // short axis horizontal (half 10)
        XCTAssertGreaterThan(g.signedDistance(x: 70, y: 75), 0)
        // Clockwise: a point on the local +x axis lands below the centre (y down).
        let q = g.local(x: 50, y: 85)
        XCTAssertEqual(q.x, 10, accuracy: 1e-9)
        XCTAssertEqual(q.y, 0, accuracy: 1e-9)
    }

    func testAMaskThatCoversNothingNearby() throws {
        let tiny = LayerMaskTransform(center: LayerPoint(x: 5, y: 5), scale: LayerPoint(x: 0.01, y: 0.01))
        let g = try mask(.ellipse, tiny).geometry(width: 64, height: 64)
        let gi = try mask(.ellipse, tiny, inverted: true).geometry(width: 64, height: 64)
        XCTAssertEqual(g.coverage(x: 32, y: 32), 0)
        XCTAssertEqual(gi.coverage(x: 32, y: 32), 1)
    }

    func testClampingAndRefusals() throws {
        let t = LayerMaskTransform(center: LayerPoint(x: 50, y: .nan), scale: LayerPoint(x: 0, y: 99), rotation: -0.0)
        XCTAssertEqual(t.center, LayerPoint(x: 10, y: 0.5))
        XCTAssertEqual(t.scale, LayerPoint(x: 0.01, y: 20))
        XCTAssertEqual(t.rotation.sign, .plus)
        let m = try mask(.polygon([LayerPoint(x: -20, y: 0), LayerPoint(x: 0, y: 1), LayerPoint(x: 1, y: 0)]), feather: 5)
        XCTAssertEqual(m.feather, 1)
        XCTAssertEqual(m.shape, .polygon([LayerPoint(x: -10, y: 0), LayerPoint(x: 0, y: 1), LayerPoint(x: 1, y: 0)]))
        XCTAssertEqual(try mask(.rectangle(cornerRadius: .infinity)).shape, .rectangle(cornerRadius: 0))
        let two = [LayerPoint(x: 0, y: 0), LayerPoint(x: 1, y: 1)]
        XCTAssertThrowsError(try mask(.polygon(two))) { XCTAssertEqual($0 as? LayerMaskError, .tooFewPoints(2)) }
        let many = (0..<33).map { (k: Int) -> LayerPoint in LayerPoint(x: cos(Double(k)), y: sin(Double(k))) }
        XCTAssertThrowsError(try mask(.polygon(many))) { XCTAssertEqual($0 as? LayerMaskError, .tooManyPoints(33)) }
        XCTAssertNoThrow(try mask(.polygon(Array(many.prefix(32)))))
        let line = [LayerPoint(x: 0, y: 0), LayerPoint(x: 0.1, y: 0.1), LayerPoint(x: 0.3, y: 0.3)]
        XCTAssertThrowsError(try mask(.polygon(line))) { XCTAssertEqual($0 as? LayerMaskError, .zeroArea) }
        let bad = [LayerPoint(x: 0, y: 0), LayerPoint(x: .nan, y: 0.1), LayerPoint(x: 0.3, y: 0)]
        XCTAssertThrowsError(try mask(.polygon(bad))) { XCTAssertEqual($0 as? LayerMaskError, .nonFinitePoint) }
        XCTAssertEqual(LayerMask.maximumPolygonPoints, 32)
    }
}
