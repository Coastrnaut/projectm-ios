// ExpressionLimitTests.swift — SHD-009-T13: each complexity limit is accepted at its bound and
// rejected one over it, with its message and position (SHD-009-R5, R13; S2; contract E1, E2, E6).
import ParameterExpression
import XCTest

final class ExpressionLimitTests: XCTestCase {
    private func accepts(_ source: String, limits: ExpressionLimits = .standard, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(ExpressionRejectionTests.error(for: source, limits: limits), file: file, line: line)
    }

    private func rejects(_ source: String, _ message: String, limits: ExpressionLimits = .standard,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ExpressionRejectionTests.error(for: source, limits: limits)?.description, message, file: file, line: line)
    }

    func testDefaults() {
        let limits = ExpressionLimits.standard
        XCTAssertEqual([limits.maximumSourceBytes, limits.maximumTokens, limits.maximumNodes, limits.maximumNesting,
                        limits.maximumBindings, limits.maximumOperationCost], [512, 256, 128, 16, 16, 256])
        XCTAssertEqual(ExpressionOpcode.allCases.filter { (op: ExpressionOpcode) -> Bool in ExpressionLimits.cost(of: op) == 4 },
                       [.sin, .cos, .smoothstep, .sqrt, .pow])
    }

    func testSourceLength() {
        accepts("1" + String(repeating: " ", count: 511))
        rejects("1" + String(repeating: " ", count: 512), "1:513: the source is 513 bytes; at most 512 are allowed")
        rejects("1\n" + String(repeating: " ", count: 600), "2:511: the source is 602 bytes; at most 512 are allowed")
    }

    func testTokenCount() {
        // Σ(tokens + 1) − 1: 42 × "((1))" and one "abs(1)" joined by "+" = 256 tokens.
        let atLimit = (Array(repeating: "((1))", count: 42) + ["abs(1)"]).joined(separator: "+")
        accepts(atLimit)
        let over = atLimit + "+1"
        rejects(over, "1:\(over.utf8.count - 1): more than 256 tokens")   // token 257 is the added "+"
        rejects("1+2+3+4", "1:6: more than 5 tokens", limits: ExpressionLimits(maximumTokens: 5))
    }

    func testNodeCount() {
        // A flat 64-term sum with a unary minus: 128 nodes, nesting 1.
        accepts("-1" + String(repeating: "+1", count: 63))
        let over = "1" + String(repeating: "+1", count: 64)   // 129 nodes; the last "1" is node 129
        rejects(over, "1:129: more than 128 expression nodes")
        // Parentheses are free.
        accepts("((1))+((1))")
    }

    func testNesting() {
        accepts(String(repeating: "(", count: 16) + "1" + String(repeating: ")", count: 16))
        rejects(String(repeating: "(", count: 17) + "1" + String(repeating: ")", count: 17), "1:17: nesting deeper than 16 levels")
        accepts(String(repeating: "-", count: 16) + "1")
        rejects(String(repeating: "-", count: 17) + "1", "1:17: nesting deeper than 16 levels")
        accepts(String(repeating: "abs(", count: 16) + "1" + String(repeating: ")", count: 16))
        rejects(String(repeating: "abs(", count: 17) + "1" + String(repeating: ")", count: 17), "1:68: nesting deeper than 16 levels")
        // A flat 60-term sum stays at nesting level 0.
        accepts("1" + String(repeating: "+1", count: 59), limits: ExpressionLimits(maximumNesting: 0))
        rejects("(1)", "1:1: nesting deeper than 0 levels", limits: ExpressionLimits(maximumNesting: 0))
    }

    func testBindingCount() {
        let sixteen = (0..<16).map { (i: Int) -> String in "let a\(i) = \(i);" }.joined()
        accepts(sixteen + "a15")
        let over = sixteen + "let a16 = 16;a16"
        rejects(over, "1:\(sixteen.utf8.count + 1): more than 16 bindings")
    }

    func testOperationCost() throws {
        // 43 × "sin(1)" joined by "+": 43 × 5 + 42 = 257, 128 nodes.
        let source = Array(repeating: "sin(1)", count: 43).joined(separator: "+")
        rejects(source, "1:294: operation cost over 256")   // the last "+" takes the running total to 257
        let compiled = try CompiledExpression(source: source, limits: ExpressionLimits(maximumOperationCost: 257))
        XCTAssertEqual(compiled.operationCost, 257)
        XCTAssertEqual(try CompiledExpression(source: "let a = sin(1); a + a").operationCost, 9)
        XCTAssertEqual(try CompiledExpression(source: "+1").operationCost, 1, "unary plus emits nothing")
        rejects("sqrt(4)", "1:1: operation cost over 4", limits: ExpressionLimits(maximumOperationCost: 4))
    }
}
