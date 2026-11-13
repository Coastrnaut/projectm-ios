// ExpressionSourceSafetyTests.swift — SHD-009-T17: the module is data-only by construction: it
// imports only ParameterGraph and the C math library and uses no expression evaluator, script
// engine, dynamic loader, process, file, bundle, network or shader compiler (SHD-009-R11; S6;
// ADR-0018).
import Foundation
import XCTest

final class ExpressionSourceSafetyTests: XCTestCase {
    private static let forbidden: [String] = [
        "NSExpression", "NSPredicate", "JavaScriptCore", "JSContext", "JSValue", "dlopen", "dlsym", "Process",
        "NSTask", "posix_spawn", "system(", "makeLibrary", "MTLCompileOptions", "MTLDevice", "URL(", "URLSession",
        "FileManager", "FileHandle", "Bundle", "NSClassFromString", "NSSelectorFromString", "perform(", "UnsafeRawPointer(bitPattern",
    ]

    func testModuleUsesOnlyAllowedImportsAndNoForbiddenFacilities() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ParameterExpression")
        let files = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { (name: String) -> Bool in name.hasSuffix(".swift") }
            .sorted()
        XCTAssertGreaterThanOrEqual(files.count, 9)
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for line in text.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") || trimmed.hasPrefix("@_exported") || trimmed.hasPrefix("@preconcurrency import") else { continue }
                let allowed: Set<String> = file == "ExpressionMath.swift"
                    ? ["import Darwin", "import Glibc", "import Musl"] : ["import ParameterGraph"]
                XCTAssertTrue(allowed.contains(trimmed), "\(file): \(trimmed)")
            }
            for word in Self.forbidden {
                XCTAssertFalse(text.contains(word), "\(file) mentions \(word)")
            }
        }
    }
}
