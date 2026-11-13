// CMP-005-T05 (US1, the roadmap acceptance "Saving and reloading reproduces a test transform matrix";
// CMP-005-S1, S2): the transform model, its matrix and its saved form. CPU only, so it also runs in
// the Linux shape.
import Compositor
import Foundation
import XCTest

/// SplitMix64: a fixed-seed generator so the 1,000 round-trip cases are the same on every run.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The saved form read back field by field (checks the documented names and the version).
private struct SavedShape: Decodable {
    struct XY: Decodable { let x: Double; let y: Double }
    let version: Int
    let translation: XY
    let scale: XY
    let rotation: Double
    let anchor: XY
}

final class LayerTransformTests: XCTestCase {
    private func p(_ x: Double, _ y: Double) -> LayerPoint { LayerPoint(x: x, y: y) }

    /// The acceptance's test transform: a move, a non-uniform scale and a rotation about a
    /// non-centre anchor.
    private func testTransform() throws -> LayerTransform {
        try LayerTransform(translation: p(0.125, -0.25), scale: p(1.5, 0.75), rotation: 0.3, anchor: p(0.2, 0.8))
    }

    private func bits(_ m: LayerTransformMatrix) -> [UInt64] { m.rows.flatMap { $0 }.map(\.bitPattern) }

    private func roundTrip(_ t: LayerTransform) throws -> LayerTransform {
        try JSONDecoder().decode(LayerTransform.self, from: try JSONEncoder().encode(t))
    }

    private func decode(_ json: String) throws -> LayerTransform {
        try JSONDecoder().decode(LayerTransform.self, from: Data(json.utf8))
    }

    private func assertClose(_ a: LayerPoint, _ b: LayerPoint, _ message: String, tolerance: Double = 1e-12,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: tolerance, "\(message) (x)", file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: tolerance, "\(message) (y)", file: file, line: line)
    }

    // MARK: - The acceptance

    func testSavingAndReloadingReproducesTheTestMatrix() throws {
        let original = try testTransform()
        let matrix = original.matrix(outputWidth: 64, outputHeight: 32)
        let reloaded = try roundTrip(original)
        XCTAssertEqual(reloaded, original)
        let again = reloaded.matrix(outputWidth: 64, outputHeight: 32)
        XCTAssertEqual(bits(again), bits(matrix), "all 9 elements bit for bit")
        XCTAssertEqual(again.rows.count, 3)
        XCTAssertEqual(again.rows[2], [0, 0, 1])
        // Not trivially the identity: the test matrix moves, scales and rotates.
        XCTAssertNotEqual(matrix, .identity)
        XCTAssertEqual(matrix.m00, cos(0.3) * 1.5)
    }

    func testThousandArbitraryTransformsRoundTripBitForBit() throws {
        var rng = SplitMix64(state: 0xC0FF_EE05)
        var cases: [LayerTransform] = []
        for _ in 0..<1000 {
            cases.append(try LayerTransform(
                translation: p(Double.random(in: -10...10, using: &rng), Double.random(in: -10...10, using: &rng)),
                scale: p(exp(Double.random(in: log(0.05)...log(20), using: &rng)), exp(Double.random(in: log(0.05)...log(20), using: &rng))),
                rotation: Double.random(in: -20...20, using: &rng),
                anchor: p(Double.random(in: -10...10, using: &rng), Double.random(in: -10...10, using: &rng))))
        }
        // Edge values: bounds, −0, decimals with no exact binary form, irrational angles.
        cases.append(try LayerTransform(translation: p(-0.0, 0.1), scale: p(0.05, 20), rotation: -0.0, anchor: p(-10, 10)))
        cases.append(try LayerTransform(translation: p(1.0 / 3, -2.0 / 3), uniformScale: 0.1, rotation: .pi / 7, anchor: p(0.3, 0.7)))
        cases.append(try LayerTransform(translation: p(Double.ulpOfOne, -Double.leastNonzeroMagnitude), scale: p(1 + Double.ulpOfOne, 0.05000000000000001),
                                        rotation: 1e300, anchor: p(0.5, 0.5)))
        var aspects = rng
        for t in cases {
            let back = try roundTrip(t)
            XCTAssertEqual(back, t)
            XCTAssertEqual([back.translation.x, back.translation.y, back.scale.x, back.scale.y, back.rotation, back.anchor.x, back.anchor.y].map(\.bitPattern),
                           [t.translation.x, t.translation.y, t.scale.x, t.scale.y, t.rotation, t.anchor.x, t.anchor.y].map(\.bitPattern))
            let aspect = Double.random(in: 0.25...4, using: &aspects)
            XCTAssertEqual(bits(back.matrix(aspect: aspect)), bits(t.matrix(aspect: aspect)))
        }
    }

    func testSavedFormHasTheDocumentedFieldsAndVersion() throws {
        let data = try JSONEncoder().encode(try testTransform())
        let saved = try JSONDecoder().decode(SavedShape.self, from: data)
        XCTAssertEqual(saved.version, 1)
        XCTAssertEqual(saved.translation.x, 0.125)
        XCTAssertEqual(saved.translation.y, -0.25)
        XCTAssertEqual(saved.scale.x, 1.5)
        XCTAssertEqual(saved.scale.y, 0.75)
        XCTAssertEqual(saved.rotation, 0.3)
        XCTAssertEqual(saved.anchor.x, 0.2)
        XCTAssertEqual(saved.anchor.y, 0.8)
        let identity = try JSONDecoder().decode(SavedShape.self, from: try JSONEncoder().encode(LayerTransform.identity))
        XCTAssertEqual(identity.anchor.x, 0.5, "every field is written, defaults included")
    }

    func testDecodingDefaultsClampsAndRefusesOtherVersions() throws {
        XCTAssertEqual(try decode(#"{"version":1}"#), .identity, "missing fields read identity values")
        let partial = try decode(#"{"version":1,"rotation":1.25}"#)
        XCTAssertEqual(partial.rotation, 1.25)
        XCTAssertEqual(partial.anchor, p(0.5, 0.5))
        let clamped = try decode(#"{"version":1,"translation":{"x":50,"y":-50},"scale":{"x":100,"y":0.001},"anchor":{"x":-11,"y":0.5}}"#)
        XCTAssertEqual(clamped.translation, p(10, -10))
        XCTAssertEqual(clamped.scale, p(20, 0.05))
        XCTAssertEqual(clamped.anchor, p(-10, 0.5))
        XCTAssertThrowsError(try decode(#"{"version":2,"rotation":1}"#), "a newer format is refused")
        XCTAssertThrowsError(try decode(#"{"rotation":1}"#), "the version is required")
    }

    // MARK: - Validation

    func testNonFiniteValuesAreRefusedAndFiniteOnesClamped() throws {
        XCTAssertThrowsError(try LayerTransform(translation: p(.nan, 0))) { XCTAssertEqual($0 as? LayerTransformError, .nonFiniteTranslation) }
        XCTAssertThrowsError(try LayerTransform(scale: p(1, .infinity))) { XCTAssertEqual($0 as? LayerTransformError, .nonFiniteScale) }
        XCTAssertThrowsError(try LayerTransform(rotation: -.infinity)) { XCTAssertEqual($0 as? LayerTransformError, .nonFiniteRotation) }
        XCTAssertThrowsError(try LayerTransform(anchor: p(0, .nan))) { XCTAssertEqual($0 as? LayerTransformError, .nonFiniteAnchor) }
        XCTAssertThrowsError(try LayerTransform(uniformScale: .nan)) { XCTAssertEqual($0 as? LayerTransformError, .nonFiniteScale) }
        let t = try LayerTransform(translation: p(12, -0.5), scale: p(-1, 30), rotation: 100, anchor: p(0.5, -40))
        XCTAssertEqual(t.translation, p(10, -0.5))
        XCTAssertEqual(t.scale, p(0.05, 20), "no mirroring: a negative scale clamps to the minimum")
        XCTAssertEqual(t.rotation, 100, "rotation is kept as given")
        XCTAssertEqual(t.anchor, p(0.5, -10))
        let zero = try LayerTransform(translation: p(-0.0, -0.0), rotation: -0.0)
        XCTAssertEqual(zero.translation.x.sign, .plus, "−0 is stored as 0")
        XCTAssertEqual(zero.rotation.sign, .plus)
    }

    // MARK: - Matrix rules (CMP-005-R2, R3; S2)

    func testIdentityIsExactForAnyAnchorAndAspect() throws {
        for anchor in [p(0.5, 0.5), p(0, 0), p(0.2, 0.9), p(-3, 7)] {
            let t = try LayerTransform(anchor: anchor)
            XCTAssertTrue(t.isIdentity)
            for aspect in [1.0, 2.0, 0.5625, 16.0 / 9.0] {
                XCTAssertEqual(t.matrix(aspect: aspect), .identity, "anchor \(anchor), aspect \(aspect)")
            }
        }
        XCTAssertTrue(LayerTransform.identity.isIdentity)
        XCTAssertFalse(try LayerTransform(rotation: 0.01).isIdentity)
        XCTAssertFalse(try LayerTransform(uniformScale: 2).isIdentity)
        XCTAssertFalse(try LayerTransform(translation: p(0, 0.1)).isIdentity)
        XCTAssertEqual(LayerTransform.identity.matrix(aspect: .nan), .identity, "a non-finite aspect reads 1")
    }

    func testAnchorLandsAtItsPositionPlusTheMove() throws {
        let t = try testTransform()
        for aspect in [1.0, 2.0, 0.75] {
            assertClose(t.matrix(aspect: aspect).apply(t.anchor), p(0.2 + 0.125, 0.8 - 0.25), "aspect \(aspect)")
        }
    }

    func testOrderIsScaleThenRotateAboutTheAnchorThenMove() throws {
        let t = try testTransform()
        let a = 2.0
        func m(_ m00: Double, _ m01: Double, _ m02: Double, _ m10: Double, _ m11: Double, _ m12: Double) -> LayerTransformMatrix {
            LayerTransformMatrix(m00: m00, m01: m01, m02: m02, m10: m10, m11: m11, m12: m12)
        }
        let stretch = m(a, 0, 0, 0, 1, 0)
        let unstretch = m(1 / a, 0, 0, 0, 1, 0)
        let anchor = stretch.apply(t.anchor)
        let toOrigin = m(1, 0, -anchor.x, 0, 1, -anchor.y)
        let back = m(1, 0, anchor.x, 0, 1, anchor.y)
        let scale = m(1.5, 0, 0, 0, 0.75, 0)
        let rotate = m(cos(0.3), -sin(0.3), 0, sin(0.3), cos(0.3), 0)
        let move = m(1, 0, 0.125, 0, 1, -0.25)
        let product = move * unstretch * back * rotate * scale * toOrigin * stretch
        let matrix = t.matrix(aspect: a)
        for (x, y) in zip(product.rows.flatMap { $0 }, matrix.rows.flatMap { $0 }) { XCTAssertEqual(x, y, accuracy: 1e-12) }
        // The other order (rotate before scale) differs for a non-uniform scale.
        let swapped = move * unstretch * back * scale * rotate * toOrigin * stretch
        XCTAssertGreaterThan(Swift.abs(swapped.m01 - matrix.m01), 1e-3)
    }

    func testQuarterTurnKeepsPixelLengthsOnANonSquareOutput() throws {
        // 64 × 32 output: 16 px to the right of the centre turns to 16 px below it (positive angle:
        // +x towards +y, clockwise on screen).
        let t = try LayerTransform(rotation: .pi / 2)
        let m = t.matrix(outputWidth: 64, outputHeight: 32)
        func pixels(_ q: LayerPoint) -> LayerPoint { p(q.x * 64, q.y * 32) }
        assertClose(pixels(m.apply(p(0.5, 0.5))), p(32, 16), "the centre stays", tolerance: 1e-9)
        assertClose(pixels(m.apply(p(0.5 + 16.0 / 64, 0.5))), p(32, 32), "right turns to down, same length", tolerance: 1e-9)
        assertClose(pixels(m.apply(p(0.5, 0.5 + 8.0 / 32))), p(24, 16), "down turns to left, same length", tolerance: 1e-9)
    }

    func testInverseAndComposition() throws {
        let m = try testTransform().matrix(aspect: 16.0 / 9.0)
        let inverse = try XCTUnwrap(m.inverse)
        for (x, y) in zip((m * inverse).rows.flatMap { $0 }, LayerTransformMatrix.identity.rows.flatMap { $0 }) {
            XCTAssertEqual(x, y, accuracy: 1e-12)
        }
        let point = p(0.37, -1.2)
        assertClose(inverse.apply(m.apply(point)), point, "inverse undoes the matrix")
        let other = try LayerTransform(translation: p(-0.3, 0.1), uniformScale: 0.4, rotation: -2).matrix(aspect: 1)
        assertClose((m * other).apply(point), m.apply(other.apply(point)), "(A * B)(p) = A(B(p))")
        XCTAssertNil(LayerTransformMatrix(m00: 0, m01: 0, m02: 1, m10: 0, m11: 0, m12: 1).inverse)
        // The smallest scale stays invertible.
        XCTAssertNotNil(try LayerTransform(uniformScale: 0).matrix(aspect: 3).inverse)
    }
}
