// SHD-003-T06 (US1; SHD-003-R1 to R3, S2): the reader accepts a valid document and refuses each class of
// mistake with its own error, whose message names the parameter and the key. CPU only; runs on Linux.
import ParameterGraph
import ShaderParameterMetadata
import XCTest

final class ShaderMetadataValidatorTests: XCTestCase {
    /// One parameter of every kind (slots 0-4).
    static let valid = """
    {"schema": 1, "variant": "sample", "name": "Sample", "summary": "One parameter of each kind.",
     "parameters": [
      {"id": "speed", "label": "Speed", "kind": "float", "slot": 0, "unit": "perSecond", "min": 0, "max": 1, "step": 0.01, "default": 0.25},
      {"id": "count", "label": "Count", "kind": "int", "slot": 1, "unit": "count", "min": 1, "max": 9, "step": 2, "default": 5},
      {"id": "mirror", "label": "Mirror", "kind": "bool", "slot": 2, "default": true},
      {"id": "shape", "label": "Shape", "kind": "enum", "slot": 3,
       "cases": [{"id": "linear", "label": "Linear"}, {"id": "radial", "label": "Radial"}], "default": "radial"},
      {"id": "tint", "label": "Tint", "kind": "color", "slot": 4, "default": [0.1, 0.2, 0.3, 1]}
     ]}
    """

    private func validate(_ json: String, required: [String] = []) throws(ShaderMetadataError) -> ValidatedShaderMetadata {
        try ShaderMetadataReader.validate(json: json, document: "test.sample", requiredParameters: required)
    }

    /// `valid` with `old` replaced by `new` (exactly once).
    private func variant(_ old: String, _ new: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertEqual(Self.valid.components(separatedBy: old).count, 2, "fixture edit \(old)", file: file, line: line)
        return Self.valid.replacingOccurrences(of: old, with: new)
    }

    private func assertRejected(_ json: String, _ expected: ShaderMetadataError, mentions: [String] = [],
                                file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try validate(json)
            XCTFail("accepted; expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
            for text in mentions { XCTAssertTrue(error.description.contains(text), "\(error.description) names \(text)", file: file, line: line) }
        }
    }

    func testValidDocumentReadsEveryKind() throws {
        let m = try validate(Self.valid, required: ["speed"])
        XCTAssertEqual(m.variant, "sample")
        XCTAssertEqual(m.name, "Sample")
        XCTAssertEqual(m.parameters.map(\.id), ["speed", "count", "mirror", "shape", "tint"])
        XCTAssertEqual(m.parameters.map(\.slot), [0, 1, 2, 3, 4])
        XCTAssertEqual(m.parameters[0].kind, .float(minimum: 0, maximum: 1, step: 0.01, defaultValue: 0.25))
        XCTAssertEqual(m.parameters[0].unit, .perSecond)
        XCTAssertEqual(m.parameters[1].kind, .int(minimum: 1, maximum: 9, step: 2, defaultValue: 5))
        XCTAssertEqual(m.parameters[2].kind, .bool(defaultValue: true))
        XCTAssertEqual(m.parameters[3].kind, .enumeration(cases: [ParameterEnumCase(id: "linear", displayName: "Linear"),
                                                                   ParameterEnumCase(id: "radial", displayName: "Radial")],
                                                           defaultValue: "radial"))
        XCTAssertEqual(m.parameters[3].unit, ParameterUnit.none)
        XCTAssertEqual(m.parameters[4].kind, .color(defaultValue: ParameterColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)))
    }

    func testDescriptorsFollowTheKindRules() throws {
        let m = try validate(Self.valid)
        let group = ParameterGroup(id: "test.sample", displayName: "Sample")
        let d = m.descriptors(idPrefix: "test.sample", group: group)
        XCTAssertEqual(d.map(\.id.rawValue), ["test.sample.speed", "test.sample.count", "test.sample.mirror", "test.sample.shape", "test.sample.tint"])
        XCTAssertEqual(d.map(\.modulation), [.continuousDefault, .discreteManual, .discreteManual, .discreteManual, .discreteManual])
        XCTAssertEqual(d[0].kind, .continuous(minimum: 0, maximum: 1, defaultValue: 0.25, step: 0.01))
        XCTAssertEqual(d[1].kind, .integer(minimum: 1, maximum: 9, defaultValue: 5, step: 2))
        XCTAssertEqual(ParameterRegistry.validate(d, retiredIDs: []), [])
    }

    // MARK: - Structure (R2)

    func testStructuralMistakes() {
        let d = "test.sample"
        assertRejected("{\"schema\": 1,", .malformedJSON(document: d))
        assertRejected("[1, 2]", .notAnObject(document: d, path: "document"))
        assertRejected(variant("\"summary\"", "\"author\": \"x\", \"summary\""), .unknownKey(document: d, path: "document", key: "author"))
        assertRejected(variant("\"label\": \"Count\",", "\"label\": \"Count\", \"colour\": 1,"),
                       .unknownKey(document: d, path: "parameters[1]", key: "colour"), mentions: ["parameters[1]", "colour"])
        assertRejected(variant("{\"id\": \"linear\", \"label\": \"Linear\"}", "{\"id\": \"linear\", \"label\": \"Linear\", \"x\": 1}"),
                       .unknownKey(document: d, path: "parameters[3].cases[0]", key: "x"))
        assertRejected(variant("\"label\": \"Speed\", ", ""), .missingKey(document: d, path: "parameters[0]", key: "label"),
                       mentions: ["parameters[0]", "label"])
        assertRejected(variant("\"default\": true", "\"default\": true, \"min\": 0"),
                       .keyNotAllowed(document: d, path: "parameters[2]", key: "min", kind: "bool"), mentions: ["min", "bool"])
        assertRejected(variant("\"default\": true", "\"default\": 1"),
                       .wrongType(document: d, path: "parameters[2]", key: "default", expected: "a boolean"))
        assertRejected(variant("\"schema\": 1", "\"schema\": 2"), .unsupportedSchema(document: d, version: 2))
        assertRejected(variant("\"kind\": \"int\"", "\"kind\": \"integer\""), .unknownKind(document: d, path: "parameters[1]", kind: "integer"))
        assertRejected(variant("\"unit\": \"count\"", "\"unit\": \"percent\""), .unknownUnit(document: d, path: "parameters[1]", unit: "percent"))
    }

    // MARK: - Values (R3)

    func testValueMistakes() {
        let d = "test.sample"
        assertRejected(variant("\"id\": \"speed\"", "\"id\": \"Speed!\""),
                       .invalidID(document: d, path: "parameters[0]", key: "id", value: "Speed!"))
        assertRejected(variant("\"label\": \"Mirror\"", "\"label\": \"  \""), .invalidLabel(document: d, path: "parameters[2]", key: "label"))
        assertRejected(variant("\"label\": \"Mirror\"", "\"label\": \"\(String(repeating: "m", count: 65))\""),
                       .invalidLabel(document: d, path: "parameters[2]", key: "label"))
        assertRejected(variant("\"min\": 0, \"max\": 1,", "\"min\": 1, \"max\": 0,"), .invertedRange(document: d, path: "parameters[0]"))
        assertRejected(variant("\"step\": 0.01", "\"step\": 0"), .invalidStep(document: d, path: "parameters[0]"))
        assertRejected(variant("\"step\": 0.01", "\"step\": 2"), .invalidStep(document: d, path: "parameters[0]"))
        assertRejected(variant("\"default\": 0.25", "\"default\": 1.5"), .defaultOutOfRange(document: d, path: "parameters[0]"),
                       mentions: ["parameters[0]", "default"])
        assertRejected(variant("\"default\": 5}", "\"default\": 4}"), .defaultOffStep(document: d, path: "parameters[1]"))
        assertRejected(variant("\"min\": 1, \"max\": 9", "\"min\": 1.5, \"max\": 9"), .notWhole(document: d, path: "parameters[1]", key: "min"))
        assertRejected(variant("[0.1, 0.2, 0.3, 1]", "[0.1, 0.2, 1.3, 1]"), .invalidColor(document: d, path: "parameters[4]"))
        assertRejected(variant("[0.1, 0.2, 0.3, 1]", "[0.1, 0.2, 0.3]"), .invalidColor(document: d, path: "parameters[4]"))
    }

    func testEnumMistakes() {
        let d = "test.sample"
        assertRejected(variant(", {\"id\": \"radial\", \"label\": \"Radial\"}], \"default\": \"radial\"", "], \"default\": \"linear\""),
                       .caseCount(document: d, path: "parameters[3]", count: 1))
        assertRejected(variant("{\"id\": \"radial\", \"label\": \"Radial\"}", "{\"id\": \"linear\", \"label\": \"Radial\"}"),
                       .duplicateCaseID(document: d, path: "parameters[3]", caseID: "linear"))
        assertRejected(variant("\"default\": \"radial\"", "\"default\": \"Radial\""),
                       .defaultNotACase(document: d, path: "parameters[3]", value: "Radial"), mentions: ["Radial", "default"])
        assertRejected(variant("\"default\": \"radial\"", "\"default\": \"radial\", \"step\": 1"),
                       .keyNotAllowed(document: d, path: "parameters[3]", key: "step", kind: "enum"))
    }

    func testListMistakes() {
        let d = "test.sample"
        assertRejected(variant("\"id\": \"count\"", "\"id\": \"speed\""), .duplicateParameterID(document: d, parameterID: "speed"))
        assertRejected(variant("\"slot\": 2,", "\"slot\": 7,"), .slotMismatch(document: d, parameterID: "mirror", slot: 7, position: 2),
                       mentions: ["mirror", "slot"])
        let none = "{\"schema\": 1, \"variant\": \"v\", \"name\": \"V\", \"summary\": \"S\", \"parameters\": []}"
        assertRejected(none, .parameterCount(document: d, count: 0))
        let item = "{\"id\": \"p%d\", \"label\": \"P\", \"kind\": \"bool\", \"slot\": %d, \"default\": false}"
        let nine = (0..<9).map { (i: Int) -> String in String(format: item, i, i) }.joined(separator: ",")
        assertRejected("{\"schema\": 1, \"variant\": \"v\", \"name\": \"V\", \"summary\": \"S\", \"parameters\": [\(nine)]}",
                       .parameterCount(document: d, count: 9))
        XCTAssertThrowsError(try validate(Self.valid, required: ["speed", "audioReactivity"])) { (error: Error) in
            XCTAssertEqual(error as? ShaderMetadataError, .missingRequiredParameter(document: d, parameterID: "audioReactivity"))
        }
    }
}
