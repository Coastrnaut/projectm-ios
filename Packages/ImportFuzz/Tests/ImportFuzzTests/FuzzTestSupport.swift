// FuzzTestSupport.swift — corpus access, the MOD-001 registry and the shared assertion
// (QA-005-T07; contract H4).
import Foundation
import FuzzKit
import ParameterGraph
import ProceduralMaterials
import VisualParameters
import XCTest

enum FuzzCorpora {
    /// The formats with a checked-in corpus directory.
    static let formats = ["archive", "expression", "graph", "json", "osc", "preset", "scene"]

    static var root: URL {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            return URL(fileURLWithPath: "/nonexistent")
        }
        return url.appendingPathComponent("Corpus", isDirectory: true)
    }

    static func load(_ format: String) -> FuzzCorpus { FuzzCorpus.load(root.appendingPathComponent(format, isDirectory: true)) }

    /// The app's parameter catalog (visual + material), as SCN-001 and FILE-001 tests build it.
    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: VisualParameterCatalog.descriptors + ProceduralMaterialCatalog.descriptors)
    }
}

extension XCTestCase {
    /// Fails with at most the first 10 violations and prints the report line (contract H4).
    func assertClean(_ report: FuzzReport, minimumInputs: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        print(report)
        XCTAssertGreaterThanOrEqual(report.inputs, minimumInputs, "\(report.name) ran too few inputs", file: file, line: line)
        for violation in report.violations.prefix(10) { XCTFail(violation, file: file, line: line) }
        if report.violations.count > 10 { XCTFail("… and \(report.violations.count - 10) more", file: file, line: line) }
    }
}
