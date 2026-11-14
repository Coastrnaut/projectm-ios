// SceneMacroTests.swift — MOD-010-T04 (US2; MOD-010-R7, R8, S1, S3; contract M3): the optional `macros` list in the
// scene document, on the real visual catalog (MOD-001). CPU only, runs on Linux.
import Foundation
import ParameterGraph
@testable import SceneFormat
import VisualParameters
import XCTest

final class SceneMacroTests: XCTestCase {
    private var registry: ParameterRegistry!

    override func setUpWithError() throws {
        registry = try SceneFixtures.registry()
    }

    /// The acceptance macro: glow intensity easeIn 2 (0.1…0.9), glow radius log 9 inverted (0.01…0.05), circular bars.
    private static let acceptanceJSON = #"{"name":"Glow sweep","note":"keep me","targets":["#
        + #"{"curve":"easeIn:2.0","maximum":0.9,"minimum":0.1,"parameter":"effect.bloom.intensity"},"#
        + #"{"curve":"log:9.0","invert":true,"maximum":0.05,"minimum":0.01,"parameter":"effect.bloom.radius"},"#
        + #"{"parameter":"visual.circularSpectrum.barCount"}],"value":0.25}"#

    private func decode(macrosJSON: String) throws -> SceneDocument {
        let text = SceneFixtures.minimalText.dropLast() + ",\"macros\":" + macrosJSON + "}"
        return try SceneDocument.decode(Array(text.utf8)).document
    }

    private func values(_ macro: ParameterMacro, at m: Double) -> [ParameterID: ParameterValue] {
        var result: [ParameterID: ParameterValue] = [:]
        for a in macro.evaluate(at: m, registry: registry).assignments { result[a.parameter] = a.value }
        return result
    }

    func testAcceptanceMacroRoundTripsVerbatimAndGivesItsCurvesValues() throws {
        let document = try decode(macrosJSON: "[" + Self.acceptanceJSON + "]")
        XCTAssertTrue(document.validate(registry: registry).isEmpty, "\(document.validate(registry: registry))")
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again, document)
        XCTAssertEqual(again.encoded(), document.encoded())
        XCTAssertEqual(again.macros?.first?.fields["note"], .string("keep me"), "unknown fields are kept")
        let macro = try XCTUnwrap(again.liveMacros(registry: registry).first ?? nil)
        XCTAssertEqual(macro.name, "Glow sweep")
        XCTAssertEqual(macro.value, 0.25)
        XCTAssertEqual(macro.targets.map(\.curve), [.easeIn(exponent: 2), .logarithmic(strength: 9), .linear], "saved curves restored")
        XCTAssertEqual(macro.targets.map(\.inverted), [false, true, false])
        let bars: [Double: String] = [0: "16", 0.25: "32", 0.5: "64", 1: "128"]
        for m: Double in [0, 0.25, 0.5, 1] {
            let v = values(macro, at: m)
            let intensity: Double = try XCTUnwrap(v[VisualParameterIDs.bloomIntensity]?.doubleValue)
            let radius: Double = try XCTUnwrap(v[VisualParameterIDs.bloomRadius]?.doubleValue)
            XCTAssertEqual(intensity, 0.1 + pow(m, 2) * 0.8, accuracy: 1e-9, "m = \(m)")
            XCTAssertEqual(radius, 0.01 + log(1 + 9 * (1 - m)) / log(10) * 0.04, accuracy: 1e-9, "m = \(m)")
            XCTAssertEqual(v[VisualParameterIDs.circularSpectrumBarCount], .enumeration(bars[m]!), "m = \(m)")
        }
        XCTAssertEqual(values(macro, at: 0)[VisualParameterIDs.bloomRadius], .continuous(0.05), "exact end")
        XCTAssertEqual(values(macro, at: 1)[VisualParameterIDs.bloomIntensity], .continuous(0.9), "exact end")
        // Live state carries the list; capture writes it back unchanged.
        let live = try again.liveState(registry: registry).state
        XCTAssertEqual(live.macros, again.macros)
        let saved = try SceneDocument(capturing: live, id: again.id, name: again.name)
        XCTAssertEqual(saved.macros, again.macros)
    }

    func testWrittenMacroReadsBackEqualAndSettingValueKeepsUnknownFields() throws {
        let macro = ParameterMacro(name: "Sweep", value: 0.5, targets: [
            MacroTarget(parameter: VisualParameterIDs.bloomThreshold, curve: .piecewise([CurvePoint(x: 0.5, y: 0.25)]),
                        outputMinimum: 0.2, outputMaximum: 0.8, inverted: true),
            MacroTarget(parameter: VisualParameterIDs.linearSpectrumOrientation),
        ])
        let entry = SceneMacroEntry(macro)
        XCTAssertEqual(SceneMacroEntry.read([entry], registry: registry).macros, [macro])
        var document = try decode(macrosJSON: "[" + Self.acceptanceJSON + "]")
        let first: SceneMacroEntry = try XCTUnwrap(document.macros?[0])
        document.macros = [first.settingValue(0.75)]
        let again = try SceneDocument.decode(document.encoded()).document
        XCTAssertEqual(again.liveMacros(registry: registry).first??.value, 0.75)
        XCTAssertEqual(again.macros?.first?.fields["note"], .string("keep me"))
    }

    func testSceneWithoutMacrosEncodesUnchanged() throws {
        let bytes = Array(SceneFixtures.minimalText.utf8)
        let document = try SceneDocument.decode(bytes).document
        XCTAssertNil(document.macros)
        XCTAssertEqual(document.encoded(), bytes)
        XCTAssertTrue(document.liveMacros(registry: registry).isEmpty)
    }

    func testUnusableMacrosAndTargetsAreReportedAtTheirPathsAndKept() throws {
        let entries: [String] = [
            #"{"targets":[],"value":0}"#,                                                  // 0: missing name
            #"{"name":"A","targets":[],"value":"half"}"#,                                  // 1: wrong value type
            #"{"name":"B","targets":{},"value":0}"#,                                       // 2: targets not a list
            #"{"name":"C","targets":["#                                                    // 3: mixed targets
                + #"{"parameter":"effect.future.knob"},"#                                  //    unknown parameter
                + #"{"parameter":"effect.bloom.enabled"},"#                                //    on/off refused
                + #"{"curve":"wobble:3","parameter":"effect.bloom.radius"},"#              //    bad curve text
                + #"{"curve":"easeIn:0.5","parameter":"effect.bloom.radius"},"#            //    invalid curve
                + #"{"maximum":0.1,"minimum":0.5,"parameter":"effect.bloom.threshold"},"#  //    minimum > maximum
                + #"{"invert":"yes","parameter":"effect.bloom.knee"},"#                    //    wrong invert type
                + #"{"parameter":"effect.bloom.intensity"},"#                              //    usable
                + #"{"parameter":"effect.bloom.intensity"}"#                               //    duplicate
                + #"],"value":1}"#,
        ]
        let document = try decode(macrosJSON: "[" + entries.joined(separator: ",") + "]")
        let issues = document.validate(registry: registry)
        XCTAssertEqual(issues.map(\.code), [.invalidMacro, .invalidMacro, .invalidMacro, .unknownMacroTarget, .invalidMacro,
                                            .invalidMacro, .invalidMacro, .invalidMacro, .invalidMacro, .invalidMacro])
        XCTAssertEqual(issues.map(\.path), ["$.macros[0].name", "$.macros[1].value", "$.macros[2].targets",
                                            "$.macros[3].targets[0].parameter", "$.macros[3].targets[1]",
                                            "$.macros[3].targets[2].curve", "$.macros[3].targets[3]", "$.macros[3].targets[4]",
                                            "$.macros[3].targets[5].invert", "$.macros[3].targets[7]"])
        XCTAssertTrue(issues.allSatisfy { (issue: SceneIssue) -> Bool in !issue.isError }, "warnings only")
        let macros = document.liveMacros(registry: registry)
        XCTAssertEqual(macros.count, 4, "positions kept")
        XCTAssertEqual(macros.prefix(3).compactMap { $0 }.count, 0)
        XCTAssertEqual(macros[3]?.targets.map(\.parameter), [VisualParameterIDs.bloomIntensity], "the usable target stays live")
        // The scene loads; capture writes the list back unchanged; SCN-012 reports the codes.
        let live = try document.liveState(registry: registry).state
        let saved = try SceneDocument(capturing: live, id: document.id, name: document.name)
        XCTAssertEqual(saved.macros, document.macros)
        let report = SceneRepairReport(document: saved, decodeWarnings: [], registry: registry)
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "unknownMacroTarget" })
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "invalidMacro" })
    }

    func testLimitsAndMalformedEntries() throws {
        let nine = try decode(macrosJSON: "[" + Array(repeating: Self.acceptanceJSON, count: 9).joined(separator: ",") + "]")
        XCTAssertEqual(nine.liveMacros(registry: registry).count, 8)
        XCTAssertEqual(nine.validate(registry: registry).map(\.path), ["$.macros[8]"])
        let ids: [String] = ["effect.bloom.intensity", "effect.bloom.radius", "effect.bloom.threshold", "effect.bloom.knee",
                             "visual.circularSpectrum.barCount", "visual.circularSpectrum.innerRadius", "visual.circularSpectrum.gap",
                             "visual.linearSpectrum.spacing", "visual.linearSpectrum.peakHold"]
        let targets: String = ids.map { (id: String) -> String in "{\"parameter\":\"\(id)\"}" }.joined(separator: ",")
        let wide = try decode(macrosJSON: "[{\"name\":\"W\",\"targets\":[" + targets + "],\"value\":0}]")
        let issues = wide.validate(registry: registry)
        XCTAssertEqual(issues.map(\.path), ["$.macros[0].targets[8]"], "\(issues)")
        XCTAssertEqual(wide.liveMacros(registry: registry).first??.targets.count, 8)
        XCTAssertThrowsError(try decode(macrosJSON: "[1]"))
        XCTAssertThrowsError(try decode(macrosJSON: "{}"))
        let tooMany = "[" + Array(repeating: "{}", count: 65).joined(separator: ",") + "]"
        XCTAssertThrowsError(try decode(macrosJSON: tooMany)) { (error: Error) in
            XCTAssertEqual(error as? SceneDecodeError, .tooMany(what: "macros", count: 65, limit: 64))
        }
    }
}
