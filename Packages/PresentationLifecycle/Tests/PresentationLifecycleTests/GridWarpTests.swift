// GridWarpTests.swift — OUT-008-T02 (spec specs/309-out-008-grid-warp, contract C1; OUT-008-S3): the grid warp's
// surface, every validity rule with an example, edits, resampling, the stored form, and seeded random meshes. For every
// accepted random mesh an independent invariant holds: the drawn triangles' areas add up to the area inside the drawn
// outline (any fold or overlap would cover some area twice). A few representative cases (owner rule 7).
import Foundation
import XCTest
@testable import PresentationLifecycle

final class GridWarpTests: XCTestCase {
    private static func p(_ x: Double, _ y: Double) -> GridWarpPoint { GridWarpPoint(x: x, y: y) }

    /// The identity of a size moved by an affine map (x, y) → (a·x + b·y + e, c·x + d·y + f).
    private static func affine(_ columns: Int, _ rows: Int, _ m: (Double, Double, Double, Double, Double, Double)) -> GridWarp {
        let points: [GridWarpPoint] = GridWarp.identity(columns: columns, rows: rows).points.map { (q: GridWarpPoint) -> GridWarpPoint in
            p(m.0 * q.x + m.1 * q.y + m.4, m.2 * q.x + m.3 * q.y + m.5)
        }
        return GridWarp.candidate(columns: columns, rows: rows, points: points)
    }

    private static func replacing(_ w: GridWarp, row: Int, column: Int, with q: GridWarpPoint) -> GridWarp {
        var points: [GridWarpPoint] = w.points
        points[row * w.columns + column] = q
        return GridWarp.candidate(columns: w.columns, rows: w.rows, points: points)
    }

    // MARK: Surface

    func testTheIdentityMapsEveryDrawnVertexToItself() {
        for size in [(3, 3), (5, 4), (9, 9)] {
            let w: GridWarp = .identity(columns: size.0, rows: size.1)
            XCTAssertTrue(w.isIdentity)
            XCTAssertEqual(w.validity, .valid)
            for j in stride(from: 0, to: w.latticeRows, by: 3) {
                for i in stride(from: 0, to: w.latticeColumns, by: 3) {
                    let q: GridWarpPoint = w.latticePoint(i: i, j: j)
                    XCTAssertEqual(q.x, Double(i) / Double(w.latticeColumns - 1), accuracy: 1e-12)
                    XCTAssertEqual(q.y, Double(j) / Double(w.latticeRows - 1), accuracy: 1e-12)
                }
            }
        }
    }

    func testAffineGridsAreReproducedExactlyAndControlPointsAreHit() {
        let w = Self.affine(4, 3, (0.7, 0.1, -0.05, 0.8, 0.1, 0.12))
        XCTAssertEqual(w.validity, .valid)
        for (u, v) in [(0.0, 0.0), (0.13, 0.77), (0.5, 0.5), (0.99, 0.31), (1.0, 1.0)] {
            let q: GridWarpPoint = w.map(u: u, v: v)
            XCTAssertEqual(q.x, 0.7 * u + 0.1 * v + 0.1, accuracy: 1e-12)
            XCTAssertEqual(q.y, -0.05 * u + 0.8 * v + 0.12, accuracy: 1e-12)
        }
        let bent = Self.replacing(.identity(columns: 5, rows: 5), row: 2, column: 2, with: Self.p(0.56, 0.47))
        XCTAssertEqual(bent.validity, .valid)
        for r in 0..<5 {
            for c in 0..<5 {
                let q: GridWarpPoint = bent.map(u: Double(c) / 4, v: Double(r) / 4)
                XCTAssertEqual(q.x, bent.point(row: r, column: c).x, accuracy: 1e-12, "passes through (\(r), \(c))")
                XCTAssertEqual(q.y, bent.point(row: r, column: c).y, accuracy: 1e-12)
            }
        }
        let fast: [GridWarpPoint] = bent.lattice
        for k in stride(from: 0, to: fast.count, by: 37) {
            let slow: GridWarpPoint = bent.latticePoint(i: k % bent.latticeColumns, j: k / bent.latticeColumns)
            XCTAssertEqual(fast[k].x, slow.x, accuracy: 1e-12, "the validator's lattice is the drawn surface")
            XCTAssertEqual(fast[k].y, slow.y, accuracy: 1e-12)
        }
    }

    // MARK: Rules

    func testEachRuleRejectsItsExample() {
        let id: GridWarp = .identity
        XCTAssertEqual(GridWarp.candidate(columns: 2, rows: 3, points: Array(id.points.prefix(6))).validity, .badSize)
        XCTAssertEqual(GridWarp.candidate(columns: 10, rows: 3, points: Array(repeating: Self.p(0, 0), count: 30)).validity, .badSize)
        XCTAssertEqual(GridWarp.candidate(columns: 3, rows: 3, points: Array(id.points.prefix(8))).validity, .badSize)
        XCTAssertEqual(Self.replacing(id, row: 1, column: 1, with: Self.p(.nan, 0.5)).validity, .nonFinite)
        XCTAssertEqual(Self.replacing(id, row: 1, column: 1, with: Self.p(0.5, .infinity)).validity, .nonFinite)
        XCTAssertEqual(Self.replacing(id, row: 0, column: 2, with: Self.p(1.6, 0)).validity, .outOfRange)
        // Swapping two neighbours crosses their cells.
        var swapped: [GridWarpPoint] = id.points
        swapped.swapAt(0, 1)
        XCTAssertEqual(GridWarp.candidate(columns: 3, rows: 3, points: swapped).validity, .cellFolded(row: 0, column: 0))
        // The centre on the top-left cell's diagonal: three of its corners in a line.
        XCTAssertEqual(Self.replacing(id, row: 1, column: 1, with: Self.p(0.25, 0.25)).validity, .cellDegenerate(row: 0, column: 0))
        // Valid cells, but a narrow cell between wide ones makes the smooth curve run backwards.
        let narrow = GridWarp.candidate(columns: 4, rows: 3, points: [0.0, 0.5, 1.0].flatMap { (y: Double) -> [GridWarpPoint] in
            [Self.p(0, y), Self.p(0.45, y), Self.p(0.46, y), Self.p(1, y)]
        })
        XCTAssertEqual(narrow.validity, .surfaceFolds)
        XCTAssertEqual(Self.ring().validity, .outlineCrosses)
        XCTAssertEqual(Self.affine(3, 3, (0.2, 0, 0, 0.2, 0.4, 0.4)).validity, .tooSmall)
        XCTAssertEqual(Self.affine(3, 3, (0.25, 0, 0, 0.25, 0.4, 0.4)).validity, .valid, "6.25 % is enough")
    }

    /// 9 × 3 points bent into a ring that turns 396°: every cell and triangle is fine, the outline overlaps itself.
    private static func ring() -> GridWarp {
        var points: [GridWarpPoint] = []
        for r in 0..<3 {
            let radius: Double = 0.35 + 0.15 * Double(r)
            for c in 0..<9 {
                let angle: Double = -Double(c) * 2 * Double.pi * 1.1 / 8
                points.append(p(0.5 + radius * cos(angle), 0.5 + radius * sin(angle)))
            }
        }
        return GridWarp.candidate(columns: 9, rows: 3, points: points)
    }

    // MARK: Edits, resampling, stored form

    func testEditsClampOrAreRefusedWithTheirReason() {
        let id: GridWarp = .identity
        guard case .applied(let nudged) = id.nudging(row: 1, column: 1, dx: GridWarp.nudgeStep, dy: 0) else {
            return XCTFail("a small nudge applies")
        }
        XCTAssertEqual(nudged.point(row: 1, column: 1).x, 0.505, accuracy: 1e-12)
        XCTAssertEqual(id.moving(row: 1, column: 1, to: Self.p(1, 0)), .refused(.cellFolded(row: 0, column: 1)))
        guard case .applied(let clamped) = id.moving(row: 0, column: 0, to: Self.p(-3, 0)) else {
            return XCTFail("clamped to the range, still valid")
        }
        XCTAssertEqual(clamped.point(row: 0, column: 0).x, -0.5)
        XCTAssertEqual(id.moving(row: 3, column: 0, to: Self.p(0, 0)), .refused(.badSize), "no such point")
    }

    func testResamplingKeepsTheShapeOrFallsBackToTheIdentity() {
        XCTAssertEqual(GridWarp.identity.resampled(columns: 5, rows: 5), .identity(columns: 5, rows: 5))
        let m = (0.8, 0.0, 0.05, 0.9, 0.1, 0.02)
        let resampled: GridWarp = Self.affine(3, 3, m).resampled(columns: 9, rows: 5)
        let expected: GridWarp = Self.affine(9, 5, m)
        XCTAssertEqual(resampled.columns, 9)
        for (a, b) in zip(resampled.points, expected.points) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testTheStoredFormRoundTripsAndRefusesBadValues() throws {
        let w = try XCTUnwrap(GridWarp(columns: 3, rows: 3, points: Self.replacing(.identity, row: 1, column: 1,
                                                                                    with: Self.p(0.55, 0.45)).points))
        XCTAssertEqual(w.stored, "3x3:0,0;0.5,0;1,0;0,0.5;0.55,0.45;1,0.5;0,1;0.5,1;1,1")
        XCTAssertEqual(GridWarp(stored: w.stored), w)
        var swapped: [GridWarpPoint] = GridWarp.identity.points
        swapped.swapAt(0, 1)
        let folded: String = GridWarp.candidate(columns: 3, rows: 3, points: swapped).stored
        for bad in ["", "3x3", "3x3:", "2x3:0,0;1,0;0,0.5;1,0.5;0,1;1,1", "3x3:0,0;0.5,0", "3by3:" + w.stored.dropFirst(4),
                    w.stored.replacingOccurrences(of: "0.55", with: "nan"), w.stored + ";1,1", folded] {
            XCTAssertNil(GridWarp(stored: bad), bad)
        }
    }

    // MARK: Random meshes (OUT-008-S3)

    func testRandomMeshesAcceptedByTheValidatorNeverFold() {
        var state: UInt64 = 0x0308_2026_1115
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        var accepted = 0, refused = 0
        for k in 0..<240 {
            let amplitude: Double = 0.3 * Double(k % 12) / 11
            let base: GridWarp = .identity(columns: 5, rows: 5)
            let points: [GridWarpPoint] = base.points.map { (q: GridWarpPoint) -> GridWarpPoint in
                Self.p(q.x + amplitude * (next() - 0.5), q.y + amplitude * (next() - 0.5))
            }
            let w = GridWarp.candidate(columns: 5, rows: 5, points: points)
            guard w.isValid else { refused += 1; continue }
            accepted += 1
            let drawn: [GridWarpPoint] = w.lattice
            let width: Int = w.latticeColumns
            var sum = 0.0
            for j in 0..<(w.latticeRows - 1) {
                for i in 0..<(width - 1) {
                    let a = drawn[j * width + i], b = drawn[j * width + i + 1]
                    let c = drawn[(j + 1) * width + i + 1], d = drawn[(j + 1) * width + i]
                    sum += abs(GridWarp.cross(a, b, d)) / 2 + abs(GridWarp.cross(b, c, d)) / 2
                }
            }
            let inside: Double = GridWarp.area(GridWarp.outline(drawn, columns: width, rows: w.latticeRows))
            XCTAssertEqual(sum, inside, accuracy: 1e-9, "mesh \(k) covers no area twice")
            XCTAssertEqual(GridWarp(stored: w.stored)?.columns, 5, "an accepted mesh survives its stored form")
        }
        XCTAssertGreaterThan(accepted, 40)
        XCTAssertGreaterThan(refused, 40)
    }
}
