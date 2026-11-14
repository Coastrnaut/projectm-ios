// ShowTransitionOverrideTests.swift — SHOW-004-T06: a cue's `transitionOverride` in show.json (SHOW-004-R1, R2, R4;
// contract show-cue-transition-override.md O1-O3): exact round trip, byte-identical encoding without overrides,
// lenient reading (invalid overrides dropped and counted, unknown types kept and reported), the effective transition
// rule, and editing that never touches the position, the order or any cue's scene default.
import Foundation
import ParameterGraph
import ShowControl
import XCTest

final class ShowTransitionOverrideTests: XCTestCase {
    private static func crossfade2s() throws -> ShowCueTransition { try ShowCueTransition(type: .crossfade, durationSeconds: 2) }
    private static func cut() throws -> ShowCueTransition { try ShowCueTransition(type: .cut, durationSeconds: 0) }

    /// Cues 1 and 2 carry a 2 s crossfade default; cue 1 a Cut override, cue 3 a custom-curve dip override, cue 4 an
    /// unknown type.
    private func withOverrides() throws -> ShowCueList {
        var list = try ShowFixtures.fiveCues()
        try list.setTransition(ShowFixtures.uuid(1), to: try Self.crossfade2s())
        try list.setTransition(ShowFixtures.uuid(2), to: try Self.crossfade2s())
        try list.setTransitionOverride(ShowFixtures.uuid(1), to: try Self.cut())
        try list.setTransitionOverride(ShowFixtures.uuid(3), to: try ShowCueTransition(
            type: .dipToBlack, durationSeconds: 0.1 + 0.2, easing: .piecewise([CurvePoint(x: 0.2, y: 0.05), CurvePoint(x: 0.8, y: 0.9)])))
        try list.setTransitionOverride(ShowFixtures.uuid(4), to: try ShowCueTransition(type: .unknown("wipeLeft"), durationSeconds: 1))
        return list
    }

    func testOverridesRoundTripExactlyAndWinOverTheSceneDefault() throws {
        let list = try withOverrides()
        let data = list.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""transitionOverride":{"duration":0,"easing":"linear","type":"cut"}"#), text)
        XCTAssertEqual(text.components(separatedBy: "\"version\":1").count, 2, "version stays 1")
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [.unknownTransitionOverrideType(cue: ShowFixtures.uuid(4).uuidString, type: "wipeLeft")])
        XCTAssertEqual(decoded.list, list)
        for (a, b) in zip(decoded.list.cues, list.cues) {
            XCTAssertEqual(a.transitionOverride?.durationSeconds.bitPattern, b.transitionOverride?.durationSeconds.bitPattern)
            XCTAssertEqual(a.transitionOverride?.easing.textForm, b.transitionOverride?.easing.textForm)
        }
        XCTAssertEqual(decoded.list.encoded(), data, "decode → encode is byte-identical")

        let cues = decoded.list.cues
        XCTAssertEqual(cues[0].effectiveTransition, try Self.cut(), "the override wins")
        XCTAssertEqual(cues[0].transition, try Self.crossfade2s(), "the scene default is kept")
        XCTAssertEqual(cues[1].effectiveTransition, try Self.crossfade2s(), "no override: the scene default")
        XCTAssertNil(cues[4].effectiveTransition, "neither: the scene appears at once")
    }

    func testAShowWithoutOverridesKeepsItsBytes() throws {
        var plain = try ShowFixtures.fiveCues()
        try plain.setTransition(ShowFixtures.uuid(2), to: try Self.crossfade2s())
        let data = plain.encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("transitionOverride"))
        var cleared = plain
        try cleared.setTransitionOverride(ShowFixtures.uuid(2), to: try Self.cut())
        XCTAssertNotEqual(cleared.encoded(), data)
        try cleared.setTransitionOverride(ShowFixtures.uuid(2), to: nil)   // "Use Scene Default"
        XCTAssertEqual(cleared.encoded(), data, "removing the override gives the original bytes")
        XCTAssertEqual(try ShowCueList.decode(data).list.encoded(), data)
        let nulled = try ShowCueList.decode(try file(cueA: "null"))
        XCTAssertEqual(nulled.warnings, [])
        XCTAssertNil(nulled.list.cues[0].transitionOverride)
    }

    private func file(cueA value: String) throws -> Data {
        let text = String(decoding: try ShowFixtures.fiveCues().encoded(), as: UTF8.self)
        let scene = #""scene":""# + ShowFixtures.sceneID(1) + "\""
        return Data(text.replacingOccurrences(of: scene, with: scene + #","transitionOverride":"# + value).utf8)
    }

    func testInvalidOverridesAreDroppedAndCountedWhileTheShowLoads() throws {
        let invalid: [String] = [
            #""cut""#,                                                        // not an object
            #"{"duration":11,"easing":"linear","type":"cut"}"#,               // duration over 10 s
            #"{"duration":1,"easing":"wobble","type":"crossfade"}"#,          // unreadable easing
            #"{"duration":1,"easing":"linear","type":""}"#,                   // empty type
        ]
        for value in invalid {
            let decoded = try ShowCueList.decode(try file(cueA: value))
            XCTAssertEqual(decoded.warnings, [.droppedTransitionOverrides(1)], value)
            XCTAssertNil(decoded.list.cues[0].transitionOverride, value)
            XCTAssertEqual(decoded.list.cues.count, 5, value)
        }
    }

    func testEditingAnOverrideNeverMovesTheShowOrTouchesADefault() throws {
        var list = try withOverrides()
        _ = list.go(to: ShowFixtures.uuid(3))
        let before = list
        try list.setTransitionOverride(ShowFixtures.uuid(2), to: try Self.cut())
        XCTAssertEqual(list.position, before.position)
        XCTAssertEqual(list.cues.map(\.id), before.cues.map(\.id))
        XCTAssertEqual(list.cues.map(\.transition), before.cues.map(\.transition), "no scene default changes")
        XCTAssertThrowsError(try list.setTransitionOverride(UUID(), to: nil))
        let copy = try list.insert(sceneID: ShowFixtures.sceneID(1), label: "Copy", after: ShowFixtures.uuid(1),
                                   transitionOverride: list.cues[0].transitionOverride)
        XCTAssertEqual(copy.transitionOverride, try Self.cut())
    }
}
