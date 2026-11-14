// ShowTransitionDocumentTests.swift — SCN-007-T06: a cue's `transition` in show.json (SCN-007-R1 to R4,
// R8; contract X1-X3): exact round trip (bit-identical durations, equal curves), byte-identical legacy
// encoding, unknown types kept and reported, invalid transitions dropped with a counted warning, model
// bounds, editing that never moves the position, and a store reload.
import Foundation
import ParameterGraph
import ShowControl
import ShowStorage
import XCTest

final class ShowTransitionDocumentTests: XCTestCase {
    /// Distinct values per cue, including a custom piecewise curve and an awkward duration.
    static func transitions() throws -> [Int: ShowCueTransition] {
        [2: try ShowCueTransition(type: .crossfade, durationSeconds: 1.5, easing: .easeOut(exponent: 2)),
         3: try ShowCueTransition(type: .dipToBlack, durationSeconds: 0.1 + 0.2,
                                  easing: .piecewise([CurvePoint(x: 0.2, y: 0.05), CurvePoint(x: 0.8, y: 0.9)])),
         4: try ShowCueTransition(type: .cut, durationSeconds: 7.25, easing: .logarithmic(strength: 9)),
         5: try ShowCueTransition(type: .crossfade, durationSeconds: 10, easing: .linear)]
    }

    private func withTransitions() throws -> ShowCueList {
        var list = try ShowFixtures.fiveCues()
        for (n, transition) in try Self.transitions() { try list.setTransition(ShowFixtures.uuid(n), to: transition) }
        return list
    }

    private func assertExactlyEqual(_ a: ShowCueTransition?, _ b: ShowCueTransition?, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, message, file: file, line: line)
        XCTAssertEqual(a?.durationSeconds.bitPattern, b?.durationSeconds.bitPattern, "\(message): bit-identical duration",
                       file: file, line: line)
        XCTAssertEqual(a?.easing.textForm, b?.easing.textForm, message, file: file, line: line)
    }

    func testTransitionsRoundTripExactly() throws {
        let list = try withTransitions()
        let data = list.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""transition":{"duration":1.5,"easing":"easeOut:2.0","type":"crossfade"}"#), text)
        XCTAssertEqual(text.components(separatedBy: "\"version\":1").count, 2, "version stays 1")
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list, list)
        for n in 1...5 {
            assertExactlyEqual(decoded.list.cues[n - 1].transition, try Self.transitions()[n], "cue \(n)")
        }
        XCTAssertEqual(decoded.list.encoded(), data, "decode → encode is byte-identical")
        XCTAssertEqual(try withTransitions().encoded(), data, "deterministic")
    }

    func testAShowWithoutTransitionsKeepsItsBytes() throws {
        let plain = try ShowFixtures.fiveCues()
        let data = plain.encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("transition"))
        var cleared = try withTransitions()
        for n in 1...5 { try cleared.setTransition(ShowFixtures.uuid(n), to: nil) }
        XCTAssertEqual(cleared.encoded(), data, "removing every transition gives the original bytes")
        // A file written before SCN-007 has no key; an explicit null is also read as none.
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [])
        XCTAssertEqual(decoded.list.encoded(), data)
        let nulled = try ShowCueList.decode(try file(cueA: "null"))
        XCTAssertEqual(nulled.warnings, [])
        XCTAssertNil(nulled.list.cues[0].transition)
        XCTAssertEqual(nulled.list.encoded(), data)
    }

    private func file(cueA transition: String) throws -> Data {
        let text = String(decoding: try ShowFixtures.fiveCues().encoded(), as: UTF8.self)
        let scene = #""scene":""# + ShowFixtures.sceneID(1) + "\""
        return Data(text.replacingOccurrences(of: scene, with: scene + #","transition":"# + transition).utf8)   // sorted-key position
    }

    func testAnUnknownTypeIsKeptVerbatimAndReported() throws {
        let data = try file(cueA: #"{"duration":0.75,"easing":"easeIn:3.0","type":"wipeLeft"}"#)
        let decoded = try ShowCueList.decode(data)
        XCTAssertEqual(decoded.warnings, [.unknownTransitionType(cue: ShowFixtures.uuid(1).uuidString, type: "wipeLeft")])
        let kept = try XCTUnwrap(decoded.list.cues[0].transition)
        XCTAssertEqual(kept.type, .unknown("wipeLeft"))
        XCTAssertFalse(kept.type.isKnown)
        XCTAssertEqual(kept.durationSeconds, 0.75)
        XCTAssertEqual(kept.easing, .easeIn(exponent: 3))
        XCTAssertEqual(decoded.list.encoded(), data, "written back unchanged")
    }

    func testInvalidTransitionsAreDroppedWithACountedWarning() throws {
        let bad = [#"{"duration":12,"easing":"linear","type":"crossfade"}"#,
                   #"{"duration":-1,"easing":"linear","type":"crossfade"}"#,
                   #"{"duration":"1","easing":"linear","type":"crossfade"}"#,
                   #"{"duration":1,"easing":"wobble:2","type":"crossfade"}"#,
                   #"{"duration":1,"easing":"easeIn:0.5","type":"crossfade"}"#,
                   #"{"duration":1,"easing":"linear","type":""}"#,
                   #"{"duration":1,"easing":"linear","type":"\#(String(repeating: "x", count: 65))"}"#,
                   #"{"duration":1,"type":"crossfade"}"#,
                   #""crossfade""#, "[1]", "7"]
        for value in bad {
            let decoded = try ShowCueList.decode(try file(cueA: value))
            XCTAssertEqual(decoded.warnings, [.droppedTransitions(1)], value)
            XCTAssertNil(decoded.list.cues[0].transition, value)
            XCTAssertEqual(decoded.list.cues.count, 5, "the show loads: \(value)")
            XCTAssertEqual(decoded.list.encoded(), try ShowFixtures.fiveCues().encoded(), "dropped on write: \(value)")
        }
    }

    func testModelBoundsAndValidation() throws {
        XCTAssertNoThrow(try ShowCueTransition(type: .crossfade, durationSeconds: 0))
        XCTAssertNoThrow(try ShowCueTransition(type: .crossfade, durationSeconds: 10))
        for seconds in [-0.001, 10.000001, .infinity, .nan] {
            XCTAssertThrowsError(try ShowCueTransition(type: .crossfade, durationSeconds: seconds), "\(seconds)")
        }
        XCTAssertThrowsError(try ShowCueTransition(type: .crossfade, durationSeconds: 1, easing: .easeOut(exponent: 9)))
        XCTAssertThrowsError(try ShowCueTransition(type: .crossfade, durationSeconds: 1,
                                                   easing: .piecewise([CurvePoint(x: 0.5, y: 0.6), CurvePoint(x: 0.4, y: 0.7)])))
        XCTAssertEqual(ShowCueTransition.defaultCrossfade.easing, .linear, "default easing is linear")
        XCTAssertEqual(ShowTransitionType(text: "dipToBlack"), .dipToBlack)
        XCTAssertNil(ShowTransitionType(text: ""))
        XCTAssertEqual(ShowTransitionType.known.map(\.text), ["cut", "crossfade", "dipToBlack"])
    }

    func testEditingNeverMovesThePositionAndDuplicateCopiesTheTransition() throws {
        var list = try withTransitions()
        list.go(to: ShowFixtures.uuid(3))
        try list.setTransition(ShowFixtures.uuid(4), to: nil)
        XCTAssertEqual(list.position, .cue(ShowFixtures.uuid(3)))
        XCTAssertEqual(list.cues.map(\.id), (1...5).map(ShowFixtures.uuid))
        XCTAssertThrowsError(try list.setTransition(ShowFixtures.uuid(77), to: nil))
        let source = try XCTUnwrap(list.cues[1].transition)
        let copy = try list.insert(sceneID: ShowFixtures.sceneID(6), label: "Cue B copy", after: ShowFixtures.uuid(2),
                                   cueID: ShowFixtures.uuid(6), transition: source)
        XCTAssertEqual(list.cues[2].transition, source)
        XCTAssertEqual(copy.transition, source)
    }

    func testAStoreReloadRestoresTransitionsExactly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scn007-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let list = try withTransitions()
        try ShowStore(directory: directory).save(list)
        let loaded = ShowStore(directory: directory).load()
        XCTAssertEqual(loaded.warnings, [])
        for n in 1...5 { assertExactlyEqual(loaded.list.cues[n - 1].transition, list.cues[n - 1].transition, "cue \(n)") }
    }
}
