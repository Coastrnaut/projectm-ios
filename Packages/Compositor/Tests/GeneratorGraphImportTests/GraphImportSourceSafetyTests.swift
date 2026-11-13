// SHD-011-T09 (US1; SHD-011-R10, S2): "no import path ever calls a loader". Scans the
// GeneratorGraphImport module's sources: no dynamic loading, bundles, files, URLs, network, process,
// script engine or shader compilation, and Foundation is used only for Data and JSON coding. The
// repository-wide rules are scripts/check_compliance.py's (SHD-011 rules). CPU only; runs on Linux.
import Foundation
import XCTest

final class GraphImportSourceSafetyTests: XCTestCase {
    private func moduleSources() throws -> [(name: String, text: String)] {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GeneratorGraphImport")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }.sorted()
        XCTAssertEqual(names, ["ExecutableSignature.swift", "GeneratorGraphImportError.swift", "GeneratorGraphImporter.swift",
                               "GraphImportLimits.swift"])
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

    func testNoLoaderFileNetworkProcessScriptOrShaderAccess() throws {
        // Some words are split so that check_compliance.py, which scans tests too, does not read
        // this list as a use of them (it also ignores string literals).
        let forbidden = ["dl" + "open", "dl" + "sym", "Bundle", "FileManager", "FileHandle", "contentsOf", "URL", "fopen",
                         "Session", "import " + "Network", "import Metal", "MTLDevice", "MTLLibrary", "MTLCompileOptions", "makeLibrary", "Process", "NSTask", "posix_spawn",
                         "NSExpression", "NSPredicate", "JSContext", "JavaScriptCore", "NSClass" + "FromString", "UserDefaults",
                         "write(to", "Data(contentsOf", "mmap", "PROT_EXEC", "unsafeBitCast", "@_silgen_name", "@_cdecl"]
        for (name, text) in try moduleSources() {
            let body = code(text)
            for word in forbidden {
                XCTAssertFalse(body.contains(word), "\(name) uses \(word)")
            }
        }
    }

    func testFoundationIsUsedOnlyForDataAndJSON() throws {
        var imports: [String] = []
        for (_, text) in try moduleSources() {
            for line in code(text).split(separator: "\n") where line.hasPrefix("import ") {
                imports.append(String(line))
            }
        }
        XCTAssertEqual(Set(imports), ["import Foundation", "import GeneratorGraph"])
        let importer = try XCTUnwrap(try moduleSources().first { $0.name == "GeneratorGraphImporter.swift" }?.text)
        XCTAssertTrue(importer.contains("JSONDecoder().decode(GeneratorGraphDocument.self"))
        XCTAssertEqual(importer.components(separatedBy: "GeneratorGraphCompiler.compile(").count - 1, 1,
                       "the only way out is SHD-002's compiler")
    }
}
