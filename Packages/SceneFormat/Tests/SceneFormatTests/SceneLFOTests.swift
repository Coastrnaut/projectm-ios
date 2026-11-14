// SceneLFOTests.swift — MOD-007-T06 (US3; MOD-007-R5, R7, R8, S4; contract L5, L6): the optional `lfos` list in
// the scene document and `audio.lfo.<index>` bindings. CPU only, runs on Linux.
import Foundation
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneLFOTests: XCTestCase {
    private var registry: ParameterRegistry!

    override func setUpWithError() throws {
        registry = try SceneFixtures.registry()
    }

    private static let sine = #"{"amplitude":0.8,"center":0.4,"phase":0.25,"rate":0.5,"shape":"sine"}"#
    private static let triangle = #"{"note":"keep me","rate":2,"shape":"triangle"}"#

    private func decode(lfosJSON: String) throws -> SceneDocument {
        let text = SceneFixtures.minimalText.dropLast() + ",\"lfos\":" + lfosJSON + "}"
        return try SceneDocument.decode(Array(text.utf8)).document
    }

    func testLFOsRoundTripVerbatimAndGiveIdenticalValues() throws {
        var document = try decode(lfosJSON: "[" + Self.sine + "," + Self.triangle + "]")
        document.bindings = [SceneBinding(source: .lfo(1), target: VisualParameterIDs.bloomIntensity,
                                          mapping: LinearMapping(outputStart: 0, outputEnd: 1))]
        document = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(document.bindings.first?.sourceID, "audio.lfo.1")
        XCTAssertEqual(document.lfos?.count, 2)
        XCTAssertEqual(document.lfos?[1].fields["note"], .string("keep me"), "unknown fields are kept")
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again, document)
        XCTAssertEqual(again.encoded(), document.encoded())
        let expected: [LFO?] = [try LFO(shape: .sine, rateHz: 0.5, phaseOffset: 0.25, amplitude: 0.8, center: 0.4),
                                try LFO(shape: .triangle, rateHz: 2)]
        XCTAssertEqual(again.lfoOscillators, expected)
        for t: UInt64 in [0, 123_456_789, 36_000_000_000_000] {
            XCTAssertEqual(again.lfoOscillators[0]?.value(elapsedNanoseconds: t), expected[0]?.value(elapsedNanoseconds: t))
        }
        XCTAssertTrue(document.validate(registry: registry).isEmpty, "\(document.validate(registry: registry))")
        // The binding from oscillator 1 is live after loading.
        let live = try document.liveState(registry: registry).state
        XCTAssertEqual(live.bindings.map(\.source), [.lfo(1)])
        XCTAssertEqual(live.lfos, document.lfos)
        // An oscillator written back reads back equal.
        XCTAssertEqual(SceneLFOEntry.read([SceneLFOEntry(expected[0]!)]).oscillators, [expected[0]])
    }

    func testSceneWithoutLFOsEncodesUnchanged() throws {
        let bytes = Array(SceneFixtures.minimalText.utf8)
        let document = try SceneDocument.decode(bytes).document
        XCTAssertNil(document.lfos)
        XCTAssertEqual(document.encoded(), bytes)
        XCTAssertTrue(document.lfoOscillators.isEmpty)
    }

    func testUnusableLFOsAreReportedAtTheirPathsAndKept() throws {
        let entries: [String] = [
            #"{"rate":25,"shape":"sine"}"#,                    // rate out of range
            #"{"rate":1,"shape":"square"}"#,                   // unknown shape (MOD-008's)
            #"{"shape":"sine"}"#,                              // missing rate
            #"{"amplitude":"big","rate":1,"shape":"sine"}"#,   // wrong type
            #"{"rate":1}"#,                                    // missing shape
            Self.sine,
        ]
        let document = try decode(lfosJSON: "[" + entries.joined(separator: ",") + "]")
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), [.invalidLFO, .unknownLFO, .invalidLFO, .invalidLFO, .invalidLFO])
        XCTAssertEqual(issues.map(\.path), ["$.lfos[0]", "$.lfos[1].shape", "$.lfos[2].rate", "$.lfos[3].amplitude", "$.lfos[4].shape"])
        XCTAssertTrue(issues.allSatisfy { (issue: SceneIssue) -> Bool in !issue.isError }, "warnings only")
        let oscillators = document.lfoOscillators
        XCTAssertEqual(oscillators.count, 6, "positions kept")
        XCTAssertEqual(oscillators.prefix(5).compactMap { $0 }.count, 0)
        XCTAssertNotNil(oscillators[5])
        // The scene loads, and capture writes the list back unchanged.
        let live = try document.liveState(registry: registry).state
        XCTAssertEqual(live.lfos, document.lfos)
        let saved = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(saved.lfos, document.lfos)
        let report = SceneRepairReport(document: saved, decodeWarnings: [], registry: registry)
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "unknownLFO" })
    }

    func testLimitAndMalformedEntries() throws {
        let nine = try decode(lfosJSON: "[" + Array(repeating: Self.sine, count: 9).joined(separator: ",") + "]")
        XCTAssertEqual(nine.lfoOscillators.count, 8)
        let issues = nine.validate(registry: registry)
        XCTAssertEqual(issues.map(\.path), ["$.lfos[8]"])
        XCTAssertEqual(issues.first?.code, .invalidLFO)
        XCTAssertThrowsError(try decode(lfosJSON: "[1]"))
        XCTAssertThrowsError(try decode(lfosJSON: "{}"))
        let tooMany = "[" + Array(repeating: "{}", count: 65).joined(separator: ",") + "]"
        XCTAssertThrowsError(try decode(lfosJSON: tooMany)) { (error: Error) in
            XCTAssertEqual(error as? SceneDecodeError, .tooMany(what: "lfos", count: 65, limit: 64))
        }
    }
}
