// MOD-001-T03: parameter ID syntax (MOD-001-R1), enum case ID syntax (MOD-001-R2) and the tagged
// JSON form of values (research MOD-001-D7).
import Foundation
import ParameterGraph
import XCTest

final class ParameterIDTests: XCTestCase {
    func testWellFormedIDs() {
        for raw in ["visual.circularSpectrum.gap", "effect.bloom.radius", "a.b1", "x.y.z.w"] {
            let id = ParameterID(raw)
            XCTAssertTrue(id.isWellFormed, raw)
            XCTAssertNil(id.syntaxProblem, raw)
        }
        let id = ParameterID("visual.circularSpectrum.gap")
        XCTAssertEqual(id.domain, "visual")
        XCTAssertEqual(id.segments, ["visual", "circularSpectrum", "gap"])
        XCTAssertEqual(id.description, "visual.circularSpectrum.gap")
    }

    func testIllFormedIDs() {
        let bad = ["", "visual", "a..b", ".a.b", "a.b.", "Visual.gap", "visual.Gap", "1a.b", "a.1b",
                   "visual.gäp", "visual.bar-count", "visual.bar_count", "visual.bar count",
                   "a." + String(repeating: "b", count: 127)]
        for raw in bad {
            let id = ParameterID(raw)
            XCTAssertFalse(id.isWellFormed, "\(raw) should be ill-formed")
            XCTAssertNotNil(id.syntaxProblem, raw)
        }
        // Exactly 128 characters is allowed.
        XCTAssertTrue(ParameterID("a." + String(repeating: "b", count: 126)).isWellFormed)
    }

    func testEnumCaseIDSyntax() {
        for raw in ["16", "vertical", "b16", "lowPass2"] {
            XCTAssertTrue(ParameterEnumCase.isWellFormedID(raw), raw)
        }
        for raw in ["", "Vertical", "low-pass", "a b", "é"] {
            XCTAssertFalse(ParameterEnumCase.isWellFormedID(raw), raw)
        }
    }

    func testIDCodableAsStringAndDictionaryKey() throws {
        let id = ParameterID("effect.bloom.radius")
        let encoded = try JSONEncoder().encode(id)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"effect.bloom.radius\"")
        XCTAssertEqual(try JSONDecoder().decode(ParameterID.self, from: encoded), id)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let dict: [ParameterID: Int] = [ParameterID("b.a"): 2, ParameterID("a.b"): 1]
        let json = String(decoding: try encoder.encode(dict), as: UTF8.self)
        XCTAssertEqual(json, "{\"a.b\":1,\"b.a\":2}")
        XCTAssertEqual(try JSONDecoder().decode([ParameterID: Int].self, from: Data(json.utf8)), dict)
    }

    func testValueJSONRoundTripKeepsKinds() throws {
        let values: [ParameterValue] = [
            .continuous(1.0), .integer(1), .boolean(true), .enumeration("vertical"),
            .color(ParameterColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for value in values {
            let data = try encoder.encode(value)
            XCTAssertEqual(try JSONDecoder().decode(ParameterValue.self, from: data), value)
        }
        XCTAssertEqual(String(decoding: try encoder.encode(ParameterValue.integer(1)), as: UTF8.self),
                       "{\"kind\":\"integer\",\"value\":1}")
        XCTAssertEqual(String(decoding: try encoder.encode(ParameterValue.continuous(1)), as: UTF8.self),
                       "{\"kind\":\"continuous\",\"value\":1}")
        XCTAssertEqual(String(decoding: try encoder.encode(ParameterValue.color(ParameterColor(red: 0, green: 0.5, blue: 1, alpha: 1))),
                              as: UTF8.self),
                       "{\"kind\":\"color\",\"value\":[0,0.5,1,1]}")
        // Integer 1 and continuous 1 stay distinct after decoding.
        let decoded = try JSONDecoder().decode(ParameterValue.self, from: Data("{\"kind\":\"continuous\",\"value\":1}".utf8))
        XCTAssertEqual(decoded, .continuous(1))
        XCTAssertNotEqual(decoded, .integer(1))
        XCTAssertThrowsError(try JSONDecoder().decode(ParameterValue.self, from: Data("{\"kind\":\"spline\",\"value\":1}".utf8)))
    }
}
