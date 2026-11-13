// SHD-011-T07, T08 (US1; SHD-011-R2, R4, R7; research SHD-011-D2): check order, nesting, encoding,
// determinism, the example graphs, and the size of the largest document SHD-002's limits allow.
// CPU only; runs on Linux.
import Foundation
import GeneratorGraph
import GeneratorGraphImport
import XCTest

final class GraphImportLimitTests: XCTestCase {
    private let valid = encoded(GeneratorGraphExamples.emberDrift)

    func testSizeIsCheckedBeforeContent() {
        var bigMachO = Data([0xCF, 0xFA, 0xED, 0xFE])
        bigMachO.append(Data(repeating: 0, count: GraphImportLimits.maximumBytes))
        XCTAssertEqual(refusal(bigMachO, nil), .tooLarge(bytes: 65_540, limit: 65_536))
        // The file name is checked first of all.
        XCTAssertEqual(refusal(bigMachO, "x.dylib"), .executableFileType("dylib"))
        XCTAssertEqual(refusal(Data(), "x.zip"), .executableFileType("zip"))
    }

    func testFileNames() {
        for name in ["graph.json", "GRAPH.JSON", "noextension", ".json", "folder/a.b/graph.json", nil] as [String?] {
            XCTAssertNoThrow(try GeneratorGraphImporter.importGraph(valid, fileName: name), "\(String(describing: name))")
        }
        for ext in ["dylib", "so", "framework", "bundle", "app", "metallib", "metal", "sh", "py", "js", "zip", "wasm"] {
            XCTAssertEqual(refusal(valid, "x.\(ext.uppercased())"), .executableFileType(ext))
        }
        XCTAssertEqual(refusal(valid, "graph.plist"), .unsupportedFileType("plist"))
    }

    func testNestingIsCountedOutsideStringsOnly() {
        let eight = Data("{\"a\":[[[[[[[1]]]]]]]}".utf8)
        XCTAssertNotEqual(refusal(eight, nil), .nestingTooDeep(limit: 8), "depth 8 passes the pre-scan")
        XCTAssertEqual(refusal(eight, nil), .malformed("missing key \"format\""))
        let inString = Data("{\"format\":\"[[[[[[[[[[[[\\\"[[[[\",\"a\":1}".utf8)
        XCTAssertEqual(refusal(inString, nil), .malformed("missing key \"version\""))
        let deep = Data(("{\"a\":" + String(repeating: "[", count: 100_00) + String(repeating: "]", count: 100_00) + "}").utf8)
        XCTAssertEqual(refusal(deep, nil), .nestingTooDeep(limit: 8))
    }

    func testByteOrderMarkAndWhitespaceAreAccepted() throws {
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data(" \n\t".utf8) + valid
        let imported = try GeneratorGraphImporter.importGraph(withBOM)
        XCTAssertEqual(imported.document, GeneratorGraphExamples.emberDrift)
        XCTAssertEqual(refusal(Data("   ".utf8), nil), .notGraphDocument)
        XCTAssertEqual(refusal(Data("\"text\"".utf8), nil), .notGraphDocument)
    }

    func testMalformedReasonsArePlatformIndependent() {
        XCTAssertEqual(refusal(Data("{".utf8), nil), .malformed("invalid JSON"))
        XCTAssertEqual(refusal(Data("{\"format\":\"projectm-ios.generator-graph\",\"version\":1,\"nodes\":[{\"id\":\"a\"}]}".utf8), nil),
                       .malformed("missing key \"kind\" at nodes[0]"))
        XCTAssertEqual(refusal(Data("{\"format\":\"projectm-ios.generator-graph\",\"version\":1,\"nodes\":[{\"id\":\"a\",\"kind\":\"time\",\"values\":{\"x\":\"no\"}}]}".utf8), nil),
                       .malformed("wrong type at nodes[0].values.x"))
    }

    func testNewerVersionAndOtherFormatAreSHD002Issues() {
        var newer = GeneratorGraphExamples.emberDrift
        newer.version = 2
        XCTAssertEqual(refusal(encoded(newer), nil), .invalidGraph(GeneratorGraphCompiler.validate(newer)))
        XCTAssertTrue(GeneratorGraphCompiler.validate(newer).contains(.unsupportedVersion(2)))
        var other = GeneratorGraphExamples.emberDrift
        other.format = "com.example.plugin"
        XCTAssertTrue(refusal(encoded(other), nil).map { (e: GeneratorGraphImportError) -> Bool in
            if case let .invalidGraph(issues) = e { return issues.contains(.unsupportedFormat("com.example.plugin")) }
            return false
        } ?? false)
    }

    func testExamplesRoundTripAndImportsAreDeterministic() throws {
        for example in GeneratorGraphExamples.all {
            let data = encoded(example)
            let first = try GeneratorGraphImporter.importGraph(data, fileName: "\(example.name).json")
            let second = try GeneratorGraphImporter.importGraph(data, fileName: "\(example.name).json")
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.document, example)
            XCTAssertEqual(first.canonicalData, data)
            XCTAssertEqual(try GeneratorGraphImporter.importGraph(first.canonicalData).document, example)
        }
        let hostile = Data([0xCA, 0xFE, 0xBA, 0xBE])
        XCTAssertEqual(refusal(hostile, nil), refusal(hostile, nil))
    }

    /// SHD-011-T08: an upper bound on any document within SHD-002's limits: 64 nodes, each of the
    /// kind with the most fields, every input set to a literal of its full width with the longest
    /// number text, every setting set, 32-character IDs and a 64-character name; pretty-printed.
    func testLargestDocumentWithinSHD002LimitsFitsTheByteLimit() throws {
        let longest = -1.2345678901234567e-300
        func widest(_ index: Int) -> GraphNode {
            let id = String(format: "%032d", index)
            let nodes = GraphNodeKind.allCases.map { (kind: GraphNodeKind) -> GraphNode in
                var values: [String: GraphValue] = [:]
                for input in kind.spec.inputs {
                    let width = max(1, input.type.componentCount)
                    values[input.name] = width == 1 ? .number(longest) : .numbers(Array(repeating: longest, count: width))
                }
                for setting in kind.spec.settings { values[setting.name] = .number(longest) }
                return GraphNode(id, kind, values: values)
            }
            return nodes.max { (a: GraphNode, b: GraphNode) -> Bool in encoded(a).count < encoded(b).count } ?? nodes[0]
        }
        let document = GeneratorGraphDocument(name: String(repeating: "n", count: GeneratorGraphLimits.nameLength),
                                              speed: longest, nodes: (0..<GeneratorGraphLimits.nodes).map(widest))
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
        let size = try pretty.encode(document).count
        print("SHD-011-T08: largest pretty-printed document within SHD-002's limits = \(size) bytes (compact \(encoded(document).count))")
        XCTAssertLessThan(size, GraphImportLimits.maximumBytes)
    }
}

private func encoded(_ node: GraphNode) -> Data {
    (try? JSONEncoder().encode(node)) ?? Data()
}
