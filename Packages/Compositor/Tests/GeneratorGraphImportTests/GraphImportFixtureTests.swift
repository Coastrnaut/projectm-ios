// SHD-011-T06 (US1; SHD-011-S1; contracts/graph-import.md "Fixture table"): every hostile and valid
// fixture file maps to its exact outcome and message. Fixtures are built in memory (no files are
// read). CPU only; runs on Linux.
import Foundation
import GeneratorGraph
import GeneratorGraphImport
import XCTest

func encoded(_ document: GeneratorGraphDocument) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(document)) ?? Data()
}

func outcome(_ data: Data, _ name: String?) -> Result<ImportedGeneratorGraph, GeneratorGraphImportError> {
    do {
        return .success(try GeneratorGraphImporter.importGraph(data, fileName: name))
    } catch {
        return .failure(error)
    }
}

func refusal(_ data: Data, _ name: String?) -> GeneratorGraphImportError? {
    if case let .failure(e) = outcome(data, name) { return e }
    return nil
}

/// A zip archive with only central-directory records (enough for the signature and the entry scan).
func zip(_ names: [String]) -> Data {
    var bytes: [UInt8] = [0x50, 0x4B, 0x03, 0x04] + [UInt8](repeating: 0, count: 26)
    for name in names {
        let utf8 = Array(name.utf8)
        var record: [UInt8] = [0x50, 0x4B, 0x01, 0x02] + [UInt8](repeating: 0, count: 42)
        record[28] = UInt8(utf8.count & 0xFF)
        record[29] = UInt8(utf8.count >> 8)
        bytes += record + utf8
    }
    bytes += [0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18)
    return Data(bytes)
}

let metalKind = "#include <metal_stdlib>\nfragment float4 evil() { return float4(1); }"

final class GraphImportFixtureTests: XCTestCase {
    private let valid = encoded(GeneratorGraphExamples.emberDrift)

    func testHostileFixturesAreRefusedWithTheirExactReason() {
        let machO64 = Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01] + [UInt8](repeating: 0, count: 24))
        let machO32BE = Data([0xFE, 0xED, 0xFA, 0xCE] + [UInt8](repeating: 0, count: 24))
        let fat = Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02] + [UInt8](repeating: 0, count: 40))
        let script = Data("#!/bin/sh\nrm -rf ~\n".utf8)
        let elf = Data([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00])
        let cycle = GeneratorGraphDocument(name: "Loop", nodes: [
            GraphNode("a", .multiply, inputs: ["a": "b"]),
            GraphNode("b", .multiply, inputs: ["a": "a"]),
            GraphNode("c", .gradient, inputs: ["t": "a"]),
            GraphNode("out", .output, inputs: ["color": "c"]),
        ])
        let metal = GeneratorGraphDocument(name: "Evil", nodes: [
            GraphNode("c", .gradient), GraphNode("out", .output, inputs: ["color": "c"]), GraphNode("x", metalKind),
        ])
        let cases: [(String, Data, String?, GeneratorGraphImportError)] = [
            ("thin Mach-O 64", machO64, "graph.json", .executableContent(.machO)),
            ("thin Mach-O 32 BE", machO32BE, nil, .executableContent(.machO)),
            ("universal binary", fat, "graph.json", .executableContent(.universalBinary)),
            ("shell script", script, "graph.json", .executableContent(.script)),
            ("ELF", elf, nil, .executableContent(.elf)),
            ("zip with an app and a dylib", zip(["readme.txt", "Payload/Evil.app/Evil", "lib/libevil.dylib"]), "graph.json",
             .archive(codeEntry: "Payload/Evil.app/Evil")),
            ("zip with only a graph", zip(["graph.json"]), nil, .archive(codeEntry: nil)),
            ("valid graph named .dylib", valid, "evil.dylib", .executableFileType("dylib")),
            ("valid graph named .txt", valid, "graph.txt", .unsupportedFileType("txt")),
            ("empty", Data(), "graph.json", .empty),
            ("nesting 9", Data("{\"a\":[[[[[[[[1]]]]]]]]}".utf8), nil, .nestingTooDeep(limit: 8)),
            ("top-level array", Data("[1, 2]".utf8), nil, .notGraphDocument),
            ("not UTF-8", Data([0xFF, 0xFE, 0x00, 0x7B]), nil, .notText),
            ("Metal source as a node kind", encoded(metal), "graph.json", .invalidGraph([.unknownKind(node: "x", kind: metalKind)])),
            ("cycle", encoded(cycle), nil, .invalidGraph(GeneratorGraphCompiler.validate(cycle))),
            ("wrong type", Data("{\"format\": 1}".utf8), nil, .malformed("wrong type at format")),
        ]
        for (label, data, name, expected) in cases {
            XCTAssertEqual(refusal(data, name), expected, label)
        }
        if case let .invalidGraph(issues) = refusal(encoded(cycle), nil) {
            XCTAssertTrue(issues.contains { (i: GeneratorGraphIssue) -> Bool in if case .cycle = i { return true }; return false })
        } else {
            XCTFail("the cycle is refused by SHD-002")
        }
    }

    func testOversizedJSONIsRefusedBeforeDecoding() {
        var big = valid
        big.append(Data(repeating: 0x20, count: GraphImportLimits.maximumBytes + 1 - valid.count))
        XCTAssertEqual(refusal(big, "big.json"), .tooLarge(bytes: 65_537, limit: 65_536))
        var edge = valid
        edge.append(Data(repeating: 0x20, count: GraphImportLimits.maximumBytes - valid.count))
        XCTAssertEqual(edge.count, 65_536)
        XCTAssertNoThrow(try GeneratorGraphImporter.importGraph(edge, fileName: "edge.json"))
    }

    func testValidGraphIsAcceptedAndUnknownKeysAreDropped() throws {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["plugin"] = "/usr/lib/x.dylib"
        let withPlugin = try JSONSerialization.data(withJSONObject: object)
        let imported = try GeneratorGraphImporter.importGraph(withPlugin, fileName: "Ember.JSON")
        XCTAssertEqual(imported.document, GeneratorGraphExamples.emberDrift)
        XCTAssertEqual(imported.compiled, try GeneratorGraphCompiler.compile(GeneratorGraphExamples.emberDrift))
        XCTAssertEqual(imported.canonicalData, valid)
        XCTAssertFalse(String(decoding: imported.canonicalData, as: UTF8.self).contains("plugin"))
    }

    func testEveryRefusalHasItsMessage() {
        let expected: [(GeneratorGraphImportError, String)] = [
            (.executableFileType("dylib"), "Files of type \".dylib\" can contain code and are never imported."),
            (.unsupportedFileType("txt"), "Files of type \".txt\" are not generator graphs; use a .json graph file."),
            (.empty, "The file is empty."),
            (.tooLarge(bytes: 65_537, limit: 65_536), "The file is 65537 bytes; graph files are at most 65536 bytes."),
            (.executableContent(.machO), "The file is a Mach-O program or library, not a graph; programs and libraries are never imported."),
            (.archive(codeEntry: nil), "The file is an archive; archives are never imported."),
            (.archive(codeEntry: "a.dylib"), "The file is an archive containing code (\"a.dylib\"); archives are never imported."),
            (.notText, "The file is not UTF-8 text."),
            (.notGraphDocument, "The file is not a generator graph document (expected a JSON object)."),
            (.nestingTooDeep(limit: 8), "The file nests brackets deeper than 8 levels."),
            (.malformed("invalid JSON"), "The graph document could not be read: invalid JSON."),
            (.invalidGraph([.noOutput]), GeneratorGraphIssue.noOutput.message),
        ]
        for (error, message) in expected {
            XCTAssertEqual(error.message, message)
        }
    }
}
