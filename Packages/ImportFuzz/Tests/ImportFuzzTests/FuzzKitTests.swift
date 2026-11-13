// FuzzKitTests.swift — QA-005-T06, T07: the harness itself (determinism, caps, budgets,
// configuration, the hang-bound report) and the corpus budget (QA-005-S3, S4; contract H1-H4).
import FuzzKit
import XCTest

final class FuzzKitTests: XCTestCase {
    private let corpus: [[UInt8]] = [Array("{\"a\":[1,2,3]}".utf8), Array("/x\0\0,f\0\0\0\0\0\0".utf8), []]
    private let fixed = FuzzConfiguration()

    private func campaign(seed: UInt64, inputs: Int = 300, cap: Int = 64,
                          strategies: [FuzzMutation] = FuzzMutation.allCases,
                          workBound: (@Sendable (Int) -> Int)? = nil) -> FuzzCampaign {
        FuzzCampaign(name: "self", seed: seed, budget: FuzzBudget(inputs: inputs, maxInputBytes: cap),
                     strategies: strategies, corpus: corpus, configuration: fixed, workBound: workBound)
    }

    func testSameSeedGivesTheSameInputsAndAnotherSeedDoesNot() {
        let a = campaign(seed: 1).run { (_: FuzzInput) -> FuzzOutcome in .refused() }
        let b = campaign(seed: 1).run { (_: FuzzInput) -> FuzzOutcome in .refused() }
        let c = campaign(seed: 2).run { (_: FuzzInput) -> FuzzOutcome in .refused() }
        XCTAssertEqual(a.digest, b.digest)
        XCTAssertEqual(a.bytes, b.bytes)
        XCTAssertNotEqual(a.digest, c.digest)
        XCTAssertEqual(campaign(seed: 9).input(57).bytes, campaign(seed: 9).input(57).bytes, "input i depends only on (seed, i)")
        // Pinned values: SplitMix64 from 0 (reference sequence), so the generator never drifts.
        var rng = FuzzRandom(state: 0)
        XCTAssertEqual(rng.next(), 0xE220_A839_7B1D_CDAF)
        XCTAssertEqual(rng.next(), 0x6E78_9E6A_A1B9_65F4)
    }

    func testEveryStrategyRespectsTheCapOnEveryInputShape() {
        var rng = FuzzRandom(state: 0x0005)
        let inputs: [[UInt8]] = [[], [0x7B], Array(repeating: 0x5B, count: 40), rng.bytes(count: 200)]
        for strategy in FuzzMutation.allCases {
            for cap in [0, 1, 16, 64] {
                for input in inputs {
                    for _ in 0..<20 {
                        let out = strategy.apply(to: input, other: inputs[3], rng: &rng, cap: cap)
                        XCTAssertLessThanOrEqual(out.count, cap, "\(strategy) cap \(cap) input \(input.count)")
                    }
                }
            }
        }
        let report = campaign(seed: 3, inputs: 2_000, cap: 48).run { (input: FuzzInput) -> FuzzOutcome in
            input.bytes.count <= 48 ? .accepted() : .refused(violation: "over cap")
        }
        XCTAssertTrue(report.violations.isEmpty)
        for strategy in FuzzMutation.allCases { XCTAssertGreaterThan(report.strategyCounts[strategy] ?? 0, 0, "\(strategy) never used") }
    }

    func testInputAndByteBudgetsEachStopARun() {
        XCTAssertEqual(campaign(seed: 4, inputs: 37).run { (_: FuzzInput) -> FuzzOutcome in .refused() }.inputs, 37)
        let small = FuzzCampaign(name: "bytes", seed: 4, budget: FuzzBudget(inputs: 10_000, maxInputBytes: 64, maxRunBytes: 500),
                                 strategies: FuzzMutation.generic, corpus: corpus, configuration: fixed)
        let report = small.run { (_: FuzzInput) -> FuzzOutcome in .refused() }
        XCTAssertLessThan(report.inputs, 10_000)
        XCTAssertGreaterThanOrEqual(report.bytes, 500)
        XCTAssertLessThan(report.bytes, 500 + 64)
    }

    func testConfigurationParsing() {
        XCTAssertNil(FuzzConfiguration.parseIterations(nil))
        XCTAssertNil(FuzzConfiguration.parseIterations(""))
        XCTAssertNil(FuzzConfiguration.parseIterations("0"))
        XCTAssertNil(FuzzConfiguration.parseIterations("-3"))
        XCTAssertNil(FuzzConfiguration.parseIterations("abc"))
        XCTAssertNil(FuzzConfiguration.parseIterations("1e3"))
        XCTAssertEqual(FuzzConfiguration.parseIterations("250"), 250)
        XCTAssertEqual(FuzzConfiguration.parseIterations("999999"), 100_000)
        XCTAssertEqual(FuzzConfiguration.parseIterations("99999999999999999999999"), 100_000)
        XCTAssertEqual(FuzzConfiguration.parseSeed("0x1F"), 31)
        XCTAssertEqual(FuzzConfiguration.parseSeed("42"), 42)
        XCTAssertNil(FuzzConfiguration.parseSeed("seed"))
        let env = FuzzConfiguration(environment: ["FUZZ_ITERATIONS": "120", "FUZZ_SEED": "0x10"])
        XCTAssertEqual(env.budget(FuzzBudget(inputs: 5, maxInputBytes: 8)).inputs, 120)
        XCTAssertEqual(env.budget(FuzzBudget(inputs: 5, maxInputBytes: 8), divisor: 25).inputs, 4)
        XCTAssertEqual(env.seed(0x01), 0x11)
        XCTAssertEqual(FuzzConfiguration(environment: [:]).budget(FuzzBudget(inputs: 5, maxInputBytes: 8)).inputs, 5)
    }

    func testWorkBoundViolationsNameTheInput() {
        let report = campaign(seed: 5, inputs: 50, workBound: { (n: Int) -> Int in n }).run { (input: FuzzInput) -> FuzzOutcome in
            .refused(work: input.iteration == 20 ? input.bytes.count + 1 : input.bytes.count)
        }
        XCTAssertEqual(report.violations.count, 1)
        let message = report.violations.first ?? ""
        XCTAssertTrue(message.contains("iteration=20"), message)
        XCTAssertTrue(message.contains("seed=0x"), message)
        XCTAssertTrue(message.contains("strategies=["), message)
        XCTAssertTrue(message.contains("hang bound"), message)
    }

    func testCorpusBudget() {
        var total = 0
        for format in FuzzCorpora.formats {
            let corpus = FuzzCorpora.load(format)
            XCTAssertGreaterThanOrEqual(corpus.items.count, 3, "\(format) needs at least 3 seed items (QA-005-S4)")
            total += corpus.totalBytes
        }
        XCTAssertLessThanOrEqual(total, 200_000, "the seed corpus stays at or below 200 KB (QA-005-R5)")
        print("QA-005 corpus: \(total) bytes in \(FuzzCorpora.formats.count) formats")
    }
}
