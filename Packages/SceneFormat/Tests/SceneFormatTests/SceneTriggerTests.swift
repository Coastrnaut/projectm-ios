// SceneTriggerTests.swift — MOD-006-T06 (US3; MOD-006-R9, R10, S4; contract T4, T5): the optional `triggers` list in
// the scene document. CPU only, runs on Linux.
import Foundation
import ParameterGraph
@testable import SceneFormat
import XCTest

final class SceneTriggerTests: XCTestCase {
    private var registry: ParameterRegistry!

    override func setUpWithError() throws {
        registry = try SceneFixtures.registry()
    }

    private static let kick = #"{"action":"cue.next","high":0.6,"hold":0,"low":0.3,"minimumInterval":0.1,"source":"audio.kick"}"#
    private static let band = #"{"action":"blackout","high":0.8,"low":0.5,"note":"keep me","source":"audio.band.3"}"#

    private func decode(triggersJSON: String) throws -> SceneDocument {
        let text = SceneFixtures.minimalText.dropLast() + ",\"triggers\":" + triggersJSON + "}"
        return try SceneDocument.decode(Array(text.utf8)).document
    }

    /// Fire times of `bindings` for a kick/band pulse train (deterministic).
    private func fires(_ bindings: [ThresholdTriggerBinding]) throws -> [String] {
        let bank = ThresholdTriggerBank()
        try bank.set(bindings)
        var log: [String] = []
        for frame in 0..<120 {
            let level: Float = frame % 20 < 3 ? 0.95 : 0.05
            let bands: [Float] = [0, 0, 0, level]
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                bank.advance(frame: AudioFeatureFrame(bands: buffer, kick: level), timeNanoseconds: 1_000_000_000 + UInt64(frame) * 16_666_667) {
                    (action: ThresholdTriggerAction) -> Void in log.append("\(frame) \(action.rawValue)")
                }
            }
        }
        return log
    }

    func testTriggersRoundTripVerbatimAndBehaveIdentically() throws {
        let document = try decode(triggersJSON: "[" + Self.kick + "," + Self.band + "]")
        XCTAssertEqual(document.triggers?.count, 2)
        XCTAssertEqual(document.triggers?[1].fields["note"], .string("keep me"), "unknown fields are kept")
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again, document)
        XCTAssertEqual(again.encoded(), document.encoded())
        let bindings: [ThresholdTriggerBinding] = again.triggerBindings
        XCTAssertEqual(bindings, [
            ThresholdTriggerBinding(source: .kick, action: .cueNext, settings: ThresholdTriggerSettings(high: 0.6, low: 0.3)),
            ThresholdTriggerBinding(source: .band(3), action: .blackout, settings: ThresholdTriggerSettings(high: 0.8, low: 0.5)),
        ])
        let log: [String] = try fires(bindings)
        XCTAssertEqual(log.count, 12, "6 pulses × 2 triggers")
        XCTAssertEqual(log, try fires(document.triggerBindings))
        XCTAssertTrue(document.validate(registry: registry).isEmpty)
        // A binding written back reads back equal.
        let written = SceneTriggerEntry(bindings[0])
        XCTAssertEqual(SceneTriggerEntry.read([written]).bindings, [bindings[0]])
    }

    func testSceneWithoutTriggersEncodesUnchanged() throws {
        let bytes = Array(SceneFixtures.minimalText.utf8)
        let document = try SceneDocument.decode(bytes).document
        XCTAssertNil(document.triggers)
        XCTAssertEqual(document.encoded(), bytes)
        XCTAssertTrue(document.triggerBindings.isEmpty)
    }

    func testUnusableTriggersAreReportedAtTheirPathsAndKept() throws {
        let entries: [String] = [
            #"{"action":"cue.next","high":0.3,"low":0.4,"source":"audio.kick"}"#,          // low ≥ high
            #"{"action":"scene.go","high":0.6,"low":0.3,"source":"audio.kick"}"#,          // unknown action
            #"{"action":"cue.next","high":0.6,"low":0.3,"source":"audio.tempo"}"#,         // unknown source
            #"{"action":"cue.next","low":0.3,"source":"audio.kick"}"#,                     // missing high
            #"{"action":"cue.next","high":0.6,"hold":"long","low":0.3,"source":"audio.kick"}"#,   // wrong type
            Self.kick,
        ]
        let document = try decode(triggersJSON: "[" + entries.joined(separator: ",") + "]")
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), [.invalidTrigger, .unknownTrigger, .unknownTrigger, .invalidTrigger, .invalidTrigger])
        XCTAssertEqual(issues.map(\.path), ["$.triggers[0]", "$.triggers[1].action", "$.triggers[2].source", "$.triggers[3].high",
                                            "$.triggers[4].hold"])
        XCTAssertTrue(issues.allSatisfy { (issue: SceneIssue) -> Bool in !issue.isError }, "warnings only")
        XCTAssertEqual(document.triggerBindings.count, 1)
        // The scene loads, and capture writes the list back unchanged.
        let live = try document.liveState(registry: registry).state
        XCTAssertEqual(live.triggers, document.triggers)
        let saved = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(saved.triggers, document.triggers)
        let report = SceneRepairReport(document: saved, decodeWarnings: [], registry: registry)
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "unknownTrigger" })
    }

    func testLimitAndMalformedEntries() throws {
        let nine = try decode(triggersJSON: "[" + Array(repeating: Self.kick, count: 9).joined(separator: ",") + "]")
        XCTAssertEqual(nine.triggerBindings.count, 8)
        let issues = nine.validate(registry: registry)
        XCTAssertEqual(issues.map(\.path), ["$.triggers[8]"])
        XCTAssertEqual(issues.first?.code, .invalidTrigger)
        XCTAssertThrowsError(try decode(triggersJSON: "[1]"))
        XCTAssertThrowsError(try decode(triggersJSON: "{}"))
        let tooMany = "[" + Array(repeating: "{}", count: 65).joined(separator: ",") + "]"
        XCTAssertThrowsError(try decode(triggersJSON: tooMany)) { (error: Error) in
            XCTAssertEqual(error as? SceneDecodeError, .tooMany(what: "triggers", count: 65, limit: 64))
        }
    }
}
