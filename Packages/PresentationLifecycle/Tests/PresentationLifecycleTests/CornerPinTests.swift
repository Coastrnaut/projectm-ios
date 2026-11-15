// CornerPinTests.swift — OUT-007-T02 (specs/264-out-007-corner-pin, contract C1): the acceptance "Four
// reference points map to specified quadrilateral with no foldover", on representative quads (owner rule 7).
import PresentationLifecycle
import XCTest

final class CornerPinTests: XCTestCase {
    private func p(_ x: Double, _ y: Double) -> CornerPinPoint { CornerPinPoint(x: x, y: y) }

    /// Keystone, rotation-like, perspective and a parallelogram: all valid.
    private var validQuads: [[CornerPinPoint]] {
        [[p(0.1, 0.05), p(0.92, 0), p(1, 1), p(0, 0.95)],
         [p(0.05, 0.1), p(0.9, 0.02), p(0.98, 0.85), p(0.12, 0.97)],
         [p(-0.3, -0.2), p(1.4, 0.1), p(1.1, 1.3), p(0.2, 1.05)],
         [p(0.1, 0.1), p(0.9, 0.2), p(0.9, 0.9), p(0.1, 0.8)]]
    }

    private let unitCorners: [(Double, Double)] = [(0, 0), (1, 0), (1, 1), (0, 1)]

    /// S1: the four unit corners map to the specified quad corners within 1e-9.
    func testTheFourCornersMapToTheSpecifiedQuadrilateral() throws {
        for quad in validQuads {
            let pin = try XCTUnwrap(CornerPin(topLeft: quad[0], topRight: quad[1], bottomRight: quad[2], bottomLeft: quad[3]))
            let h: Homography = pin.homography
            for (i, corner) in unitCorners.enumerated() {
                let mapped: CornerPinPoint = h.map(x: corner.0, y: corner.1)
                XCTAssertEqual(mapped.x, quad[i].x, accuracy: 1e-9)
                XCTAssertEqual(mapped.y, quad[i].y, accuracy: 1e-9)
            }
        }
    }

    /// S2: interior points land inside the quad (inside every edge, same orientation as the square).
    func testInteriorPointsMapInsideTheQuad() throws {
        for quad in validQuads {
            let h: Homography = CornerPin.candidate(quad).homography
            for u in stride(from: 0.05, through: 0.95, by: 0.15) {
                for v in stride(from: 0.05, through: 0.95, by: 0.15) {
                    let m: CornerPinPoint = h.map(x: u, y: v)
                    for i in 0..<4 {
                        let a: CornerPinPoint = quad[i], b: CornerPinPoint = quad[(i + 1) % 4]
                        let side: Double = (b.x - a.x) * (m.y - a.y) - (b.y - a.y) * (m.x - a.x)
                        XCTAssertGreaterThan(side, 0, "(\(u), \(v)) is inside edge \(i)")
                    }
                }
            }
        }
    }

    func testIdentityIsIdentity() {
        let h: Homography = CornerPin.identity.homography
        XCTAssertEqual(h, Homography.identity)
        XCTAssertTrue(CornerPin.identity.isValid && CornerPin.identity.isIdentity)
        for (u, v) in [(0.0, 0.0), (0.3, 0.7), (1.0, 1.0), (0.5, 0.25)] {
            let m: CornerPinPoint = h.map(x: u, y: v)
            XCTAssertEqual(m.x, u, accuracy: 1e-12)
            XCTAssertEqual(m.y, v, accuracy: 1e-12)
        }
        let matrix: [Double] = h.layerMatrix(width: 1920, height: 1080, anchorX: 960, anchorY: 540)
        for (value, expected) in zip(matrix, Homography.identityMatrix) { XCTAssertEqual(value, expected, accuracy: 1e-12) }
    }

    /// S3: concave, bow-tie, collinear, tiny, mirrored and out-of-range quads are rejected.
    func testFoldingAndDegenerateQuadsAreRejected() {
        let cases: [(String, [CornerPinPoint], CornerPin.Validity)] = [
            ("concave", [p(0, 0), p(1, 0), p(0.4, 0.4), p(0, 1)], .notConvex),
            ("bow-tie", [p(0, 0), p(1, 0), p(0, 1), p(1, 1)], .notConvex),
            ("mirrored", [p(1, 0), p(0, 0), p(0, 1), p(1, 1)], .notConvex),
            ("collinear", [p(0, 0), p(0.5, 0.01), p(1, 0.02), p(0, 1)], .collinear),
            ("coincident", [p(0, 0), p(0, 0), p(1, 1), p(0, 1)], .collinear),
            ("tiny", [p(0.4, 0.4), p(0.6, 0.4), p(0.6, 0.6), p(0.4, 0.6)], .tooSmall),
            ("out of range", [p(-0.6, 0), p(1, 0), p(1, 1), p(0, 1)], .outOfRange),
        ]
        for (name, quad, expected) in cases {
            XCTAssertEqual(CornerPin.candidate(quad).validity, expected, name)
            XCTAssertNil(CornerPin(topLeft: quad[0], topRight: quad[1], bottomRight: quad[2], bottomLeft: quad[3]), name)
        }
    }

    /// S2: a dense grid keeps its orientation everywhere (positive Jacobian determinant) for valid quads.
    func testValidQuadsPreserveOrientationOnADenseGrid() {
        for quad in validQuads {
            let h: Homography = CornerPin.candidate(quad).homography
            for i in 0...40 {
                for j in 0...40 {
                    let u = Double(i) / 40, v = Double(j) / 40
                    XCTAssertGreaterThan(h.jacobianDeterminant(x: u, y: v), 0, "(\(u), \(v))")
                }
            }
        }
    }

    /// OUT-007-R4: edits clamp to the range and are refused when the result would fold.
    func testEditsAreClampedOrRefused() {
        let pin: CornerPin = .identity
        let moved: CornerPin = pin.moving(.topLeft, to: p(0.1, 0.05))
        XCTAssertEqual(moved.point(.topLeft), p(0.1, 0.05))
        XCTAssertEqual(pin.moving(.topLeft, to: p(1.2, 1.2)), pin, "a drag across the opposite edge is refused")
        XCTAssertEqual(pin.moving(.bottomRight, to: p(9, 9)).point(.bottomRight), p(1.5, 1.5), "clamped to the range")
        let nudged: CornerPin = pin.nudging(.topRight, dx: -CornerPin.nudgeStep, dy: CornerPin.nudgeStep)
        XCTAssertEqual(nudged.point(.topRight).x, 1 - CornerPin.nudgeStep, accuracy: 1e-12)
        XCTAssertEqual(nudged.point(.topRight).y, CornerPin.nudgeStep, accuracy: 1e-12)
    }

    /// The Core Animation matrix, applied about the layer's anchor, lands the layer's corners on the quad.
    func testTheLayerMatrixProjectsTheCornersOntoTheQuad() {
        let width = 1920.0, height = 1080.0
        for quad in validQuads {
            let m: [Double] = CornerPin.candidate(quad).homography.layerMatrix(width: width, height: height,
                                                                                anchorX: width / 2, anchorY: height / 2)
            for (i, corner) in unitCorners.enumerated() {
                let r: CornerPinPoint = Homography.project(m, x: corner.0 * width, y: corner.1 * height,
                                                           anchorX: width / 2, anchorY: height / 2)
                XCTAssertEqual(r.x, quad[i].x * width, accuracy: 1e-6)
                XCTAssertEqual(r.y, quad[i].y * height, accuracy: 1e-6)
            }
        }
    }

    /// S5: the stored value round-trips; malformed or invalid values read nil.
    func testTheStoredValueRoundTripsAndRejectsBadInput() throws {
        let pin = try XCTUnwrap(CornerPin(topLeft: p(0.1, 0.05), topRight: p(0.92, 0), bottomRight: p(1, 1), bottomLeft: p(0, 0.95)))
        XCTAssertEqual(pin.stored, "0.1,0.05;0.92,0;1,1;0,0.95")
        XCTAssertEqual(CornerPin(stored: pin.stored), pin)
        XCTAssertEqual(CornerPin(stored: CornerPin.identity.stored), .identity)
        for bad in ["", "1,2,3", "0,0;1,0;1,1", "0,0;1,0;1,1;0,x", "0,0;1,0;0,1;1,1", "0,0;1,0;1,1;0,1;0,0", "nan,0;1,0;1,1;0,1"] {
            XCTAssertNil(CornerPin(stored: bad), bad)
        }
    }
}
