// SceneJSONFuzzTests.swift — QA-005-T09: scene JSON (SCN-001 decode and validation, MOD-013
// restore) under mutated bytes. Every input decodes to a document or a typed `SceneDecodeError`; an
// accepted document validates, restores its modulation, and its canonical bytes decode again
// (QA-005-R6; contract "Suites").
import FuzzKit
import ParameterGraph
import SceneFormat
import XCTest

final class SceneJSONFuzzTests: XCTestCase {
    static let budget = FuzzBudget(inputs: 800, maxInputBytes: 16_384)

    func testMutatedScenesDecodeOrRefuseWithTypedErrors() throws {
        let registry = try FuzzCorpora.registry()
        let corpus = FuzzCorpora.load("scene")
        let campaign = FuzzCampaign(name: "scene-json", seed: 0x05CE_0001, budget: Self.budget,
                                    strategies: FuzzMutation.json, corpus: corpus.items,
                                    customMutations: [FuzzJSON.mutation])
        var issues = 0
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            let decoded: SceneDecodeResult
            do throws(SceneDecodeError) {
                decoded = try SceneDocument.decode(input.bytes)
            } catch {
                return error.message.isEmpty ? .refused(violation: "decode error without a message: \(error)") : .refused()
            }
            issues += decoded.document.validate(registry: registry).count
            let restore = decoded.document.restoreModulation(registry: registry)
            issues += restore.issues.count
            let again = decoded.document.encoded()
            do {
                let second = try SceneDocument.decode(again)
                if second.document.encoded() != again {
                    return .accepted(violation: "canonical bytes are not a fixed point")
                }
            } catch {
                return .accepted(violation: "canonical bytes of an accepted scene do not decode: \(error)")
            }
            return .accepted()
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThanOrEqual(report.accepted, corpus.items.count, "the corpus itself decodes")
        XCTAssertGreaterThan(report.refused, report.inputs / 4, "mutations reach the refusals")
        print("QA-005 scene-json: \(issues) validation and restore issues reported as typed values")
    }
}
