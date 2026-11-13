// FILE-007-T03 (FILE-007-R1 to R4, S1): the hostile table and edge cases for BoundedJSON. Each case
// has its exact typed error and offset, and the work done (bytes examined) is bounded by the offset
// of the refusal: no rescans, no recursion. Contract C1.
import XCTest
import LocalPortability

final class BoundedJSONTests: XCTestCase {
    /// Any top-level value, so array cases can be written directly.
    private let open = JSONLimits(maxBytes: 4 << 20, maxDepth: 8, maxStringBytes: 65_536, maxNumberBytes: 32,
                                  maxElements: 65_536, rejectsDuplicateKeys: true, requiresObjectRoot: false)

    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    private func repeated(_ text: String, _ times: Int) -> [UInt8] {
        let unit = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(unit.count * times)
        for _ in 0..<times { out.append(contentsOf: unit) }
        return out
    }

    /// Refused with exactly `expected`, having examined at most `offset + 1` bytes (or `maxExamined`).
    private func assertRefused(_ input: [UInt8], _ expected: JSONShapeError, limits: JSONLimits? = nil, maxExamined: Int? = nil,
                               _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let outcome = BoundedJSON.check(input, limits: limits ?? open)
        switch outcome.result {
        case .success:
            XCTFail("\(name): accepted", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, name, file: file, line: line)
            let bound = maxExamined ?? (expected.offset + 1)
            XCTAssertLessThanOrEqual(outcome.bytesExamined, bound, "\(name): work not bounded by the refusal", file: file, line: line)
        }
        // Data and [UInt8] agree.
        XCTAssertEqual(BoundedJSON.check(Data(input), limits: limits ?? open), outcome, name, file: file, line: line)
    }

    private func assertAccepted(_ input: [UInt8], limits: JSONLimits? = nil, _ name: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let outcome = BoundedJSON.check(input, limits: limits ?? open)
        if case .failure(let error) = outcome.result { XCTFail("\(name): refused \(error)", file: file, line: line) }
        XCTAssertEqual(outcome.bytesExamined, input.count, name, file: file, line: line)
    }

    // MARK: Hostile table (the roadmap acceptance: malformed nesting and oversize payload)

    func testHostileTable() {
        let tenMegabyteString = [UInt8(ascii: "\"")] + [UInt8](repeating: 0x78, count: 10_000_000) + [UInt8(ascii: "\"")]
        // 1,000,000 elements in about 2 MB, under the 4 MiB byte cap, so the element limit decides.
        let millionElements = bytes("[") + repeated("0,", 999_999) + bytes("0]")
        XCTAssertEqual(millionElements.count, 2_000_001)

        let cases: [(name: String, input: [UInt8], expected: JSONShapeError, maxExamined: Int?)] = [
            ("100,000-deep arrays", repeated("[", 100_000), .nestingTooDeep(offset: 8, limit: 8), nil),
            ("100,000-deep objects", repeated("{\"a\":", 100_000), .nestingTooDeep(offset: 40, limit: 8), nil),
            ("10 MB string", tenMegabyteString, .tooLarge(bytes: 10_000_002, limit: 4 << 20), 0),
            ("1,000,000-element array", millionElements, .tooManyElements(offset: 131_073, limit: 65_536), nil),
            ("overlong UTF-8 (C0 AF)", [0x22, 0xC0, 0xAF, 0x22], .invalidUTF8(offset: 1), nil),
            ("encoded surrogate (ED A0 80)", [0x22, 0xED, 0xA0, 0x80, 0x22], .invalidUTF8(offset: 2), nil),
            ("above U+10FFFF (F4 90)", [0x22, 0xF4, 0x90, 0x80, 0x80, 0x22], .invalidUTF8(offset: 2), nil),
            ("lone continuation byte", [0x22, 0x80, 0x22], .invalidUTF8(offset: 1), nil),
            ("byte FF", [0x22, 0xFF, 0x22], .invalidUTF8(offset: 1), nil),
            ("truncated sequence at the end", [0x22, 0xE2, 0x82], .unterminatedString(offset: 3), nil),
            ("overlong number", repeated("1", 1_000), .numberTooLong(offset: 32, limit: 32), nil),
            ("duplicate key", bytes("{\"a\":1,\"a\":2}"), .duplicateKey(offset: 9), nil),
            ("duplicate key through an escape", bytes("{\"a\":1,\"\\u0061\":2}"), .duplicateKey(offset: 14), nil),
            ("byte order mark", [0xEF, 0xBB, 0xBF] + bytes("{}"), .byteOrderMark, 3),
            ("trailing garbage", bytes("{} x"), .trailingData(offset: 3), nil),
            ("two documents", bytes("{}{}"), .trailingData(offset: 2), nil),
            ("unterminated string", bytes("{\"a\":\"abc"), .unterminatedString(offset: 9), nil),
            ("unclosed array", bytes("[1,2"), .unexpectedEnd(offset: 4), nil),
        ]
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        for c in cases { assertRefused(c.input, c.expected, maxExamined: c.maxExamined, c.name) }
    }

    // MARK: Edge cases

    func testGrammarEdgeCases() {
        let cases: [(String, String, JSONShapeError)] = [
            ("empty", "", .empty),
            ("white space only", "   ", .unexpectedEnd(offset: 3)),
            ("leading zero", "[01]", .invalidNumber(offset: 2)),
            ("lone minus", "[-]", .invalidNumber(offset: 2)),
            ("minus leading zero", "[-01]", .invalidNumber(offset: 3)),
            ("dot without digits", "[1.]", .invalidNumber(offset: 3)),
            ("exponent without digits", "[1e]", .invalidNumber(offset: 3)),
            ("exponent sign without digits", "[1e+]", .invalidNumber(offset: 4)),
            ("two dots", "[1.2.3]", .invalidNumber(offset: 4)),
            ("plus sign", "[+1]", .unexpectedCharacter(offset: 1)),
            ("number then letter", "[1x]", .unexpectedCharacter(offset: 2)),
            ("control character in a string", "[\"a\nb\"]", .controlCharacter(offset: 3)),
            ("unknown escape", "[\"\\x\"]", .invalidEscape(offset: 3)),
            ("bad hex digit", "[\"\\u12G4\"]", .invalidEscape(offset: 6)),
            ("lone low surrogate", "[\"\\uDC00\"]", .invalidEscape(offset: 7)),
            ("lone high surrogate", "[\"\\uD800\"]", .invalidEscape(offset: 8)),
            ("high surrogate then non-low", "[\"\\uD800\\u0041\"]", .invalidEscape(offset: 13)),
            ("trailing comma", "[1,]", .unexpectedCharacter(offset: 3)),
            ("trailing comma in object", "{\"a\":1,}", .unexpectedCharacter(offset: 7)),
            ("missing colon", "{\"a\" 1}", .unexpectedCharacter(offset: 5)),
            ("unquoted key", "{a:1}", .unexpectedCharacter(offset: 1)),
            ("misspelled literal", "[tru]", .unexpectedCharacter(offset: 4)),
            ("truncated literal", "[nul", .unexpectedEnd(offset: 4)),
            ("mismatched bracket", "[1}", .unexpectedCharacter(offset: 2)),
            ("non-ASCII outside strings", "[\u{00E9}]", .unexpectedCharacter(offset: 1)),
            ("single quotes", "['a']", .unexpectedCharacter(offset: 1)),
        ]
        for (name, text, expected) in cases { assertRefused(bytes(text), expected, name) }
    }

    func testAcceptedShapes() {
        let cases: [(String, String)] = [
            ("brackets inside strings are text", "[\"[[[[[[[[[[[[[[[[{{{{{{{{\"]"),
            ("escaped quote does not end a string", "[\"a\\\"]]]]]]]]]]]]\"]"),
            ("valid surrogate pair", "[\"\\uD83D\\uDE00\"]"),
            ("every escape", "[\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u00e9\"]"),
            ("multi-byte UTF-8", "{\"k\":\"\u{00E9}\u{20AC}\u{1F600}\"}"),
            ("same key in different objects", "{\"a\":{\"a\":1},\"b\":{\"a\":2}}"),
            ("numbers", "[0,-0,1.5,-2.25e10,3E-2,4e+1,1234567890]"),
            ("literals and white space", " \t\r\n[true , false,null ] \n"),
            ("empty containers", "{\"a\":[],\"b\":{}}"),
            ("scalar top level when allowed", "42"),
        ]
        for (name, text) in cases { assertAccepted(bytes(text), name) }
    }

    func testDuplicateKeysAllowedWhenNotRefused() {
        var limits = open
        limits.rejectsDuplicateKeys = false
        assertAccepted(bytes("{\"a\":1,\"a\":2}"), limits: limits, "duplicates allowed by the limits")
    }

    func testObjectRootIsRequiredWhenAsked() {
        var limits = open
        limits.requiresObjectRoot = true
        assertRefused(bytes("[1]"), .notAnObject(offset: 0), limits: limits, "array root")
        assertRefused(bytes("  5"), .notAnObject(offset: 2), limits: limits, "number root after white space")
        assertRefused(bytes("\"{}\""), .notAnObject(offset: 0), limits: limits, "string root")
        assertAccepted(bytes(" {} "), limits: limits, "object root")
    }

    // MARK: Exact limits: at the limit accepted, one over refused

    func testLimitsAreInclusive() {
        let small = JSONLimits(maxBytes: 64, maxDepth: 3, maxStringBytes: 4, maxNumberBytes: 3, maxElements: 2,
                               rejectsDuplicateKeys: true, requiresObjectRoot: false)
        assertAccepted(bytes("[[[]]]"), limits: small, "depth 3")
        assertRefused(bytes("[[[[]]]]"), .nestingTooDeep(offset: 3, limit: 3), limits: small, "depth 4")
        assertAccepted(bytes("[\"abcd\"]"), limits: small, "string of 4 bytes")
        assertRefused(bytes("[\"abcde\"]"), .stringTooLong(offset: 6, limit: 4), limits: small, "string of 5 bytes")
        assertRefused(bytes("[\"\\n\\n\\n\"]"), .stringTooLong(offset: 6, limit: 4), limits: small, "escapes counted as written")
        assertAccepted(bytes("[123]"), limits: small, "number of 3")
        assertRefused(bytes("[1234]"), .numberTooLong(offset: 4, limit: 3), limits: small, "number of 4")
        assertAccepted(bytes("[1,2]"), limits: small, "2 elements")
        assertRefused(bytes("[1,2,3]"), .tooManyElements(offset: 5, limit: 2), limits: small, "3 elements")
        assertAccepted(bytes("{\"a\":1,\"b\":2}"), limits: small, "2 members")
        assertRefused(bytes("{\"a\":1,\"b\":2,\"c\":3}"), .tooManyElements(offset: 13, limit: 2), limits: small, "3 members")
        let exact = [UInt8(ascii: "\"")] + [UInt8](repeating: 0x61, count: 2) + [UInt8(ascii: "\"")]
        var tiny = small
        tiny.maxBytes = exact.count
        assertAccepted(exact, limits: tiny, "exactly max bytes")
        assertRefused(exact + [0x20], .tooLarge(bytes: exact.count + 1, limit: exact.count), limits: tiny, maxExamined: 0, "one byte over")
    }

    func testSummaryAndErrorFamilies() throws {
        let summary = try BoundedJSON.validate(Data("{\"a\":[1,{\"b\":null}]}".utf8), limits: open)
        XCTAssertEqual(summary.deepest, 3)
        XCTAssertEqual(summary.values, 5)
        XCTAssertEqual(summary.bytesExamined, 20)
        XCTAssertEqual(JSONShapeError.nestingTooDeep(offset: 1, limit: 2).family, .limit)
        XCTAssertEqual(JSONShapeError.tooLarge(bytes: 2, limit: 1).family, .limit)
        XCTAssertEqual(JSONShapeError.duplicateKey(offset: 1).family, .duplicateKey)
        XCTAssertEqual(JSONShapeError.invalidUTF8(offset: 1).family, .grammar)
        XCTAssertEqual(JSONShapeError.byteOrderMark.family, .grammar)
    }

    func testDataSliceOffsetsAreRelativeToTheSlice() {
        let whole = Data("xx{\"a\":1,\"a\":2}".utf8)
        let slice = whole[2...]
        XCTAssertEqual(BoundedJSON.check(slice, limits: open).result, .failure(.duplicateKey(offset: 9)))
    }

    // MARK: Schema

    func testDocumentSchemaVerdictsAndCap() {
        let schema = DocumentSchema(name: "org.example.doc", oldestReadableVersion: 1, currentVersion: 3, limits: open)
        XCTAssertEqual(schema.verdict(for: 3), .current)
        XCTAssertEqual(schema.verdict(for: 2), .older)
        XCTAssertEqual(schema.verdict(for: 1), .older)
        XCTAssertEqual(schema.verdict(for: 0), .unsupported)
        XCTAssertEqual(schema.verdict(for: 4), .newer)
        XCTAssertEqual(schema.capped(atBytes: 100).limits.maxBytes, 100)
        XCTAssertEqual(schema.capped(atBytes: 8 << 20).limits.maxBytes, 4 << 20, "a cap never raises the limit")
        XCTAssertThrowsError(try schema.capped(atBytes: 3).validate(Data("[1,2]".utf8))) { error in
            XCTAssertEqual(error as? JSONShapeError, .tooLarge(bytes: 5, limit: 3))
        }
    }
}
