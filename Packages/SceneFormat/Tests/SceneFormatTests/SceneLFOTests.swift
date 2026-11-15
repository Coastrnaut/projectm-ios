// SceneLFOTests.swift — MOD-007-T06 (US3; MOD-007-R5, R7, R8, S4; contract L5, L6): the optional `lfos` list in
// the scene document and `audio.lfo.<index>` bindings. CPU only, runs on Linux.
// MOD-009-T06 (MOD-009-R7, R8, S5; contract T5): the optional `sync` object of an entry.
// MOD-008-T09 (MOD-008-R9, S3; contract S8): stepped shapes and the optional `duty`, `seed` and `glide` fields.
// MOD-016-T08 (MOD-016-R9, S4; contract W8): the `randomWalk` shape and the optional `smoothness` field.
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
            #"{"rate":1,"shape":"noise"}"#,                    // unknown shape
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

    // MARK: MOD-009 sync

    private static let synced = #"{"rate":0.25,"shape":"sine","sync":{"beats":4,"note":"kept"}}"#

    func testSyncRoundTripsVerbatim() throws {
        let document = try decode(lfosJSON: "[" + Self.synced + "," + Self.sine + "]")
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again, document)
        XCTAssertEqual(again.encoded(), document.encoded(), "byte-identical re-encode")
        XCTAssertEqual(again.lfos?[0].fields["sync"]?.objectValue?["note"], .string("kept"), "unknown keys inside sync are kept")
        let expected = try LFO(shape: .sine, rateHz: 0.25, sync: LFOSync(beatsPerCycle: 4))
        XCTAssertEqual(again.lfoOscillators[0], expected)
        XCTAssertNil(again.lfoOscillators[1]?.sync)
        XCTAssertTrue(again.validate(registry: registry).isEmpty, "\(again.validate(registry: registry))")
        // A live oscillator writes `sync` only when set, and reads back equal.
        let written = SceneLFOEntry(expected)
        XCTAssertEqual(written.fields["sync"], .object(["beats": .double(4)]))
        XCTAssertEqual(SceneLFOEntry.read([written]).oscillators, [expected])
        XCTAssertNil(SceneLFOEntry(try LFO(shape: .sine, rateHz: 1)).fields["sync"], "no sync: no new field")
        for beats in LFOSync.allowedBeatsPerCycle {
            let lfo = try LFO(shape: .triangle, rateHz: 1, sync: LFOSync(beatsPerCycle: beats))
            let decoded = try decode(lfosJSON: "[" + String(decoding: SceneJSONWriter.write(.object(SceneLFOEntry(lfo).fields)), as: UTF8.self) + "]")
            XCTAssertEqual(decoded.lfoOscillators, [lfo], "\(beats) beats survive JSON")
        }
    }

    func testInvalidAndUnknownSyncAreReportedAndRunUnsynced() throws {
        let entries: [String] = [
            #"{"rate":0.5,"shape":"sine","sync":2}"#,                    // not an object
            #"{"rate":0.5,"shape":"sine","sync":{"beats":"x"}}"#,        // not a number
            #"{"rate":0.5,"shape":"sine","sync":{}}"#,                   // missing beats
            #"{"rate":0.5,"shape":"sine","sync":{"beats":-1}}"#,         // not positive
            #"{"rate":0.5,"shape":"sine","sync":{"beats":0.333}}"#,      // a length this version does not know
            #"{"rate":25,"shape":"sine","sync":{"beats":0.333}}"#,       // MOD-007 error first; sync not examined
        ]
        let document = try decode(lfosJSON: "[" + entries.joined(separator: ",") + "]")
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), [.invalidLFOSync, .invalidLFOSync, .invalidLFOSync, .invalidLFOSync, .unknownLFOSync, .invalidLFO])
        XCTAssertEqual(issues.map(\.path), ["$.lfos[0].sync", "$.lfos[1].sync.beats", "$.lfos[2].sync.beats", "$.lfos[3].sync.beats",
                                            "$.lfos[4].sync.beats", "$.lfos[5]"])
        XCTAssertTrue(issues.allSatisfy { (issue: SceneIssue) -> Bool in !issue.isError }, "warnings only")
        let oscillators = document.lfoOscillators
        let unsynced = try LFO(shape: .sine, rateHz: 0.5)
        XCTAssertEqual(Array(oscillators.prefix(5)), Array(repeating: unsynced, count: 5), "live at the stored rate, unsynced")
        XCTAssertNil(oscillators[5])
        let live = try document.liveState(registry: registry).state
        let saved = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(saved.lfos, document.lfos, "kept verbatim for re-save")
        let report = SceneRepairReport(document: saved, decodeWarnings: [], registry: registry)
        let codes: Set<String> = Set(report.entries.map { (e: SceneRepairReport.Entry) -> String in e.code })
        XCTAssertTrue(codes.isSuperset(of: ["invalidLFOSync", "unknownLFOSync"]))
    }

    // MARK: MOD-008 stepped shapes

    func testSteppedShapesRoundTripShapeDutySeedAndGlide() throws {
        let square = try LFO(shape: .square, rateHz: 2, dutyCycle: 0.3)
        let hold = try LFO(shape: .sampleHold, rateHz: 4, phaseOffset: 0.5, seed: 4_294_967_295, glide: 0.25)
        let unseeded = try LFO(shape: .sampleHold, rateHz: 1)
        let entries: [SceneLFOEntry] = [SceneLFOEntry(square), SceneLFOEntry(hold), SceneLFOEntry(unseeded)]
        XCTAssertEqual(entries[0].fields["duty"], .double(0.3))
        XCTAssertNil(entries[0].fields["seed"])
        XCTAssertEqual(entries[1].fields["seed"], .integer(4_294_967_295))
        XCTAssertEqual(entries[1].fields["glide"], .double(0.25))
        XCTAssertNil(entries[2].fields["seed"], "an unseeded oscillator writes no seed")
        XCTAssertNil(entries[2].fields["glide"], "glide 0 is not written")
        XCTAssertNil(SceneLFOEntry(try LFO(shape: .sine, rateHz: 1)).fields["duty"], "sine writes nothing new")
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.lfos = entries
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.lfos, entries)
        XCTAssertEqual(again.lfoOscillators, [square, hold, unseeded], "shape, duty, seed and glide are kept exactly")
        XCTAssertTrue(again.validate(registry: registry).isEmpty, "\(again.validate(registry: registry))")
        for t: UInt64 in [0, 250_000_001, 3_600_000_000_000] {
            XCTAssertEqual(again.lfoOscillators[1]?.value(elapsedNanoseconds: t), hold.value(elapsedNanoseconds: t),
                           "the same seed and timebase give the same step values after a round trip")
        }
    }

    func testInvalidSteppedFieldsAreReportedAndKept() throws {
        let entries: [String] = [
            #"{"duty":0.99,"rate":1,"shape":"square"}"#,       // duty out of range
            #"{"glide":2,"rate":1,"shape":"sampleHold"}"#,     // glide out of range
            #"{"rate":1,"seed":-1,"shape":"sampleHold"}"#,     // negative seed
            #"{"rate":1,"seed":1.5,"shape":"sampleHold"}"#,    // not a whole number
            #"{"rate":1,"seed":4294967296,"shape":"sampleHold"}"#,   // beyond 32 bits
            #"{"duty":"wide","rate":1,"shape":"square"}"#,     // wrong type
            #"{"rate":1,"seed":12,"shape":"sampleHold"}"#,
        ]
        let document = try decode(lfosJSON: "[" + entries.joined(separator: ",") + "]")
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), Array(repeating: SceneIssue.Code.invalidLFO, count: 6))
        XCTAssertEqual(issues.map(\.path), ["$.lfos[0]", "$.lfos[1]", "$.lfos[2].seed", "$.lfos[3].seed", "$.lfos[4].seed",
                                            "$.lfos[5].duty"])
        let oscillators = document.lfoOscillators
        XCTAssertEqual(oscillators.prefix(6).compactMap { $0 }.count, 0, "unusable entries are nil, positions kept")
        XCTAssertEqual(oscillators[6], try LFO(shape: .sampleHold, rateHz: 1, seed: 12))
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.lfos, document.lfos, "entries are kept verbatim for re-save")
    }

    // MARK: MOD-016 random walk

    func testRandomWalkRoundTripsEveryField() throws {
        let walk = try LFO(shape: .randomWalk, rateHz: 0.75, phaseOffset: 0.125, amplitude: 0.6, center: 0.35,
                           sync: LFOSync(beatsPerCycle: 4), seed: 2_026, smoothness: 0.4)
        let plain = try LFO(shape: .randomWalk, rateHz: 1)
        let entries: [SceneLFOEntry] = [SceneLFOEntry(walk), SceneLFOEntry(plain)]
        XCTAssertEqual(entries[0].fields["shape"], .string("randomWalk"))
        XCTAssertEqual(entries[0].fields["smoothness"], .double(0.4))
        XCTAssertEqual(entries[0].fields["seed"], .integer(2_026))
        XCTAssertNil(entries[1].fields["smoothness"], "the default smoothness 1 is not written")
        XCTAssertNil(entries[1].fields["glide"])
        XCTAssertNil(entries[1].fields["duty"])
        for other in [LFOShape.sine, .triangle, .square, .sampleHold] {
            let lfo = try LFO(shape: other, rateHz: 1, smoothness: 0.5)
            XCTAssertNil(SceneLFOEntry(lfo).fields["smoothness"], "\(other) writes no smoothness")
        }
        var document = try SceneDocument.decode(Array(SceneFixtures.minimalText.utf8)).document
        document.lfos = entries
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.lfos, entries)
        XCTAssertEqual(again.lfoOscillators, [walk, plain], "shape, rate, sync, phase, depth, centre, smoothness and seed kept")
        XCTAssertTrue(again.validate(registry: registry).isEmpty, "\(again.validate(registry: registry))")
        for t: UInt64 in [0, 333_333_333, 36_000_000_000_000] {
            XCTAssertEqual(again.lfoOscillators[0]?.value(elapsedNanoseconds: t, tempoBPM: 128),
                           walk.value(elapsedNanoseconds: t, tempoBPM: 128),
                           "the same seed and timebase give identical values after a round trip")
        }
    }

    func testInvalidSmoothnessIsReportedAndKept() throws {
        let entries: [String] = [
            #"{"rate":1,"shape":"randomWalk","smoothness":1.5}"#,
            #"{"rate":1,"shape":"randomWalk","smoothness":-1}"#,
            #"{"rate":1,"shape":"randomWalk","smoothness":"x"}"#,
            #"{"rate":1,"shape":"randomWalk","smoothness":0}"#,
        ]
        let document = try decode(lfosJSON: "[" + entries.joined(separator: ",") + "]")
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), Array(repeating: SceneIssue.Code.invalidLFO, count: 3))
        XCTAssertEqual(issues.map(\.path), ["$.lfos[0]", "$.lfos[1]", "$.lfos[2].smoothness"])
        let oscillators = document.lfoOscillators
        XCTAssertEqual(oscillators.prefix(3).compactMap { $0 }.count, 0, "unusable entries are nil, positions kept")
        XCTAssertEqual(oscillators[3], try LFO(shape: .randomWalk, rateHz: 1, smoothness: 0))
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.lfos, document.lfos, "entries are kept verbatim for re-save")
    }
}
