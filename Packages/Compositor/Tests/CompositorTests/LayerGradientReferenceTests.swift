// CMP-008-T04: the plain-Swift gradient reference (CMP-008-R1 to R4, R12; research CMP-008-D1, D2; S2).
// No GPU; builds and runs on Linux (the Compositor target's CPU part).
import Compositor
import Foundation
import XCTest

final class LayerGradientReferenceTests: XCTestCase {
    private func stops(_ pairs: [(Double, Double)]) -> [LayerGradientStop] {
        pairs.map { (p: (Double, Double)) -> LayerGradientStop in LayerGradientStop(position: p.0, alpha: p.1) }
    }

    private let horizontal = LayerGradientKind.linear(start: LayerPoint(x: 0, y: 0.5), end: LayerPoint(x: 1, y: 0.5))

    /// The test stop lists: rising, falling, mixed (rise, fall, rise, flat), and with a hard step.
    private var lists: [(String, [LayerGradientStop])] {
        [
            ("rising", stops([(0.1, 0), (0.9, 1)])),
            ("falling", stops([(0, 1), (0.5, 0.25), (1, 0)])),
            ("mixed", stops([(0.1, 0.2), (0.35, 0.9), (0.6, 0.1), (0.8, 0.7), (0.95, 0.7)])),
            ("hard step", stops([(0, 0), (0.5, 0), (0.5, 1), (1, 1)])),
        ]
    }

    func testEachStopsAlphaHoldsExactlyAtItsPosition() throws {
        for (name, list) in lists {
            let g = try LayerGradientMask(kind: horizontal, stops: list)
            for (k, stop) in g.stops.enumerated() {
                // At a hard step the later stop wins at the shared position.
                let later: Bool = k + 1 < g.stops.count && g.stops[k + 1].position == stop.position
                if later { continue }
                XCTAssertEqual(g.alpha(at: stop.position), stop.alpha, "\(name) stop \(k)")
            }
        }
    }

    func testAlphaIsClampedOutsideTheStops() throws {
        let g = try LayerGradientMask(kind: horizontal, stops: stops([(0.2, 0.3), (0.7, 0.9)]))
        XCTAssertEqual(g.alpha(at: -5), 0.3)
        XCTAssertEqual(g.alpha(at: 0.2), 0.3)
        XCTAssertEqual(g.alpha(at: 0.7), 0.9)
        XCTAssertEqual(g.alpha(at: 3), 0.9)
        XCTAssertEqual(g.alpha(at: 0.45), 0.6, accuracy: 1e-12)
    }

    /// CMP-008-S2: 0 monotonicity violations over a dense sweep of every test list.
    func testDenseSweepIsMonotonicBetweenAdjacentStops() throws {
        var violations = 0
        var samples = 0
        for (_, list) in lists {
            let g = try LayerGradientMask(kind: horizontal, stops: list)
            for k in 1..<g.stops.count {
                let a: LayerGradientStop = g.stops[k - 1]
                let b: LayerGradientStop = g.stops[k]
                guard b.position > a.position else { continue }
                let rising: Bool = b.alpha >= a.alpha
                var previous: Double = g.alpha(at: a.position)
                // The segment's interior plus its end, except where a later stop shares the end (a hard step).
                let shared: Bool = k + 1 < g.stops.count && g.stops[k + 1].position == b.position
                for step in 1...(shared ? 255 : 256) {
                    let t: Double = a.position + (b.position - a.position) * Double(step) / 256
                    let value: Double = g.alpha(at: t)
                    samples += 1
                    if rising ? value < previous : value > previous { violations += 1 }
                    let low: Double = min(a.alpha, b.alpha)
                    let high: Double = max(a.alpha, b.alpha)
                    if value < low || value > high { violations += 1 }
                    previous = value
                }
            }
        }
        XCTAssertEqual(violations, 0)
        XCTAssertGreaterThan(samples, 2_000)
    }

    func testEqualPositionsGiveAHardStep() throws {
        let g = try LayerGradientMask(kind: horizontal, stops: stops([(0, 0), (0.5, 0), (0.5, 1), (1, 1)]))
        XCTAssertEqual(g.alpha(at: 0.4999), 0)
        XCTAssertEqual(g.alpha(at: 0.5), 1)
        XCTAssertEqual(g.alpha(at: 0.5001), 1)
    }

    func testStopsAreStableSortedAndClamped() throws {
        let given: [LayerGradientStop] = stops([(0.8, 0.1), (0.2, 0.5), (0.8, 0.9), (-1, 2)])
        let g = try LayerGradientMask(kind: horizontal, stops: given)
        XCTAssertEqual(g.stops.map(\.position), [0, 0.2, 0.8, 0.8])
        XCTAssertEqual(g.stops.map(\.alpha), [1, 0.5, 0.1, 0.9])   // equal positions keep their order
        let odd = LayerGradientStop(position: .nan, alpha: .infinity)
        XCTAssertEqual(odd.position, 0)
        XCTAssertEqual(odd.alpha, 1)
        XCTAssertEqual(LayerGradientStop(position: -0.0, alpha: 0.5).position.sign, .plus)
    }

    func testRefusals() {
        XCTAssertThrowsError(try LayerGradientMask(kind: horizontal, stops: stops([(0, 1)]))) { (e: Error) in
            XCTAssertEqual(e as? LayerGradientMaskError, .tooFewStops(1))
        }
        let nine: [LayerGradientStop] = (0..<9).map { (k: Int) -> LayerGradientStop in LayerGradientStop(position: Double(k) / 8, alpha: 1) }
        XCTAssertThrowsError(try LayerGradientMask(kind: horizontal, stops: nine)) { (e: Error) in
            XCTAssertEqual(e as? LayerGradientMaskError, .tooManyStops(9))
        }
        let point = LayerPoint(x: 0.3, y: 0.3)
        XCTAssertThrowsError(try LayerGradientMask(kind: .linear(start: point, end: point), stops: stops([(0, 1), (1, 0)]))) { (e: Error) in
            XCTAssertEqual(e as? LayerGradientMaskError, .zeroLength)
        }
        XCTAssertNoThrow(try LayerGradientMask(kind: horizontal, stops: Array(nine.prefix(8))))
    }

    func testGeometryIsClamped() throws {
        let far = try LayerGradientMask(kind: .linear(start: LayerPoint(x: -50, y: .nan), end: LayerPoint(x: 50, y: 0.5)),
                                        stops: stops([(0, 1), (1, 0)]))
        XCTAssertEqual(far.kind, .linear(start: LayerPoint(x: -10, y: 0.5), end: LayerPoint(x: 10, y: 0.5)))
        let tiny = try LayerGradientMask(kind: .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0), stops: stops([(0, 1), (1, 0)]))
        XCTAssertEqual(tiny.kind, .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0.01))
        let odd = try LayerGradientMask(kind: .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: .nan), stops: stops([(0, 1), (1, 0)]))
        XCTAssertEqual(odd.kind, .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0.5))
    }

    func testLinearParameterIsAProjectionInPixels() throws {
        // 200 × 100, start (0, 0) → end (1, 1): pixels (0, 0) → (200, 100). Isolines are perpendicular to the axis in pixels.
        let g = try LayerGradientMask(kind: .linear(start: LayerPoint(x: 0, y: 0), end: LayerPoint(x: 1, y: 1)),
                                      stops: stops([(0, 0), (1, 1)])).geometry(width: 200, height: 100)
        XCTAssertEqual(g.parameter(x: 0, y: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(g.parameter(x: 200, y: 100), 1, accuracy: 1e-12)
        XCTAssertEqual(g.parameter(x: 100, y: 50), 0.5, accuracy: 1e-12)
        // A step perpendicular to (200, 100) — along (−100, 200) — keeps t.
        XCTAssertEqual(g.parameter(x: 100 - 10, y: 50 + 20), 0.5, accuracy: 1e-12)
        XCTAssertEqual(g.alpha(x: 100, y: 50), 0.5, accuracy: 1e-12)
    }

    func testRadialStaysRoundOnWideAndTallPictures() throws {
        let gradient = try LayerGradientMask(kind: .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0.4), stops: stops([(0, 1), (1, 0)]))
        for (w, h) in [(160, 90), (90, 160)] {
            let g = gradient.geometry(width: w, height: h)
            let r: Double = 0.4 * Double(min(w, h))
            let cx: Double = Double(w) / 2, cy: Double = Double(h) / 2
            for angle in stride(from: 0.0, to: 6.28, by: 0.7) {
                let x: Double = cx + 0.5 * r * cos(angle)
                let y: Double = cy + 0.5 * r * sin(angle)
                XCTAssertEqual(g.parameter(x: x, y: y), 0.5, accuracy: 1e-9, "\(w)×\(h) at \(angle)")
                XCTAssertEqual(g.alpha(x: x, y: y), 0.5, accuracy: 1e-9)
            }
        }
    }

    func testDefaults() {
        XCTAssertEqual(LayerGradientMask.linearDefault.kind, .linear(start: LayerPoint(x: 0, y: 0.5), end: LayerPoint(x: 1, y: 0.5)))
        XCTAssertEqual(LayerGradientMask.radialDefault.kind, .radial(center: LayerPoint(x: 0.5, y: 0.5), radius: 0.5))
        for g in [LayerGradientMask.linearDefault, .radialDefault] {
            XCTAssertEqual(g.stops, [LayerGradientStop(position: 0, alpha: 1), LayerGradientStop(position: 1, alpha: 0)])
        }
        XCTAssertEqual(LayerGradientKind.kindNames, ["linear", "radial"])
    }
}
