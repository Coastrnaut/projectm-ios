// BoundedJSONFuzzTests.swift — QA-005-T13: the shared JSON shape check (FILE-007) under mutated
// documents, with its own `bytesExamined` counter as the hang bound: never more than the input's
// length, exactly the length when accepted, and 0 for a size refusal. Limits alternate between the
// scene archive manifest schema and a tight set that the mutations hit often (QA-005-R4, R6).
import Foundation
import FuzzKit
import LocalPortability
import SceneArchive
import XCTest

final class BoundedJSONImportFuzzTests: XCTestCase {
    static let budget = FuzzBudget(inputs: 3_000, maxInputBytes: 4_096)
    static let limitSets: [JSONLimits] = [
        SceneArchiveFormat.manifestSchema.limits,
        JSONLimits(maxBytes: 2_048, maxDepth: 4, maxStringBytes: 32, maxNumberBytes: 12, maxElements: 8),
        JSONLimits(maxBytes: 4_096, maxDepth: 64, maxStringBytes: 4_096, maxNumberBytes: 64, maxElements: 4_096,
                   rejectsDuplicateKeys: false, requiresObjectRoot: false),
    ]

    func testMutatedDocumentsReturnTypedShapesWithinTheirWorkBound() {
        let corpus = FuzzCorpora.load("json")
        let campaign = FuzzCampaign(name: "bounded-json", seed: 0x0F11_E005, budget: Self.budget,
                                    strategies: FuzzMutation.json, corpus: corpus.items,
                                    workBound: { (n: Int) -> Int in n },
                                    customMutations: [FuzzJSON.mutation])
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            let limits = Self.limitSets[input.iteration % Self.limitSets.count]
            let outcome = BoundedJSON.check(input.bytes, limits: limits)
            let sameForData = BoundedJSON.check(Data(input.bytes), limits: limits)
            let differs: String? = sameForData == outcome ? nil : "the [UInt8] and Data entry points disagree"
            switch outcome.result {
            case .success(let summary):
                if outcome.bytesExamined != input.bytes.count || summary.bytesExamined != input.bytes.count {
                    return .accepted(work: outcome.bytesExamined, violation: "accepted without examining every byte")
                }
                return .accepted(work: outcome.bytesExamined, violation: differs)
            case .failure(.tooLarge):
                return .refused(work: outcome.bytesExamined, violation: outcome.bytesExamined == 0 ? differs : "size refusal examined bytes")
            case .failure:
                return .refused(work: outcome.bytesExamined, violation: differs)
            }
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThan(report.accepted, 100)
        XCTAssertGreaterThan(report.refused, 100)
    }
}
