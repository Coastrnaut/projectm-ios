// ExpressionCompileWorkTests.swift — SHD-010-T08, T11: compile work stays within the documented
// linear bounds for fixtures, a seeded fuzz and growing adversarial inputs; counts are deterministic;
// an informational host measurement runs only on request (SHD-010-R5, R7, R10; S3, S4; contract B4).
import Foundation
import ParameterExpression
import ParameterGraph
import XCTest

/// SplitMix64: a small deterministic generator.
private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}

final class ExpressionCompileWorkTests: XCTestCase {
    /// Limits loose enough that growing inputs are not cut off by a limit.
    private static let loose = ExpressionLimits(maximumSourceBytes: 1 << 20, maximumTokens: 1 << 20, maximumNodes: 1 << 20,
                                                maximumNesting: 1 << 20, maximumBindings: 1 << 20,
                                                maximumOperationCost: 1 << 30)

    private static var everyFixture: [String] {
        ExpressionFixtures.valid
            + ExpressionRejectionTests.table.map { (row: (source: String, message: String)) -> String in row.source }
            + PathologicalFixtures.table.map { (row: (name: String, source: String, message: String?)) -> String in row.source }
    }

    private func assertWithinBounds(_ source: String, limits: ExpressionLimits = .standard,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let work = CompiledExpression.measure(source: source, limits: limits).work
        XCTAssertLessThanOrEqual(work.lexerSteps, work.lexerBound, "lexer", file: file, line: line)
        XCTAssertLessThanOrEqual(work.parserSteps, work.parserBound, "parser", file: file, line: line)
        XCTAssertLessThanOrEqual(work.compilerSteps, work.compilerBound, "compiler", file: file, line: line)
        if limits == .standard {
            XCTAssertLessThanOrEqual(work.total, ExpressionCompileWork.ceiling(for: .standard), file: file, line: line)
        }
    }

    func testCeilingAtTheStandardLimits() {
        XCTAssertEqual(ExpressionCompileWork.ceiling(for: .standard), 3858)
        XCTAssertLessThanOrEqual(ExpressionCompileWork.ceiling(for: .standard), 4096, "contract B4")
    }

    func testEveryFixtureIsWithinTheBounds() {
        for source in Self.everyFixture { assertWithinBounds(source) }
    }

    func testSeededFuzzIsWithinTheBounds() {
        let words: [String] = ["let a = ", "let b = ", ";", "(", ")", "-", "+", "*", "abs(", "sin(", "pow(", ",", "1",
                               "1e400", "1.", "a", "b", "audio.bandMean", "audio.band.3", "time", " ", "\n", "\u{1}", "é"]
        var random = SplitMix64(state: 0x5D10)
        var refused = 0
        for _ in 0..<500 {
            var source = ""
            let pieces = random.below(400)
            for _ in 0..<pieces { source += words[random.below(words.count)] }
            assertWithinBounds(source)
            if case .failure = CompiledExpression.measure(source: source).result { refused += 1 }
        }
        XCTAssertGreaterThan(refused, 0)
    }

    /// A binding name of fixed width, so doubling the count doubles the bytes.
    private static func name(_ i: Int) -> String {
        let digits = String(i)
        return "a" + String(repeating: "0", count: 4 - digits.count) + digits
    }

    /// S4: doubling an adversarial input at most doubles the work plus a constant.
    func testWorkGrowsLinearly() {
        let name = Self.name
        let shapes: [(name: String, make: (Int) -> String)] = [
            ("nesting", { (n: Int) -> String in String(repeating: "(", count: n) + "1" + String(repeating: ")", count: n) }),
            ("unary", { (n: Int) -> String in String(repeating: "-", count: n) + "1" }),
            ("calls", { (n: Int) -> String in String(repeating: "abs(", count: n) + "1" + String(repeating: ")", count: n) }),
            ("flat sum", { (n: Int) -> String in String(repeating: "1+", count: n) + "1" }),
            ("bindings", { (n: Int) -> String in
                (0..<n).map { (i: Int) -> String in
                    i == 0 ? "let \(name(0)) = 1;" : "let \(name(i)) = \(name(i - 1)) + \(name(i - 1));"
                }.joined() + name(n - 1)
            }),
            ("ring", { (n: Int) -> String in
                (0..<n).map { (i: Int) -> String in "let \(name(i)) = \(name((i + 1) % n));" }.joined() + name(0)
            }),
            ("long name", { (n: Int) -> String in String(repeating: "a", count: n) }),
            ("malformed number", { (n: Int) -> String in String(repeating: "1", count: n) + "x" }),
            ("whitespace", { (n: Int) -> String in String(repeating: " \n", count: n) + "1" }),
        ]
        for shape in shapes {
            let small = CompiledExpression.measure(source: shape.make(200), limits: Self.loose).work
            let large = CompiledExpression.measure(source: shape.make(400), limits: Self.loose).work
            XCTAssertTrue(small.isWithinBounds && large.isWithinBounds, shape.name)
            XCTAssertLessThanOrEqual(large.total, 2 * small.total + 16, shape.name)
            XCTAssertGreaterThan(large.total, small.total, shape.name)
        }
    }

    func testCountsAreDeterministic() {
        for source in Self.everyFixture {
            let first = CompiledExpression.measure(source: source)
            let second = CompiledExpression.measure(source: source)
            XCTAssertEqual(first.work, second.work, source)
            switch (first.result, second.result) {
            case let (.success(a), .success(b)): XCTAssertEqual(a.bytes, b.bytes, source)
            case let (.failure(a), .failure(b)): XCTAssertEqual(a, b, source)
            default: XCTFail(source)
            }
        }
    }

    /// SHD-010-T11: informational only (no assertion on time). Run with
    /// `PARAMETER_EXPRESSION_BENCH=1 swift test -c release --filter ExpressionCompileWorkTests/testInformationalHostCost`.
    func testInformationalHostCost() throws {
        guard ProcessInfo.processInfo.environment["PARAMETER_EXPRESSION_BENCH"] == "1" else {
            throw XCTSkip("informational measurement; set PARAMETER_EXPRESSION_BENCH=1")
        }
        let bands = [Float](repeating: 0.5, count: 128)
        let formulas: [(name: String, source: String)] = [
            ("add", Array(repeating: "1", count: 64).joined(separator: "+")),
            ("sin", Array(repeating: "sin(time)", count: 42).joined(separator: "+")),
            ("pow", Array(repeating: "pow(time,1.5)", count: 32).joined(separator: "+")),
            ("bandMean (128 bands)", Array(repeating: "audio.bandMean", count: 34).joined(separator: "+")),
            ("full budget", Array(repeating: "sin(time)", count: 41).joined(separator: "+") + "+sqrt(audio.bandMean)+1"),
        ]
        let clock = ContinuousClock()
        for formula in formulas {
            let compiled = try CompiledExpression(source: formula.source)
            var frameSet = ExpressionFrameSet()
            while (try? frameSet.admit(compiled)) != nil {}
            let snapshot = frameSet.snapshot
            var results = [Double](repeating: 0, count: 32)
            let iterations = 2_000
            var sink = 0.0
            let elapsed = bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Duration in
                results.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<Double>) -> Duration in
                    clock.measure {
                        for i in 0..<iterations {
                            let inputs = ExpressionInputs(frame: AudioFeatureFrame(bands: buffer, onset: 0.5, beatConfidence: 0.5),
                                                          timeSeconds: Double(i) * 0.016)
                            _ = snapshot.evaluate(inputs, into: out)
                            sink += out[0]
                        }
                    }
                }
            }
            let nanoseconds = Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9
            let perFrame = nanoseconds / Double(iterations)
            print(String(format: "SHD-010 bench %@: %d formulas, cost %d/frame, %.0f ns/frame, %.2f ns/unit (sink %.1f)",
                         formula.name, snapshot.expressions.count, snapshot.operationCost, perFrame,
                         perFrame / Double(snapshot.operationCost), sink))
        }
    }
}
