// ExpressionRejectionTests.swift — SHD-009-T12: every rejected source maps to its exact message and
// position (SHD-009-R2 to R4, R6; S2; contract E1-E5, E7).
import ParameterExpression
import XCTest

final class ExpressionRejectionTests: XCTestCase {
    static let table: [(source: String, message: String)] = [
        // Unknown names.
        ("audio.bass", "1:1: unknown identifier 'audio.bass'"),
        ("1 + audio.band.128", "1:5: unknown identifier 'audio.band.128'"),
        ("audio.band.07", "1:1: unknown identifier 'audio.band.07'"),
        ("Time", "1:1: unknown identifier 'Time'"),
        ("audio.band.-1", "1:11: unexpected character '.'"),
        ("1 +\n  audio.bass", "2:3: unknown identifier 'audio.bass'"),
        // Functions.
        ("tan(1)", "1:1: unknown function 'tan'"),
        ("time(1)", "1:1: 'time' is not a function"),
        ("let k = 1; k(2)", "1:12: 'k' is not a function"),
        ("sin + 1", "1:1: function 'sin' needs arguments, as in sin(x)"),
        ("clamp(1, 2)", "1:1: 'clamp' takes 3 arguments, found 2"),
        ("abs(1, 2)", "1:1: 'abs' takes 1 argument, found 2"),
        ("min()", "1:1: 'min' takes 2 arguments, found 0"),
        // Recursion.
        ("let x = x + 1; x", "1:9: recursive binding: x → x"),
        ("let a = b; let b = a; a", "1:20: recursive binding: a → b → a"),
        ("let c = b; let a = c; let b = a; a", "1:20: recursive binding: c → b → a → c"),
        ("let q = d; let a = d; let d = a; q", "1:31: recursive binding: a → d → a"),
        // Binding names.
        ("let a.b = 1; 1", "1:5: binding name 'a.b' must not contain '.'"),
        ("let time = 1; time", "1:5: 'time' is a reserved name"),
        ("let sin = 1; 1", "1:5: 'sin' is a reserved name"),
        ("let audio = 1; 1", "1:5: 'audio' is a reserved name"),
        ("let x = 1; let x = 2; x", "1:16: 'x' is already defined"),
        ("let let = 1; 1", "1:5: expected a binding name, found 'let'"),
        ("let x = 1 x", "1:11: expected ';', found 'x'"),
        ("let x 1; x", "1:7: expected '=', found '1'"),
        // Numbers and characters.
        ("1.", "1:1: malformed number '1.'"),
        ("1e", "1:1: malformed number '1e'"),
        ("1.2.3", "1:1: malformed number '1.2.3'"),
        ("0x1F", "1:1: malformed number '0x1F'"),
        ("2 * 3e+", "1:5: malformed number '3e+'"),
        ("12abc", "1:1: malformed number '12abc'"),
        ("1e400", "1:1: number '1e400' is out of range"),
        (".5", "1:1: unexpected character '.'"),
        ("1 $ 2", "1:3: unexpected character '$'"),
        ("1 + é", "1:5: unexpected byte 0xC3"),
        ("\u{7}", "1:1: unexpected byte 0x07"),
        // Syntax and trailing input.
        ("", "1:1: expected an expression, found end of input"),
        ("   ", "1:4: expected an expression, found end of input"),
        ("(1 + 2", "1:7: expected ')', found end of input"),
        ("1 + 2)", "1:6: expected end of input, found ')'"),
        ("1 2", "1:3: expected end of input, found '2'"),
        ("1;", "1:2: expected end of input, found ';'"),
        ("max(1 2)", "1:7: expected ',' or ')', found '2'"),
        ("=", "1:1: expected an expression, found '='"),
        ("1 + let", "1:5: expected an expression, found 'let'"),
        ("1 +", "1:4: expected an expression, found end of input"),
        // Phase order: a lexical error wins over an earlier syntax error; names win over recursion.
        (") $", "1:3: unexpected character '$'"),
        ("let x = x; foo", "1:12: unknown identifier 'foo'"),
    ]

    func testRejectionTable() {
        for (source, message) in Self.table {
            XCTAssertEqual(Self.error(for: source)?.description, message, "source: \(source.debugDescription)")
        }
    }

    /// MOD-007-T05 (research MOD-007-D4): oscillators are binding sources, not formula names.
    func testLFOSourcesAreNotFormulaNames() {
        XCTAssertEqual(Self.error(for: "audio.lfo.0 * 2")?.reason, .unknownIdentifier("audio.lfo.0"))
        XCTAssertNil(Self.error(for: "audio.kick * 2"))
    }

    /// MOD-015-T07 (research MOD-015-D5): band envelopes are binding sources, not formula names.
    func testBandEnvelopeSourcesAreNotFormulaNames() {
        XCTAssertEqual(Self.error(for: "audio.bandEnvelope.slow.0 * 2")?.reason, .unknownIdentifier("audio.bandEnvelope.slow.0"))
        XCTAssertNil(Self.error(for: "audio.band.0 * 2"))
    }

    func testErrorCarriesPositionAndReason() {
        let error = Self.error(for: "1 +\n  audio.bass")
        XCTAssertEqual(error?.position, SourcePosition(line: 2, column: 3))
        XCTAssertEqual(error?.reason, .unknownIdentifier("audio.bass"))
    }

    static func error(for source: String, limits: ExpressionLimits = .standard) -> ExpressionError? {
        do {
            _ = try CompiledExpression(source: source, limits: limits)
            return nil
        } catch {
            return error
        }
    }
}
