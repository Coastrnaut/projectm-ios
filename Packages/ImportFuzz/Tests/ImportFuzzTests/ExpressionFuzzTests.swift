// ExpressionFuzzTests.swift — QA-005-T13: the expression language (SHD-009) under mutated source
// text, with the SHD-010 compile-work counters as the hang bound: every phase within its linear
// bound and the total within the ceiling at the standard limits (contract B4: ≤ 4,096). An accepted
// expression compiles to the same bytes twice (QA-005-R4, R6).
import FuzzKit
import ParameterExpression
import XCTest

final class ExpressionImportFuzzTests: XCTestCase {
    static let budget = FuzzBudget(inputs: 3_000, maxInputBytes: ExpressionLimits.standard.maximumSourceBytes + 8)

    func testMutatedSourcesCompileOrRefuseWithinTheirWorkBound() {
        let corpus = FuzzCorpora.load("expression")
        let ceiling = ExpressionCompileWork.ceiling(for: .standard)
        let campaign = FuzzCampaign(name: "expression", seed: 0x05D0_9001, budget: Self.budget,
                                    strategies: FuzzMutation.text, corpus: corpus.items,
                                    workBound: { (_: Int) -> Int in ceiling })
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            let source = String(decoding: input.bytes, as: UTF8.self)
            let (result, work) = CompiledExpression.measure(source: source)
            let violation: String? = work.isWithinBounds ? nil
                : "compile work outside contract B4: lexer \(work.lexerSteps)/\(work.lexerBound), parser \(work.parserSteps)/\(work.parserBound), compiler \(work.compilerSteps)/\(work.compilerBound)"
            switch result {
            case .success(let compiled):
                if case .success(let again) = CompiledExpression.measure(source: source).result, again.bytes == compiled.bytes {
                    return .accepted(work: work.total, violation: violation)
                }
                return .accepted(work: work.total, violation: violation ?? "compiling twice gives different bytes")
            case .failure:
                return .refused(work: work.total, violation: violation)
            }
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThanOrEqual(report.accepted, corpus.items.count)
        XCTAssertLessThanOrEqual(report.maxWork, 4_096)
    }
}
