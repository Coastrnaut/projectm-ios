// ExpressionNumericSafetyTests.swift — SHD-009-T14: undefined arithmetic gives its documented
// finite result (SHD-009-R7; S3; contract E4, E6).
import ParameterExpression
import XCTest

final class ExpressionNumericSafetyTests: XCTestCase {
    private func value(_ source: String, _ inputs: ExpressionTestInputs = ExpressionTestInputs(),
                       file: StaticString = #filePath, line: UInt = #line) -> Double {
        do {
            return inputs.evaluate(try CompiledExpression(source: source))
        } catch {
            XCTFail("\(source): \(error)", file: file, line: line)
            return .nan
        }
    }

    func testDocumentedResults() {
        let largest = Double.greatestFiniteMagnitude
        let cases: [(String, Double)] = [
            ("1 / 0", 0), ("0 / 0", 0), ("-1 / 0", 0), ("1 / (time - 2)", 0),
            ("sqrt(-4)", 0), ("sqrt(0)", 0),
            ("pow(-8, 0.5)", 0), ("pow(-8, 1 / 3)", 0), ("pow(-2, 3)", -8),
            ("pow(10, 400)", largest), ("pow(0, -1)", largest),
            ("1e308 * 10", largest), ("-1e308 * 10", -largest), ("1e308 * 10 - 1e308 * 10", 0),
            ("1e308 + 1e308", largest), ("1 / 1e-308 / 1e-308", largest),
            ("smoothstep(1, 1, 0.5)", 0), ("smoothstep(1, 1, 1)", 1), ("smoothstep(1, 0, 0.25)", 0.84375),
            ("clamp(0.5, 1, 0)", 0), ("fract(-1e-20)", 0), ("floor(1e308 * 10)", largest),
            ("mix(0, 1e308, 2)", largest), ("mix(-1e308, 1e308, 2)", -1e308 + largest),
        ]
        for (source, expected) in cases {
            XCTAssertEqual(value(source).bitPattern, expected.bitPattern, "\(source) = \(value(source))")
        }
        for source in ["sin(1e308 * 10)", "cos(-1e308 * 10)", "fract(1e308)", "smoothstep(-1e308, 1e308, 0)"] {
            XCTAssertTrue(value(source).isFinite, source)
        }
    }

    func testNonFiniteInputsReadZero() {
        let bad = ExpressionTestInputs(bands: [.nan, .infinity, -.infinity], onset: .nan, beatConfidence: .infinity, time: .nan)
        XCTAssertEqual(value("audio.band.0 + audio.band.1 + audio.band.2 + audio.bandMean + audio.onset + audio.beatConfidence + time", bad), 0)
        let infiniteTime = ExpressionTestInputs(time: -.infinity)
        XCTAssertEqual(value("time", infiniteTime), 0)
        let missing = ExpressionTestInputs(bands: [], onset: nil, beatConfidence: nil)
        XCTAssertEqual(value("audio.band.127 + audio.bandMean + audio.onset + audio.beatConfidence", missing), 0)
    }
}
