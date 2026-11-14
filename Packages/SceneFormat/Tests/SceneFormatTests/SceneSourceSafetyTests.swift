// SceneSourceSafetyTests.swift — the scene module reads no files, opens no URLs, uses no network or
// processes, loads nothing dynamically and executes nothing from a document (SCN-001-T22;
// SCN-001-R14; contract C7). Scans the module's own sources; CPU only, runs on Linux.
import Foundation
import XCTest

final class SceneSourceSafetyTests: XCTestCase {
    private func moduleSources() throws -> [(name: String, text: String)] {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SceneFormat")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }.sorted()
        XCTAssertEqual(names, ["SceneDecoding.swift", "SceneDocument.swift", "SceneEditing.swift",
                               "SceneEffectChain.swift", "SceneEffectChainPresets.swift",   // FX-020
                               "SceneEncoding.swift", "SceneGroup.swift",   // CMP-011
                               "SceneHistory.swift", "SceneIssue.swift",
                               "SceneJSON.swift", "SceneJSONParser.swift", "SceneJSONWriter.swift", "SceneLiveState.swift", "SceneMigration.swift",
                               "SceneModulationRestore.swift", "SceneRepair.swift", "SceneSlideshow.swift",   // MED-006
                               "SceneValidation.swift", "SceneVideoLoop.swift"])   // MED-003
        return try names.map { (name: String) -> (name: String, text: String) in
            (name, try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
        }
    }

    /// Code without `//` comment lines (comments may name the forbidden APIs to explain the rule).
    private func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { (line: Substring) -> Bool in !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testNoFileURLNetworkProcessLoaderOrEvaluator() throws {
        let forbidden = ["dl" + "open", "dl" + "sym", "Bundle", "FileManager", "FileHandle", "Data(contentsOf", "String(contentsOf", "URL", "fopen",
                         "fwrite", "ff" + "lush", "std" + "out", "std" + "err", "Process", "NSTask", "URL" + "Session", "Net" + "work", "NSExpression",
                         "JSContext", "JSONSerialization", "JSONDecoder", "JSONEncoder", "evaluate(", "write(to", "@_silgen_name",
                         "@_cdecl", "UserDefaults"]
        for (name, text) in try moduleSources() {
            let body = code(text)
            for word in forbidden {
                XCTAssertFalse(body.contains(word), "\(name) uses \(word)")
            }
        }
    }

    func testFoundationOnlyAtTheValidationEdge() throws {
        for (name, text) in try moduleSources() where code(text).contains("import Foundation") {
            XCTAssertEqual(name, "SceneValidation.swift", "only validation needs Foundation (Data for MED-009/SHD-011, trimming)")
        }
    }
}
