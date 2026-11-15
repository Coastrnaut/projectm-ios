// SHD-008-T03: path validation (contract P1), coding and sampling (SHD-008-R1, R2, S1, S2).
import Foundation
import VisualGenerators
import XCTest

final class VectorPathTests: XCTestCase {
    static func pts(_ xy: [(Double, Double)]) -> [VectorPoint] {
        xy.map { (p: (Double, Double)) -> VectorPoint in VectorPoint(x: p.0, y: p.1) }
    }

    static let arrow = pts([(0.1, 0.1), (0.9, 0.5), (0.1, 0.9), (0.5, 0.5)])
    static let lShape = pts([(0.1, 0.1), (0.5, 0.1), (0.5, 0.5), (0.9, 0.5), (0.9, 0.9), (0.1, 0.9)])

    private func issue(_ xy: [(Double, Double)]) -> VectorPathIssue? { VectorPath.validate(Self.pts(xy)) }

    private func assertCrosses(_ xy: [(Double, Double)], _ name: String) {
        guard case .crossesItself? = issue(xy) else {
            return XCTFail("\(name): expected crossesItself, got \(String(describing: issue(xy)))")
        }
        XCTAssertThrowsError(try VectorPath(Self.pts(xy)), name)
    }

    func testSelfIntersectingFamiliesAreRejected() {
        assertCrosses([(0.1, 0.1), (0.9, 0.9), (0.9, 0.1), (0.1, 0.9)], "bow-tie")
        assertCrosses([(0.1, 0.1), (0.9, 0.9), (0.9, 0.1), (0.5, 0.05), (0.1, 0.9)], "figure-8, 5 points")
        assertCrosses([(0.1, 0.1), (0.9, 0.1), (0.1, 0.5), (0.9, 0.9), (0.1, 0.9)], "vertex touching an edge")
        assertCrosses([(0.1, 0.1), (0.5, 0.1), (0.5, 0.9), (0.3, 0.9), (0.3, 0.1), (0.2, 0.1)], "collinear overlap")
        assertCrosses([(0.1, 0.1), (0.9, 0.1), (0.5, 0.1), (0.5, 0.9)], "adjacent spike doubling back")
        XCTAssertEqual(VectorPathIssue.crossesItself(0, 2).message, "The path crosses itself.")
    }

    func testConvexAndConcavePathsAreAccepted() throws {
        let square = try VectorPath(Self.pts([(0, 0), (1, 0), (1, 1), (0, 1)]))
        XCTAssertEqual(abs(square.area), 1, accuracy: 1e-12)
        let arrow = try VectorPath(Self.arrow)
        XCTAssertEqual(arrow.triangleCount, 2)
        let l = try VectorPath(Self.lShape)
        XCTAssertEqual(l.triangleCount, 4)
        XCTAssertEqual(abs(l.area), 0.48, accuracy: 1e-12)
        XCTAssertNoThrow(try VectorPath(Self.pts([(0.1, 0.1), (0.5, 0.1), (0.9, 0.1), (0.5, 0.9)])), "collinear neighbours on one edge")
        XCTAssertNil(VectorPath.validate(VectorPath.default.points))
    }

    func testAreaDuplicateRangeAndCountRules() {
        XCTAssertEqual(issue([(0.1, 0.1), (0.9, 0.1), (0.5, 0.10001)]), .tooSmall)
        XCTAssertNil(issue([(0.1, 0.1), (0.9, 0.1), (0.5, 0.11)]), "a thin sliver above the minimum is kept")
        XCTAssertEqual(issue([(0.1, 0.1), (0.1, 0.1), (0.9, 0.9), (0.1, 0.9)]), .duplicatePoint(0))
        XCTAssertEqual(issue([(0.1, 0.1), (0.9, 0.9), (0.1, 0.9), (0.1, 0.1)]), .duplicatePoint(3), "last equals first")
        XCTAssertEqual(issue([(0.1, 0.1), (1.2, 0.5), (0.1, 0.9)]), .outOfRange(1))
        XCTAssertEqual(issue([(0.1, 0.1), (0.5, .nan), (0.1, 0.9)]), .outOfRange(1))
        XCTAssertEqual(issue([(0.1, 0.1), (0.5, 0.5)]), .tooFewPoints(2))
        let many: [(Double, Double)] = (0..<33).map { (k: Int) -> (Double, Double) in
            let a: Double = Double(k) * 2 * Double.pi / 33
            return (0.5 + 0.4 * cos(a), 0.5 + 0.4 * sin(a))
        }
        XCTAssertEqual(issue(many), .tooManyPoints(33))
        XCTAssertNil(issue(Array(many.prefix(32))))
    }

    func testCodingRestoresEveryPointExactlyAndRefusesAnInvalidList() throws {
        let path = try VectorPath(Self.pts([(0.123456789012345, 0.1), (0.987654321098765, 0.33333333333333331), (0.4, 0.9)]))
        let data: Data = try JSONEncoder().encode(path)
        let back: VectorPath = try JSONDecoder().decode(VectorPath.self, from: data)
        XCTAssertEqual(back.points, path.points)
        let bowTie = Data(#"{"points":[{"x":0.1,"y":0.1},{"x":0.9,"y":0.9},{"x":0.9,"y":0.1},{"x":0.1,"y":0.9}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(VectorPath.self, from: bowTie))
    }

    func testSamplesLieInsideAndCoverTheArea() throws {
        let l = try VectorPath(Self.lShape)
        var rng = SystemRandomNumberGenerator()
        var inNotch = 0
        for _ in 0..<2000 {
            let r: [Double] = (0..<3).map { (_: Int) -> Double in Double.random(in: 0...1, using: &rng) }
            let p: VectorPoint = l.sample(r[0], r[1], r[2])
            XCTAssertTrue(l.contains(p) || Self.onBoundary(p), "\(p)")
            if p.x > 0.5 && p.y < 0.5 { inNotch += 1 }
        }
        XCTAssertEqual(inNotch, 0)
        XCTAssertTrue(l.contains(VectorPoint(x: 0.3, y: 0.3)))
        XCTAssertFalse(l.contains(VectorPoint(x: 0.7, y: 0.3)))
    }

    static func onBoundary(_ p: VectorPoint) -> Bool {
        let e: Double = 1e-9
        return abs(p.x - 0.1) < e || abs(p.x - 0.9) < e || abs(p.y - 0.1) < e || abs(p.y - 0.9) < e || abs(p.x - 0.5) < e || abs(p.y - 0.5) < e
    }
}

final class VectorPathDraftTests: XCTestCase {
    private static func p(_ x: Double, _ y: Double) -> VectorPoint { VectorPoint(x: x, y: y) }

    func testABowTieCannotCloseAndATriangleCan() {
        var draft = VectorPathDraft(path: nil)
        XCTAssertEqual(draft.status, "Tap to add points.")
        for q in [Self.p(0.1, 0.1), Self.p(0.9, 0.9), Self.p(0.9, 0.1), Self.p(0.1, 0.9)] { XCTAssertTrue(draft.add(q)) }
        XCTAssertFalse(draft.canClose)
        XCTAssertEqual(draft.status, "The path crosses itself.")
        XCTAssertFalse(draft.close())
        XCTAssertFalse(draft.isClosed)
        XCTAssertNil(draft.committed)
        XCTAssertTrue(draft.removeLast())
        XCTAssertEqual(draft.status, "Ready to close.")
        XCTAssertTrue(draft.close())
        XCTAssertEqual(draft.committed?.points.count, 3)
        XCTAssertEqual(draft.status, "Path closed, 3 points.")
        XCTAssertFalse(draft.add(Self.p(0.5, 0.5)), "no taps once closed")
    }

    func testClosedEditsThatBreakThePathAreRefusedAndTheLastValidPathStays() throws {
        let square = try VectorPath([Self.p(0.1, 0.1), Self.p(0.9, 0.1), Self.p(0.9, 0.9), Self.p(0.1, 0.9)])
        var draft = VectorPathDraft(path: square)
        XCTAssertFalse(draft.move(0, to: Self.p(0.95, 0.5)), "across the opposite edge")
        XCTAssertEqual(draft.committed, square)
        XCTAssertEqual(draft.points, square.points)
        XCTAssertEqual(draft.status, "Not changed: the path crosses itself.")
        XCTAssertTrue(draft.nudge(0, dx: VectorPathDraft.nudgeStep, dy: 0))
        XCTAssertEqual(draft.committed?.points[0].x ?? 0, 0.11, accuracy: 1e-12)
        XCTAssertNil(draft.refusal)
        XCTAssertTrue(draft.delete(3))
        XCTAssertFalse(draft.delete(0), "a triangle keeps its 3 points")
        XCTAssertEqual(draft.committed?.points.count, 3)
        draft.startOver()
        XCTAssertFalse(draft.isClosed)
        XCTAssertEqual(draft.committed?.points.count, 3, "the closed path stays in use until a new one closes")
    }

    func testCapAndDuplicateTapsAreRefused() {
        var draft = VectorPathDraft(path: nil)
        XCTAssertTrue(draft.add(Self.p(0.2, 0.2)))
        XCTAssertFalse(draft.add(Self.p(0.2, 0.2)))
        XCTAssertEqual(draft.status, "Point 1 repeats the next point.")
        for k in 1..<VectorPath.maximumPoints { XCTAssertTrue(draft.add(Self.p(Double(k) / 40, 0.5 + Double(k % 2) / 4))) }
        XCTAssertFalse(draft.add(Self.p(0.9, 0.9)))
        XCTAssertEqual(draft.points.count, VectorPath.maximumPoints)
    }
}
