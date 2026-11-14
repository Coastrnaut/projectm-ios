// SCN-007-T02: a MOD-004 curve on the CMP-014 transition spec and clock (SCN-007-R7, S5). Plain Swift (runs in
// the Linux shape too). Times are injected; nothing reads a clock.
import Compositor
import Foundation
import ParameterGraph
import XCTest

final class SceneTransitionCurveTests: XCTestCase {
    private static let step: UInt64 = 25_000_000

    func testTheCurveShapesEasedProgressAtEveryFrame() throws {
        let curves: [MappingCurve] = [.easeIn(exponent: 2), .easeOut(exponent: 3),
                                      .piecewise([CurvePoint(x: 0.25, y: 0.6), CurvePoint(x: 0.75, y: 0.7)])]
        for curve in curves {
            let spec = try SceneTransitionSpec(style: .crossfade, durationSeconds: 0.2, curve: curve)
            var clock = SceneTransitionClock(spec: spec)
            XCTAssertEqual(clock.curve, curve)
            var time: UInt64 = 1_000_000_000
            clock.advance(presentationTimeNanoseconds: time)
            for k in 1...8 {
                time += Self.step
                let progress = clock.advance(presentationTimeNanoseconds: time)
                XCTAssertEqual(progress, Double(k) / 8, accuracy: 1e-12)
                XCTAssertEqual(clock.easedProgress, curve.apply(progress), "\(curve.textForm) at frame \(k)")
                XCTAssertEqual(spec.ease(progress), curve.apply(progress))
            }
            XCTAssertEqual(clock.easedProgress, 1, "exact end")
        }
        // The shaping is real: ease-in at a quarter is a sixteenth, not the smoothstep's 0.15625.
        var clock = SceneTransitionClock(spec: try SceneTransitionSpec(style: .crossfade, durationSeconds: 0.1, curve: .easeIn(exponent: 2)))
        clock.advance(presentationTimeNanoseconds: 0)
        clock.advance(presentationTimeNanoseconds: Self.step)
        XCTAssertEqual(clock.easedProgress, 0.0625)
    }

    func testNoCurveKeepsCMP014EncodingAndEasing() throws {
        let spec = try SceneTransitionSpec(style: .dipToBlack, durationSeconds: 2, easing: .easeInOut)
        XCTAssertNil(spec.curve)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(spec), as: UTF8.self)
        XCTAssertEqual(text, #"{"durationSeconds":2,"easing":"easeInOut","style":"dipToBlack"}"#)
        XCTAssertEqual(SceneTransitionClock(spec: spec).curve, nil)
        XCTAssertEqual(spec.ease(0.25), SceneTransitionEasing.easeInOut.ease(0.25))
    }

    func testACurveRoundTripsThroughCodable() throws {
        let spec = try SceneTransitionSpec(style: .crossfade, durationSeconds: 1.2345678901234567,
                                           curve: .piecewise([CurvePoint(x: 0.3, y: 0.1)]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(spec)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""curve":"piecewise:0.3,0.1""#))
        let back = try JSONDecoder().decode(SceneTransitionSpec.self, from: data)
        XCTAssertEqual(back, spec)
        XCTAssertEqual(back.durationSeconds.bitPattern, spec.durationSeconds.bitPattern)
    }

    func testAnInvalidCurveIsRefused() {
        XCTAssertThrowsError(try SceneTransitionSpec(style: .crossfade, durationSeconds: 1, curve: .easeIn(exponent: 0.5))) { error in
            guard case SceneTransitionError.invalidCurve = error else { return XCTFail("\(error)") }
        }
        let bad = Data(#"{"durationSeconds":1,"easing":"linear","style":"crossfade","curve":"wobble:2"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SceneTransitionSpec.self, from: bad))
    }
}
