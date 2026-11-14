// LissajousLayoutTests.swift — VIS-004-T04: the roadmap acceptance "In-phase and quadrature fixtures yield
// distinguishable stable shapes" on the CPU geometry (VIS-004-S1, S2; R3, R4, R5, R7). Runs everywhere,
// Linux included.
import XCTest
@testable import VisualGenerators

final class LissajousLayoutTests: XCTestCase {
    func testInPhaseIsTheDiagonalAndQuadratureIsACircle() {
        let layout = LissajousLayout()
        layout.layout(LissajousFixture.history(.inPhase))
        XCTAssertEqual(layout.pointCount, LissajousLayout.windowFrames)
        for j in 0..<layout.pointCount {
            let p = layout.normalizedPoint(j)
            XCTAssertEqual(p.u, p.v, accuracy: 1e-9, "in-phase point \(j) on the diagonal")
        }
        let line = ShapeMetrics(layout: layout)
        XCTAssertLessThan(line.axisRatio, 0.02)
        XCTAssertEqual(line.angle, Double.pi / 4, accuracy: 1e-6, "the 45° diagonal")

        let scope = LissajousLayout()
        scope.layout(LissajousFixture.history(.quadrature))
        let circle = ShapeMetrics(layout: scope)
        XCTAssertGreaterThan(circle.axisRatio, 0.95)
        XCTAssertLessThan(circle.radiusSpread, 0.02, "points on a circle")
        XCTAssertEqual(circle.minor.squareRoot(), circle.major.squareRoot(), accuracy: 0.02 * circle.major.squareRoot(),
                       "both axis lengths equal within 2 %")
        XCTAssertGreaterThan(circle.axisRatio - line.axisRatio, 0.9, "the shapes are distinguishable")
        // The auto gain brings the circle to the plot's reach: |(u, v)| ≈ 1.
        XCTAssertEqual(circle.meanRadius, 1, accuracy: 0.02)
    }

    func testSteadyFixtureIsIdenticalFrameToFrameAndAdvancingFixtureIsStable() {
        for kind in [LissajousFixture.Kind.inPhase, .quadrature] {
            let layout = LissajousLayout()
            let history = LissajousFixture.history(kind)
            layout.layout(history)
            let first = ShapeMetrics(layout: layout)
            let points = (0..<layout.pointCount).map { (j: Int) -> Double in layout.normalizedPoint(j).u }
            for _ in 0..<10 {
                layout.layout(history)
                XCTAssertEqual(ShapeMetrics(layout: layout), first, "steady \(kind): identical metric")
                XCTAssertEqual((0..<layout.pointCount).map { (j: Int) -> Double in layout.normalizedPoint(j).u }, points)
            }
            // A phase-advancing fixture (735 frames per 60 Hz frame, varying a little): the shape holds.
            let moving = LissajousLayout()
            var end = 60_000
            for frame in 0..<30 {
                moving.layout(LissajousFixture.history(kind, endingAt: end))
                let m = ShapeMetrics(layout: moving)
                XCTAssertEqual(m.axisRatio, first.axisRatio, accuracy: 0.01, "\(kind) frame \(frame)")
                end += 700 + (frame * 7) % 71
            }
        }
    }

    func testMidSideRotatesTheInPhaseLineToVertical() {
        let layout = LissajousLayout(configuration: LissajousConfiguration(mode: .midSide))
        layout.layout(LissajousFixture.history(.inPhase))
        for j in 0..<layout.pointCount { XCTAssertEqual(layout.normalizedPoint(j).u, 0, accuracy: 1e-9) }
        XCTAssertEqual(abs(ShapeMetrics(layout: layout).angle), Double.pi / 2, accuracy: 1e-6, "mono is vertical")
        layout.layout(LissajousFixture.history(.antiPhase))
        for j in 0..<layout.pointCount { XCTAssertEqual(layout.normalizedPoint(j).v, 0, accuracy: 1e-9) }
        // A left-only signal leans up-left: x = −L/√2, y = L/√2.
        layout.layout(LissajousFixture.history(.leftOnly))
        for j in 0..<layout.pointCount {
            let p = layout.normalizedPoint(j)
            XCTAssertEqual(p.u, -p.v, accuracy: 1e-9)
        }
        // In X/Y the left-only signal lies on the x axis.
        let xy = LissajousLayout()
        xy.layout(LissajousFixture.history(.leftOnly))
        for j in 0..<xy.pointCount { XCTAssertEqual(xy.normalizedPoint(j).v, 0, accuracy: 1e-12) }
    }

    func testSilenceDrawsNothingAndNonFiniteSamplesReadZero() {
        let layout = LissajousLayout()
        layout.layout(LissajousFixture.silence())
        XCTAssertEqual(layout.pointCount, 0)
        XCTAssertEqual(layout.vertexCount(), 0, "silence draws nothing")
        var history = LissajousFixture.history(.inPhase)
        for i in stride(from: 0, to: history.count, by: 5) { history[i] = i % 2 == 0 ? .nan : .infinity }
        layout.layout(history)
        for j in 0..<layout.pointCount {
            let p = layout.normalizedPoint(j)
            XCTAssertTrue(p.u.isFinite && p.v.isFinite && abs(p.u) <= 1 && abs(p.v) <= 1)
        }
        let nonFinite = [Float](repeating: .nan, count: 2 * LissajousFixture.frames)
        let fresh = LissajousLayout()
        fresh.layout(nonFinite)
        XCTAssertEqual(fresh.vertexCount(), 0, "non-finite only reads as silence")
    }

    func testGeometryStaysInsideTheOutputAtAnySize() {
        for (w, h) in [(256, 192), (192, 256), (3, 2), (1, 1)] {
            let layout = LissajousLayout()
            layout.layout(LissajousFixture.history(.quadrature), width: w, height: h)
            let r: Double = 0.9 * Double(min(w, h)) / 2
            for j in 0..<layout.pointCount {
                let p = layout.point(j)
                XCTAssertLessThanOrEqual(abs(p.x - Double(w) / 2), r + 1e-9, "\(w)x\(h)")
                XCTAssertLessThanOrEqual(abs(p.y - Double(h) / 2), r + 1e-9, "\(w)x\(h)")
            }
            XCTAssertGreaterThan(layout.vertexCount(), 0)
        }
        let empty = LissajousLayout()
        empty.layout(LissajousFixture.history(.quadrature), width: 0, height: 100)
        XCTAssertEqual(empty.vertexCount(), 0)
    }

    func testColorsFollowThePaletteOldestToNewest() {
        let layout = LissajousLayout(configuration: LissajousConfiguration(palette: .colorBlindSafe))
        layout.layout(LissajousFixture.history(.quadrature))
        let n = LissajousLayout.traceSegments
        XCTAssertEqual(layout.flashRegionCount, n)
        for k in [0, n / 2, n - 1] {
            XCTAssertEqual(layout.flashRegionColor(k), VisualPalette.colorBlindSafe.color(bar: k, of: n))
        }
    }

    func testFewerFramesThanTheWindowReadZeroBefore() {
        let short = Array(LissajousFixture.history(.inPhase).suffix(2 * 100))
        let layout = LissajousLayout()
        layout.layout(short)
        XCTAssertEqual(layout.pointCount, LissajousLayout.windowFrames)
        for j in 0..<(LissajousLayout.windowFrames - 100) {
            XCTAssertEqual(layout.normalizedPoint(j).u, 0)
            XCTAssertEqual(layout.normalizedPoint(j).v, 0)
        }
    }
}
