// SHD-005-T03: the CPU reference of the gradient (contract G2): exact at every stop in every mode, the segment rule,
// the modes between stops, limits. Plain Swift (runs on Linux).
import VisualGenerators
import XCTest

final class GradientRampTests: XCTestCase {
    private let stops: [GradientRampStop] = [
        GradientRampStop(position: 0.1, red: 0xFF, green: 0x40, blue: 0x00, alpha: 1),
        GradientRampStop(position: 0.35, red: 0x20, green: 0xC0, blue: 0x80, alpha: 0.5),
        GradientRampStop(position: 0.6, red: 0x00, green: 0x10, blue: 0xF0, alpha: 0.75),
        GradientRampStop(position: 0.9, red: 0xE8, green: 0xE8, blue: 0x30, alpha: 0.25),
    ]

    private func encodedBytes(_ c: LinearColor) -> [Int] {
        [c.red, c.green, c.blue].map { (v: Float) -> Int in Int((SRGB.encode(v) * 255).rounded()) }
    }

    func testEveryStopIsExactInEveryMode() throws {
        for mode in GradientInterpolation.allCases {
            let ramp = try XCTUnwrap(GradientRamp(stops: stops, interpolation: mode))
            for s in stops {
                let c: LinearColor = ramp.color(at: s.position)
                XCTAssertEqual(encodedBytes(c), [Int(s.red), Int(s.green), Int(s.blue)], "\(mode) at \(s.position)")
                XCTAssertEqual(c.alpha, s.alpha, "\(mode) alpha at \(s.position)")
            }
        }
    }

    func testOutsideTheEndsHoldsTheEndStops() throws {
        let ramp = try XCTUnwrap(GradientRamp(stops: stops))
        XCTAssertEqual(ramp.color(at: 0), stops[0].linear)
        XCTAssertEqual(ramp.color(at: -3), stops[0].linear)
        XCTAssertEqual(ramp.color(at: 1), stops[3].linear)
        XCTAssertEqual(ramp.color(at: .nan), stops[0].linear)
    }

    func testModesBetweenStops() throws {
        let smooth = try XCTUnwrap(GradientRamp(stops: stops, interpolation: .smooth))
        let srgb = try XCTUnwrap(GradientRamp(stops: stops, interpolation: .srgb))
        let step = try XCTUnwrap(GradientRamp(stops: stops, interpolation: .step))
        let mid: Float = 0.225
        let a: LinearColor = stops[0].linear
        let b: LinearColor = stops[1].linear
        XCTAssertEqual(smooth.color(at: mid).green, (a.green + b.green) / 2, accuracy: 1e-5)
        XCTAssertEqual(smooth.color(at: mid).alpha, 0.75, accuracy: 1e-6)
        XCTAssertEqual(srgb.color(at: mid).green, SRGB.decode((0x40 + 0xC0) / 2 / 255), accuracy: 1e-5)
        XCTAssertEqual(step.color(at: mid), a, "Step holds the stop")
        XCTAssertEqual(step.color(at: 0.3499), a, "just before the next stop")
        XCTAssertEqual(step.color(at: 0.35), b)
    }

    func testEqualPositionsLaterWinsAndSortIsStable() throws {
        let hard: [GradientRampStop] = [
            GradientRampStop(position: 0.5, red: 0, green: 0, blue: 0xFF),
            GradientRampStop(position: 0.5, red: 0xFF, green: 0, blue: 0),
            GradientRampStop(position: 0, red: 0, green: 0xFF, blue: 0),
        ]
        let ramp = try XCTUnwrap(GradientRamp(stops: hard))
        XCTAssertEqual(ramp.stops.map(\.red), [0, 0, 0xFF])
        XCTAssertEqual(ramp.color(at: 0.5), hard[1].linear)
        XCTAssertEqual(ramp.color(at: 0.4999).blue, hard[0].linear.blue, accuracy: 0.01)
    }

    func testLimitsAndClamping() {
        let one = GradientRampStop(position: 2, red: 1, green: 2, blue: 3, alpha: .nan)
        XCTAssertEqual(one.position, 1)
        XCTAssertEqual(one.alpha, 1)
        XCTAssertNil(GradientRamp(stops: [one]))
        XCTAssertNil(GradientRamp(stops: Array(repeating: one, count: 9)))
        XCTAssertNotNil(GradientRamp(stops: Array(repeating: one, count: 8)))
    }

    func testPaletteRampUsesTheGradientOverBlack() throws {
        let ramp = try XCTUnwrap(GradientRamp(stops: stops))
        let palette = VisualPalette.custom(PaletteRamp(gradient: ramp))
        let c: LinearColor = palette.color(bar: 0, of: 1)   // t = 0 → first stop, alpha 1
        XCTAssertEqual(c, LinearColor(red: stops[0].linear.red, green: stops[0].linear.green, blue: stops[0].linear.blue, alpha: 1))
        let last: LinearColor = PaletteRamp(gradient: ramp).color(at: 1)
        XCTAssertEqual(last.alpha, 1)
        XCTAssertEqual(last.red, stops[3].linear.red * 0.25, accuracy: 1e-6)
    }

    func testShaderStopsCarryLinearAndEncodedValues() throws {
        let ramp = try XCTUnwrap(GradientRamp(stops: stops, interpolation: .srgb))
        let packed = ramp.shaderStops
        XCTAssertEqual(packed.count, 4)
        XCTAssertEqual(packed[1].linear.w, 0.5)
        XCTAssertEqual(packed[1].encoded.w, 0.35)
        XCTAssertEqual(packed[1].encoded.y, Float(0xC0) / 255)
        XCTAssertEqual(GradientInterpolation.srgb.shaderMode, 1)
    }
}
