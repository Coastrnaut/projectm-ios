// ExpressionPathologicalTests.swift — SHD-010-T07: pathological fixtures are refused with their exact
// message before any evaluation, or compiled with a bounded cost (SHD-010-R1, R6; S1; contract B3,
// B5).
import ParameterExpression
import XCTest

enum PathologicalFixtures {
    /// The ring `let a0 = a1; … let a15 = a0; a0`.
    static let ring: String = (0..<16).map { (i: Int) -> String in "let a\(i) = a\((i + 1) % 16);" }.joined() + "a0"
    /// The doubling chain `let a0 = audio.onset; let a1 = a0 + a0; … a15`.
    static let doubling: String = "let a0 = audio.onset;"
        + (1..<16).map { (i: Int) -> String in "let a\(i) = a\(i - 1) + a\(i - 1);" }.joined() + "a15"
    static let seventeenBindings: String = (0..<16).map { (i: Int) -> String in "let a\(i) = \(i);" }.joined() + "let a16 = 16;a16"
    static let maximalSines: String = Array(repeating: "sin(1)", count: 43).joined(separator: "+")

    /// Source and expected outcome: an exact refusal message, or nil (accepted).
    static let table: [(name: String, source: String, message: String?)] = [
        ("one megabyte", String(repeating: " ", count: 1_000_000) + "1",
         "1:513: the source is 1000001 bytes; at most 512 are allowed"),
        ("nesting under the token limit", String(repeating: "(", count: 127) + "1" + String(repeating: ")", count: 127),
         "1:17: nesting deeper than 16 levels"),
        ("nesting at the byte limit", String(repeating: "(", count: 255) + "1" + String(repeating: ")", count: 255),
         "1:257: more than 256 tokens"),
        ("unary flood", String(repeating: "-", count: 255) + "1", "1:17: nesting deeper than 16 levels"),
        ("nested calls", String(repeating: "abs(", count: 17) + "1" + String(repeating: ")", count: 17),
         "1:68: nesting deeper than 16 levels"),
        ("token flood", String(repeating: "1+", count: 255) + "1", "1:257: more than 256 tokens"),
        ("400-digit literal", String(repeating: "1", count: 400),
         "1:1: number '\(String(repeating: "1", count: 400))' is out of range"),
        ("control byte", "1 + \u{7}", "1:5: unexpected byte 0x07"),
        ("17 bindings", seventeenBindings, "1:189: more than 16 bindings"),
        ("maximal cost", maximalSines, "1:294: operation cost over 256"),
        ("binding ring", ring,
         "1:202: recursive binding: " + ((0..<16).map { (i: Int) -> String in "a\(i)" } + ["a0"]).joined(separator: " → ")),
        ("doubling chain", doubling, nil),
        ("band means at the byte limit", Array(repeating: "audio.bandMean", count: 34).joined(separator: "+"), nil),
    ]
}

final class ExpressionPathologicalTests: XCTestCase {
    func testFixtureTable() {
        var frameSet = ExpressionFrameSet()
        for fixture in PathologicalFixtures.table {
            let (result, work) = CompiledExpression.measure(source: fixture.source)
            XCTAssertTrue(work.isWithinBounds, fixture.name)
            switch (result, fixture.message) {
            case let (.failure(error), message?):
                XCTAssertEqual(error.description, message, fixture.name)
            case let (.success(compiled), nil):
                XCTAssertLessThanOrEqual(compiled.operationCost, 256, fixture.name)
                XCTAssertNoThrow(try frameSet.admit(compiled), fixture.name)
            case let (.failure(error), nil):
                XCTFail("\(fixture.name): refused with \(error)")
            case (.success, _?):
                XCTFail("\(fixture.name): accepted")
            }
        }
        // Only the two accepted fixtures reached the frame set; a refused source has no compiled form.
        XCTAssertEqual(frameSet.count, 2)
    }

    func testOversizedSourceIsRefusedWithoutReadingIt() {
        let (_, work) = CompiledExpression.measure(source: String(repeating: " ", count: 1_000_000) + "1")
        XCTAssertEqual(work.lexerSteps, 513, "the length check plus the 512 bytes that place the error")
        XCTAssertEqual(work.parserSteps + work.compilerSteps, 0)
    }

    func testDoublingChainIsLinear() throws {
        let compiled = try CompiledExpression(source: PathologicalFixtures.doubling)
        XCTAssertEqual(compiled.operationCost, 63, "1 read + 16 stores + 30 loads + 15 adds + 1 final load")
        XCTAssertEqual(ExpressionTestInputs().evaluate(compiled), 0.75 * 32768)
    }

    func testBandMeanCost() throws {
        let source = Array(repeating: "audio.bandMean", count: 34).joined(separator: "+")
        XCTAssertEqual(source.utf8.count, 509)
        XCTAssertEqual(try CompiledExpression(source: source).operationCost, 34 * 4 + 33)
    }

    /// Contract B5: the static cost is the sum of the instructions' costs, each instruction runs once
    /// (no opcode jumps), so evaluation work equals the cost.
    func testCostEqualsWork() throws {
        let sources = ExpressionFixtures.valid + [PathologicalFixtures.doubling, PathologicalFixtures.maximalSines]
        for source in sources {
            guard let compiled = try? CompiledExpression(source: source, limits: ExpressionLimits(maximumOperationCost: 257)) else {
                XCTFail(source)
                continue
            }
            let sum = compiled.instructions.reduce(0) { (total: Int, instruction: ExpressionInstruction) -> Int in
                total + ExpressionLimits.cost(of: instruction.opcode)
            }
            XCTAssertEqual(sum, compiled.operationCost, source)
        }
        // The closed opcode set: values, arithmetic, functions, slots; no jump, call or loop.
        XCTAssertEqual(ExpressionOpcode.allCases.map { (op: ExpressionOpcode) -> UInt8 in op.rawValue },
                       [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34])
    }
}
