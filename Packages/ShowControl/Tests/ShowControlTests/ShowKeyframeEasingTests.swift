// ShowKeyframeEasingTests.swift — SHOW-009-T05, T06: the roadmap acceptance "Reference midpoints match expected
// interpolation values" (specs/283-show-009-keyframe-easing; contract contracts/keyframe-easing.md E1-E6). Pure: no clock.
import Foundation
import ParameterGraph
import ShowControl
import XCTest

final class ShowKeyframeEasingTests: XCTestCase {
    private let glow = ParameterID("effect.bloom.intensity")

    private func track(_ keys: [(Int, Double, ShowKeyframeInterpolation)]) throws -> ShowKeyframeTrack {
        try ShowKeyframeTrack(id: UUID(), parameter: glow, keyframes: keys.map { (k: (Int, Double, ShowKeyframeInterpolation)) -> ShowKeyframe in
            ShowKeyframe(time: k.0, value: .number(k.1), interpolation: k.2)
        })
    }

    private func number(_ t: ShowKeyframeTrack, _ ms: Int) throws -> Double {
        try XCTUnwrap(t.value(at: .milliseconds(ms))?.number)
    }

    /// The Hermite reference written out independently (research D2).
    private static func hermite(_ y0: Double, _ y1: Double, _ m0: Double, _ m1: Double, _ h: Double, _ u: Double) -> Double {
        let h00: Double = 2 * pow(u, 3) - 3 * pow(u, 2) + 1
        let h10: Double = pow(u, 3) - 2 * pow(u, 2) + u
        let h01: Double = -2 * pow(u, 3) + 3 * pow(u, 2)
        let h11: Double = pow(u, 3) - pow(u, 2)
        return h00 * y0 + h10 * h * m0 + h01 * y1 + h11 * h * m1
    }

    // E2, S1: keys (0 s, 0.0) and (1 s, 1.0): the reference midpoints and Cubic's quarter points.
    func testTwoKeyReferenceMidpoints() throws {
        let expected: [ShowKeyframeInterpolation: Double] = [.linear: 0.5, .stepped: 0.0, .hold: 0.0, .ease: 0.5, .cubic: 0.5]
        XCTAssertEqual(Set(expected.keys), Set(ShowKeyframeInterpolation.allCases))
        for (mode, value) in expected {
            let t = try track([(0, 0.0, mode), (1_000, 1.0, .linear)])
            XCTAssertEqual(try number(t, 500), value, accuracy: 1e-12, "\(mode) at 0.5 s")
        }
        let cubic = try track([(0, 0.0, .cubic), (1_000, 1.0, .cubic)])
        for u in [0.25, 0.75] {
            let reference: Double = 3 * u * u - 2 * u * u * u   // 0.15625, 0.84375
            XCTAssertEqual(try number(cubic, Int(u * 1_000)), reference, accuracy: 1e-9, "cubic at \(u) s")
        }
        XCTAssertEqual(try number(cubic, 250), 0.15625, accuracy: 1e-9)
        XCTAssertEqual(try number(cubic, 750), 0.84375, accuracy: 1e-9)
        XCTAssertEqual(ShowKeyframeInterpolation.allCases.map(\.displayName), ["Linear", "Stepped", "Hold", "Ease", "Cubic"])
    }

    // E3: Hold also holds the arriving segment; Stepped only the leaving one.
    func testHoldIsACutWhereSteppedIsNot() throws {
        let stepped = try track([(0, 0.0, .linear), (1_000, 1.0, .stepped), (2_000, 0.0, .linear)])
        let hold = try track([(0, 0.0, .linear), (1_000, 1.0, .hold), (2_000, 0.0, .linear)])
        XCTAssertEqual(try number(stepped, 500), 0.5)
        XCTAssertEqual(try number(hold, 500), 0.0)
        XCTAssertEqual(try number(hold, 999), 0.0)
        XCTAssertEqual(try number(stepped, 1_500), 1.0)
        XCTAssertEqual(try number(hold, 1_500), 1.0)
        // Colours: Hold arrives as a cut too.
        let red = try XCTUnwrap(ShowKeyframeColor(red: 1, green: 0, blue: 0))
        let blue = try XCTUnwrap(ShowKeyframeColor(red: 0, green: 0, blue: 1))
        let colors = try ShowKeyframeTrack(id: UUID(), parameter: glow, keyframes: [
            ShowKeyframe(time: 0, value: .color(red), interpolation: .cubic), ShowKeyframe(time: 1_000, value: .color(blue), interpolation: .hold),
        ])
        XCTAssertEqual(colors.value(at: .milliseconds(500)), .color(red))
    }

    // E1, S2: every mode returns the stored sample bit for bit at every key (numbers and colours).
    func testEveryModeIsExactAtKeys() throws {
        let values: [Double] = [0.1, 0.30000000000000004, 0.95, 0.2, 0.7000000000000001]
        for mode in ShowKeyframeInterpolation.allCases {
            let t = try track(values.enumerated().map { (e: (offset: Int, element: Double)) -> (Int, Double, ShowKeyframeInterpolation) in
                (e.offset * 777, e.element, mode)
            })
            for k in t.keyframes {
                XCTAssertEqual(t.value(at: .milliseconds(k.time))?.number?.bitPattern, k.value.number?.bitPattern, "\(mode) at \(k.time)")
            }
        }
        let c = try XCTUnwrap(ShowKeyframeColor(red: 0.9, green: 0.12345678901234, blue: 0.7, alpha: 0.5))
        let colors = try ShowKeyframeTrack(id: UUID(), parameter: glow, keyframes: [
            ShowKeyframe(time: 0, value: .color(.white), interpolation: .cubic),
            ShowKeyframe(time: 900, value: .color(c), interpolation: .hold),
            ShowKeyframe(time: 1_800, value: .color(.white), interpolation: .cubic),
        ])
        XCTAssertEqual(colors.value(at: .milliseconds(900))?.color?.components.map(\.bitPattern), c.components.map(\.bitPattern))
    }

    // E4: a three-key Cubic run matches the closed-form Hermite with Fritsch–Butland slopes and flows through the inner key.
    func testThreeKeyCubicMatchesTheClosedFormReference() throws {
        let t = try track([(0, 0.0, .cubic), (1_000, 1.0, .cubic), (3_000, 2.0, .cubic)])
        let m1: Double = 9_000.0 / 13_000_000.0   // (w1 + w2) / (w1/Δ0 + w2/Δ1), w1 = 5000, w2 = 4000, Δ0 = 1/1000, Δ1 = 1/2000
        XCTAssertEqual(try number(t, 500), Self.hermite(0, 1, 0, m1, 1_000, 0.5), accuracy: 1e-9)
        XCTAssertEqual(try number(t, 2_000), Self.hermite(1, 2, m1, 0, 2_000, 0.5), accuracy: 1e-9)
        let before: Double = try number(t, 990)
        let after: Double = try number(t, 1_010)
        XCTAssertEqual((after - before) / 20, m1, accuracy: 1e-5, "the curve keeps moving through the inner key")
    }

    // E5, S3: a dense sample never leaves a segment's key range; a peak key is flat; a Hold key after Cubic holds.
    func testCubicNeverOvershootsAndHandlesPeaksAndHolds() throws {
        let keys: [(Int, Double, ShowKeyframeInterpolation)] = [
            (0, 0.2, .cubic), (700, 0.9, .cubic), (1_000, 0.85, .cubic), (2_500, 0.1, .cubic), (2_600, 1.0, .cubic), (4_000, 0.0, .cubic),
        ]
        let t = try track(keys)
        for i in 0..<(keys.count - 1) {
            let low: Double = min(keys[i].1, keys[i + 1].1)
            let high: Double = max(keys[i].1, keys[i + 1].1)
            for ms in stride(from: keys[i].0, through: keys[i + 1].0, by: 10) {
                let v: Double = try number(t, ms)
                XCTAssertTrue(v >= low && v <= high, "\(v) at \(ms) ms is outside \(low)…\(high)")
            }
        }
        // 0.9 at 700 ms is a peak: zero slope, so both sides stay below it.
        XCTAssertEqual(try number(t, 699), try number(t, 701), accuracy: 1e-5)
        let held = try track([(0, 0.0, .cubic), (1_000, 1.0, .cubic), (2_000, 0.5, .hold), (3_000, 0.0, .linear)])
        XCTAssertEqual(try number(held, 1_500), 1.0, "a Hold key holds the arriving segment, even after Cubic")
        XCTAssertEqual(try number(held, 999), try number(held, 1_001), accuracy: 1e-5, "the run ends flat before the hold")
    }

    // E6, S4: every mode round-trips; Hold and Cubic carry `easing`; old documents read as before.
    func testStorageRoundTripAndOlderDocuments() throws {
        var list = ShowCueList(id: UUID(), name: "Show")
        let modes: [ShowKeyframeInterpolation] = ShowKeyframeInterpolation.allCases
        list.tracks = try ShowKeyframeTracks(tracks: [track(modes.enumerated().map { (e: (offset: Int, element: ShowKeyframeInterpolation)) -> (Int, Double, ShowKeyframeInterpolation) in
            (e.offset * 1_000, 0.1 * Double(e.offset), e.element)
        })])
        let bytes: Data = list.encoded()
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("\"easing\":\"hold\"") && text.contains("\"easing\":\"cubic\""))
        XCTAssertEqual(text.components(separatedBy: "\"easing\"").count - 1, 2, "easing only for Hold and Cubic")
        XCTAssertFalse(text.contains("stepped"), "Stepped is stored with SHOW-008's name")
        let decoded = try ShowCueList.decode(bytes)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list.tracks.tracks.first?.keyframes.map(\.interpolation), modes)
        XCTAssertEqual(decoded.list.encoded(), bytes)

        let old = """
        {"format":"projectm-ios.show","version":1,"id":"\(UUID().uuidString)","name":"Show","cues":[],"position":null,
         "tracks":[{"id":"\(UUID().uuidString)","parameter":"effect.bloom.intensity","keyframes":[
            {"time":0,"value":0.5},
            {"time":10,"value":0.5,"interpolation":"hold"},
            {"time":20,"value":0.5,"interpolation":"ease","easing":"bounce"},
            {"time":30,"value":0.5,"interpolation":"bounce","easing":"cubic"},
            {"time":40,"value":0.5,"interpolation":"bounce","easing":"elastic"}]}]}
        """
        let read = try ShowCueList.decode(Data(old.utf8))
        XCTAssertEqual(read.warnings, [.droppedKeyframes(1)], "only the keyframe with no known curve is dropped")
        XCTAssertEqual(read.list.tracks.tracks.first?.keyframes.map(\.interpolation), [.linear, .stepped, .ease, .cubic])
    }
}
