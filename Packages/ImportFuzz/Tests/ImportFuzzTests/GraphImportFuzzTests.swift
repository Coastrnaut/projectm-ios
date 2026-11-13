// GraphImportFuzzTests.swift — QA-005-T11: generator-graph import (SHD-011) under mutated bytes and
// file names. Every input is accepted or refused with a typed `GeneratorGraphImportError`; an
// accepted graph's canonical bytes import again to an equal document (QA-005-R6).
import Foundation
import FuzzKit
import GeneratorGraph
import GeneratorGraphImport
import XCTest

final class GraphImportFuzzTests: XCTestCase {
    /// The importer's limit is 64 KiB; inputs stay small (the examples are about 1 KB) except where
    /// repetition grows them, and the size refusal is covered by SHD-011's own tests.
    static let budget = FuzzBudget(inputs: 600, maxInputBytes: 8_192)
    static let fileNames: [String?] = [nil, "graph.json", "GRAPH.JSON", "graph", "graph.metal", "graph.json.zip", ".json", "a.b.json"]

    func testMutatedGraphFilesImportOrRefuseWithTypedErrors() {
        let corpus = FuzzCorpora.load("graph")
        let campaign = FuzzCampaign(name: "graph-import", seed: 0x05D1_1001, budget: Self.budget,
                                    strategies: FuzzMutation.json, corpus: corpus.items, customMutations: [FuzzJSON.mutation])
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            let name = Self.fileNames[input.iteration % Self.fileNames.count]
            let imported: ImportedGeneratorGraph
            do throws(GeneratorGraphImportError) {
                imported = try GeneratorGraphImporter.importGraph(Data(input.bytes), fileName: name)
            } catch {
                return .refused()
            }
            do throws(GeneratorGraphImportError) {
                let again = try GeneratorGraphImporter.importGraph(imported.canonicalData, fileName: "graph.json")
                if again.document != imported.document { return .accepted(violation: "canonical bytes import to a different document") }
                if again.canonicalData != imported.canonicalData { return .accepted(violation: "canonical bytes are not a fixed point") }
            } catch {
                return .accepted(violation: "canonical bytes of an accepted graph are refused: \(error)")
            }
            return .accepted()
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThan(report.accepted, 10, "value mutations keep some graphs valid")
        XCTAssertGreaterThan(report.refused, report.inputs / 4)
    }
}
