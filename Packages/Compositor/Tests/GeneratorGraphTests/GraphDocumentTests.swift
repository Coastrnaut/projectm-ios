// SHD-002-T12 (US1; SHD-002-R1, R2, R3): the document's JSON form and the closed kind catalog.
// CPU only; runs on Linux.
import Foundation
import GeneratorGraph
import XCTest

final class GraphDocumentTests: XCTestCase {
    static let contractJSON = """
    {
      "format": "projectm-ios.generator-graph",
      "version": 1,
      "name": "Ember Drift",
      "speed": 0.2,
      "nodes": [
        {"id": "t", "kind": "time"},
        {"id": "flow", "kind": "drift", "inputs": {"phase": "t"}, "values": {"velocityX": 0.3, "velocityY": 0.1}},
        {"id": "n", "kind": "noise", "inputs": {"point": "flow"}, "values": {"scale": 3, "octaves": 4}},
        {"id": "c", "kind": "gradient", "inputs": {"t": "n"}, "values": {"colorA": [0.05, 0.0, 0.02], "colorB": [0.9, 0.35, 0.05]}},
        {"id": "out", "kind": "output", "inputs": {"color": "c"}}
      ]
    }
    """

    func testExamplesRoundTripThroughJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for document in GeneratorGraphExamples.all {
            let data = try encoder.encode(document)
            let decoded = try JSONDecoder().decode(GeneratorGraphDocument.self, from: data)
            XCTAssertEqual(decoded, document, document.name)
            XCTAssertEqual(try encoder.encode(decoded), data, "\(document.name): stable text form")
            XCTAssertEqual(try GeneratorGraphCompiler.compile(decoded).planBytes,
                           try GeneratorGraphCompiler.compile(document).planBytes, document.name)
        }
    }

    func testTheContractExampleDecodesToEmberDrift() throws {
        let decoded = try JSONDecoder().decode(GeneratorGraphDocument.self, from: Data(Self.contractJSON.utf8))
        XCTAssertEqual(decoded, GeneratorGraphExamples.emberDrift)
    }

    func testMissingOptionalFieldsUseDefaultsAndUnknownKeysAreIgnored() throws {
        let json = """
        {"format": "projectm-ios.generator-graph", "version": 1, "extra": {"ignored": true},
         "nodes": [{"id": "out", "kind": "output", "note": "x"}]}
        """
        let d = try JSONDecoder().decode(GeneratorGraphDocument.self, from: Data(json.utf8))
        XCTAssertEqual(d.name, "")
        XCTAssertEqual(d.speed, GeneratorGraphDocument.defaultSpeed)
        XCTAssertEqual(d.nodes, [GraphNode("out", .output)])
    }

    func testKindCatalog() {
        XCTAssertEqual(GraphNodeKind.allCases.count, 26)
        let opcodes = GraphNodeKind.allCases.map { (k: GraphNodeKind) -> UInt32 in k.opcode }
        XCTAssertEqual(Set(opcodes).count, 26, "unique opcodes")
        XCTAssertEqual(opcodes, Array(1...26).map { UInt32($0) }, "opcodes are permanent and dense")
        for kind in GraphNodeKind.allCases {
            let spec = kind.spec
            XCTAssertLessThanOrEqual(spec.valueInputs.count, 3, "\(kind): three operand slots")
            XCTAssertLessThanOrEqual(spec.settings.count, 4, "\(kind): four setting slots")
            XCTAssertLessThanOrEqual(spec.inputs.filter { $0.type == .phase }.count, 1)
            for input in spec.inputs {
                if input.type == .phase || input.type == .point {
                    XCTAssertTrue(input.defaultValue.isEmpty, "\(kind).\(input.name)")
                } else {
                    XCTAssertEqual(input.defaultValue.count, input.type.componentCount, "\(kind).\(input.name)")
                    for v in input.defaultValue {
                        XCTAssertTrue(v >= input.lower && v <= input.upper, "\(kind).\(input.name) default in range")
                    }
                }
                if input.required {
                    XCTAssertTrue(input.type == .phase || kind == .output, "\(kind).\(input.name) required")
                }
            }
            for s in spec.settings {
                XCTAssertTrue(s.defaultValue >= s.lower && s.defaultValue <= s.upper, "\(kind).\(s.name)")
            }
            XCTAssertNil(spec.inputs.first { spec.setting(named: $0.name) != nil }, "\(kind): names unique")
        }
        XCTAssertNil(GraphNodeKind.output.spec.output)
        XCTAssertEqual(GraphNodeKind.time.spec.output, .phase)
        XCTAssertEqual(GraphNodeKind.allCases.filter { $0.spec.output == .phase }, [.time], "only time makes phase")
    }
}
