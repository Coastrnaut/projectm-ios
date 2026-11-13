// SceneJSONTests.swift — the bounded parser and canonical writer (SCN-001-T07; research
// SCN-001-D1; contract C2, C4).
@testable import SceneFormat
import XCTest

final class SceneJSONTests: XCTestCase {
    private func parse(_ text: String, depth: Int = 32) throws -> SceneJSON {
        try SceneJSONParser.parse(Array(text.utf8), maximumDepth: depth)
    }

    private func canonical(_ text: String) throws -> String {
        String(decoding: try parse(text).canonicalBytes, as: UTF8.self)
    }

    func testCanonicalFormSortsKeysAndRemovesWhiteSpace() throws {
        XCTAssertEqual(try canonical(" { \"b\" : [1, 2.5, true, null], \"a\":\"x\", \"B\": {} } "),
                       "{\"B\":{},\"a\":\"x\",\"b\":[1,2.5,true,null]}")
        // Keys sort by UTF-8 bytes: "Z" (0x5A) < "a" (0x61) < "é" (0xC3 0xA9).
        XCTAssertEqual(try canonical("{\"é\":1,\"a\":2,\"Z\":3}"), "{\"Z\":3,\"a\":2,\"é\":1}")
    }

    func testNumbersKeepTheirWrittenText() throws {
        let text = "[0,-0,1.0,1E5,1e-7,0.1,9007199254740993,123456789012345678901234567890]"
        XCTAssertEqual(try canonical(text), text)
        XCTAssertEqual(SceneNumber(0.1).text, "0.1")
        XCTAssertEqual(SceneNumber(1.0).text, "1.0")
        XCTAssertEqual(SceneNumber(1e-7).text, "1e-07")
        XCTAssertEqual(SceneNumber(-0.0).text, "-0.0")
        XCTAssertEqual(SceneNumber(1e16).text, "1e+16")
        XCTAssertEqual(SceneNumber(Int64(-42)).text, "-42")
        // Every written double reads back to the same bits.
        for d in [0.1, 1.0 / 3.0, 5e-324, Double.greatestFiniteMagnitude, -2.5e-300, 1e16, 123456.789] {
            let n = try parse(SceneNumber(d).text).numberValue
            XCTAssertEqual(n?.doubleValue?.bitPattern, d.bitPattern)
        }
        XCTAssertNil(try parse("1e999").numberValue?.doubleValue)
        XCTAssertNil(try parse("1.5").numberValue?.int64Value)
    }

    func testStringsRoundTripWithMinimalEscaping() throws {
        let value = SceneJSON.string("quote \" back \\ slash / tab \t nl \n bell \u{07} é 漢 🎛")
        let bytes = value.canonicalBytes
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self),
                       "\"quote \\\" back \\\\ slash / tab \\t nl \\n bell \\u0007 é 漢 🎛\"")
        XCTAssertEqual(try SceneJSONParser.parse(bytes, maximumDepth: 32), value)
        XCTAssertEqual(try parse("\"\\u00e9\\ud83c\\udf9b\\/\""), .string("é🎛/"))
    }

    func testMalformedJSONIsRefusedWithItsOffset() {
        let cases: [(String, Int, String)] = [
            ("", 0, "unexpected end of data"),
            ("{", 1, "expected a key"),
            ("[1,]", 3, "unexpected character"),
            ("01", 1, "unexpected data after the document"),
            ("\"a", 2, "unterminated string"),
            ("\"\\x\"", 3, "invalid escape"),
            ("\"\\ud800\"", 7, "unpaired surrogate escape"),
            ("\"\u{01}\"", 1, "control character in a string"),
            ("tru", 0, "unexpected end of data"),
            ("1.", 2, "invalid number"),
            ("{\"a\" 1}", 5, "expected \":\""),
        ]
        for (text, offset, reason) in cases {
            XCTAssertThrowsError(try parse(text), text) {
                XCTAssertEqual($0 as? SceneDecodeError, .notJSON(offset: offset, reason: reason), text)
            }
        }
    }

    func testInvalidUTF8IsRefused() {
        for bytes: [UInt8] in [[0x22, 0xFF, 0x22], [0x22, 0xC0, 0xAF, 0x22], [0x22, 0xED, 0xA0, 0x80, 0x22], [0x22, 0xE2, 0x82]] {
            XCTAssertThrowsError(try SceneJSONParser.parse(bytes, maximumDepth: 32)) {
                guard case let .notJSON(_, reason)? = $0 as? SceneDecodeError else { return XCTFail("\($0)") }
                XCTAssertEqual(reason, "invalid UTF-8")
            }
        }
    }

    func testDepthIsLimitedWhileParsing() throws {
        let ok = String(repeating: "[", count: 32) + String(repeating: "]", count: 32)
        XCTAssertNoThrow(try parse(ok))
        let deep = String(repeating: "[", count: 33) + String(repeating: "]", count: 33)
        XCTAssertThrowsError(try parse(deep)) { XCTAssertEqual($0 as? SceneDecodeError, .nestingTooDeep(limit: 32)) }
        // A hostile depth far beyond the limit stops at the limit (no deep recursion).
        let hostile = String(repeating: "[", count: 100_000)
        XCTAssertThrowsError(try parse(hostile)) { XCTAssertEqual($0 as? SceneDecodeError, .nestingTooDeep(limit: 32)) }
    }

    func testDuplicateKeysAreRefusedWithTheirPath() {
        XCTAssertThrowsError(try parse("{\"layers\":[{\"kind\":1,\"kind\":2}]}")) {
            XCTAssertEqual($0 as? SceneDecodeError, .duplicateKey(path: "$.layers[0]", key: "kind"))
        }
        XCTAssertThrowsError(try parse("{\"parameters\":{\"a.b\":{\"x\":1,\"x\":1}}}")) {
            XCTAssertEqual($0 as? SceneDecodeError, .duplicateKey(path: "$.parameters[\"a.b\"]", key: "x"))
        }
    }

    /// SCN-002-T01: the public entry point keeps the reader's bounds and round-trips canonically.
    func testPublicParseIsBoundedAndCanonical() throws {
        let text = "{\"a\":[1,2.5,true,null],\"b\":\"x\"}"
        XCTAssertEqual(try SceneJSON.parse(Array(text.utf8)).canonicalBytes, Array(text.utf8))
        XCTAssertThrowsError(try SceneJSON.parse([])) { (e: Error) in XCTAssertEqual(e as? SceneDecodeError, .empty) }
        XCTAssertThrowsError(try SceneJSON.parse(Array("{\"a\":1,\"a\":2}".utf8)))
        let deep = String(repeating: "[", count: 40) + String(repeating: "]", count: 40)
        XCTAssertThrowsError(try SceneJSON.parse(Array(deep.utf8))) { (e: Error) in
            XCTAssertEqual(e as? SceneDecodeError, .nestingTooDeep(limit: SceneLimits.maximumDepth))
        }
        let big = [UInt8](repeating: 0x20, count: SceneLimits.maximumBytes + 1)
        XCTAssertThrowsError(try SceneJSON.parse(big)) { (e: Error) in
            XCTAssertEqual(e as? SceneDecodeError, .tooLarge(bytes: SceneLimits.maximumBytes + 1, limit: SceneLimits.maximumBytes))
        }
    }
}
