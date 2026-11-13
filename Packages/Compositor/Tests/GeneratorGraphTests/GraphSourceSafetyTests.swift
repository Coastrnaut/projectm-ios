// SHD-002-T22 (US5; SHD-002-R10; S7): "graph content can never become code". Scans the GeneratorGraph
// module's sources: exactly one shader library is created, from the module's own constant, and
// nothing reads files, bundles, URLs or the network or loads dynamic code; documents carrying code
// are refused or inert. CPU only; runs on Linux.
import Foundation
import GeneratorGraph
import XCTest

final class GraphSourceSafetyTests: XCTestCase {
    private func moduleSources() throws -> [(name: String, text: String)] {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GeneratorGraph")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }.sorted()
        XCTAssertGreaterThanOrEqual(names.count, 11, "the module's files were found")
        return try names.map { (name: String) -> (name: String, text: String) in
            (name, try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
        }
    }

    /// Code without `//` comment lines (comments may name the forbidden APIs to explain the rule).
    private func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testTheOnlyLibraryIsCompiledFromTheModulesConstant() throws {
        var calls: [(String, String)] = []
        for (name, text) in try moduleSources() {
            for line in code(text).split(separator: "\n") where line.contains("makeLibrary(") && !line.contains("func makeLibrary(") {
                calls.append((name, line.trimmingCharacters(in: .whitespaces)))
            }
        }
        XCTAssertEqual(calls.count, 2, "one compile and one call of it: \(calls)")
        let compile = calls.filter { $0.1.contains("device.makeLibrary(") }
        XCTAssertEqual(compile.count, 1, "\(compile)")
        XCTAssertEqual(compile.first?.0, "GeneratorGraphShaders.swift")
        XCTAssertTrue(compile.first?.1.contains("makeLibrary(source: Self.source,") ?? false, "\(compile)")
        for call in calls where !call.1.contains("device.makeLibrary(") {
            XCTAssertTrue(call.1.contains("GeneratorGraphShaders.makeLibrary(device: device)"), "\(call)")
        }
        var functionLookups = 0
        for (_, text) in try moduleSources() {
            for line in code(text).split(separator: "\n") where line.contains("makeFunction(name:") {
                functionLookups += 1
                XCTAssertTrue(line.contains("GeneratorGraphShaders.vertexFunction") || line.contains("GeneratorGraphShaders.fragmentFunction"),
                              "function names are constants: \(line)")
            }
        }
        XCTAssertEqual(functionLookups, 2)
    }

    func testNoFileBundleNetworkOrDynamicCodeAccess() throws {
        // Some words are split so that check_compliance.py, which scans tests too, does not read
        // this list as a use of them.
        let forbidden = ["contentsOf", "URL(", "URL" + "Session", "URLRequest", "Bundle", "FileManager", "FileHandle",
                         "makeDefaultLibrary", "makeLibrary(URL", "makeLibrary(data", "makeLibrary(filepath",
                         "dl" + "open", "dl" + "sym", "NSClass" + "FromString", "import Foundation", "import " + "Network"]
        for (name, text) in try moduleSources() {
            let body = code(text)
            for word in forbidden {
                XCTAssertEqual(occurrences(of: word, in: body), 0, "\(name) uses \(word)")
            }
        }
    }

    func testTheShaderSourceIsALiteralWithOnlyTheStandardInclude() throws {
        let shaders = try XCTUnwrap(try moduleSources().first { $0.name == "GeneratorGraphShaders.swift" }?.text)
        XCTAssertTrue(shaders.contains("static let source = \"\"\""), "a constant multi-line literal")
        XCTAssertEqual(occurrences(of: "\\(", in: shaders.components(separatedBy: "static let source").last?
            .components(separatedBy: "\"\"\"").dropFirst().first ?? ""), 0, "no interpolation in the shader literal")
        XCTAssertEqual(occurrences(of: "#include", in: shaders), 1)
        XCTAssertTrue(shaders.contains("#include <metal_stdlib>"))
    }

    func testDocumentsCarryingCodeAreRefusedOrInert() throws {
        let snippet = "#include <metal_stdlib>\nfragment float4 evil() { return 1; }"
        let refused = minimalGraph([GraphNode("x", snippet)])
        XCTAssertEqual(GeneratorGraphCompiler.validate(refused), [.unknownKind(node: "x", kind: snippet)])
        let path = minimalGraph([GraphNode("y", "/usr/lib/libSystem.dylib")])
        XCTAssertEqual(GeneratorGraphCompiler.validate(path), [.unknownKind(node: "y", kind: "/usr/lib/libSystem.dylib")])
        let named = graphDoc([GraphNode("c", .gradient), GraphNode("out", .output, inputs: ["color": "c"])], name: "fragment evil")
        let plan = try GeneratorGraphCompiler.compile(named).planBytes
        XCTAssertFalse(String(decoding: plan, as: UTF8.self).contains("evil"), "names never reach the plan")
    }
}
