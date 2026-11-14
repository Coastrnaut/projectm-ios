// ExpressionCurveTests.swift — MOD-004-T06: an SHD-009 expression mapping shapes the formula's 0…1
// position with its curve before MOD-003's interpolation (MOD-004-R8; contract K7).
import ParameterExpression
import ParameterGraph
import XCTest

final class ExpressionCurveTests: XCTestCase {
    func testExpressionMappingAppliesItsCurve() throws {
        let expression = try CompiledExpression(source: "0.5")
        let linear = ExpressionMapping(expression: expression, outputStart: 0, outputEnd: 10)
        XCTAssertEqual(linear.curve, .linear, "linear by default")
        XCTAssertEqual(linear.map(.silent), 5)
        let curved = ExpressionMapping(expression: expression, outputStart: 0, outputEnd: 10, curve: .easeIn(exponent: 2))
        XCTAssertEqual(curved.map(.silent), 2.5)
        XCTAssertEqual(curved.position(.silent), 0.5, "the position stays the formula's value")
        let high = ExpressionMapping(expression: try CompiledExpression(source: "7"), outputStart: 0, outputEnd: 10,
                                     curve: .logarithmic(strength: 9))
        XCTAssertEqual(high.map(.silent), 10, "a clamped position of 1 reaches the end exactly")
    }
}
