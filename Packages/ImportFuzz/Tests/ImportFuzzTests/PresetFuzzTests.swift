// PresetFuzzTests.swift — QA-005-T08: Milkdrop preset text (PRE-012) under mutated bytes. Every
// input gets a typed validation (accepted or a quarantine reason) and the same bytes always give
// the same validation; a subset goes through the user preset import path (files in a temporary
// directory, no trial runner) and ends added, waiting, quarantined or refused, and the library
// reloads with the same presets (QA-005-R6).
import Foundation
import FuzzKit
import PresetLibrary
import XCTest

final class PresetFuzzTests: XCTestCase {
    /// Built-in presets reach 168 KB, but the validator's line, block and statement checks all work
    /// on far smaller spans; 16 KiB keeps the default run short. Larger inputs: `FUZZ_ITERATIONS` and
    /// PRE-012's own sweep (`PRESET_MUTATION_SWEEP_FULL=1`).
    static let budget = FuzzBudget(inputs: 300, maxInputBytes: 16_384)
    /// Each import writes files, so the import subset is small (`FUZZ_ITERATIONS / 25` on demand).
    static let importBudget = FuzzBudget(inputs: 40, maxInputBytes: 16_384)
    static let textures: Set<String> = ["noise_lq", "noise_mq", "noise_hq", "noisevol_lq", "noisevol_hq"]

    func testMutatedPresetTextIsValidatedDeterministically() {
        let corpus = FuzzCorpora.load("preset")
        let campaign = FuzzCampaign(name: "preset-validator", seed: 0x05E7_0001, budget: Self.budget,
                                    strategies: FuzzMutation.text, corpus: corpus.items)
        let report = campaign.run { (input: FuzzInput) -> FuzzOutcome in
            let first = MilkdropPresetValidator.validate(input.bytes, knownTextures: Self.textures)
            let second = MilkdropPresetValidator.validate(input.bytes, knownTextures: Self.textures)
            let violation: String? = first == second ? nil : "validation differs between two calls"
            if first.warnings.count > PresetImportLimits.maxWarnings {
                return .refused(violation: "more warnings than the limit: \(first.warnings.count)")
            }
            return first.rejection == nil ? .accepted(violation: violation) : .refused(violation: violation)
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        XCTAssertGreaterThanOrEqual(report.accepted, corpus.items.count)
        XCTAssertGreaterThan(report.refused, 0)
    }

    func testMutatedPresetFilesGoThroughTheImportPath() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qa005-\(UUID().uuidString)", isDirectory: true)
        let picked = directory.appendingPathComponent("picked", isDirectory: true)
        let libraryFolder = directory.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = UserPresetLibrary(directory: libraryFolder)
        await library.load()
        let corpus = FuzzCorpora.load("preset")
        let campaign = FuzzCampaign(name: "preset-import", seed: 0x05E7_0002, budget: Self.importBudget,
                                    strategies: FuzzMutation.text, corpus: corpus.items, budgetDivisor: 25)
        let report = await campaign.runAsync { (input: FuzzInput) async -> FuzzOutcome in
            let url = picked.appendingPathComponent("Author - fuzz \(input.iteration).milk")
            do { try Data(input.bytes).write(to: url) } catch { return .refused(violation: "could not write the picked file") }
            switch await library.importFile(at: url) {
            case .added, .waiting: return .accepted()
            case .quarantined, .refused: return .refused()
            }
        }
        assertClean(report, minimumInputs: campaign.budget.inputs)
        let before = await library.snapshot
        let reloaded = UserPresetLibrary(directory: libraryFolder)
        let after = await reloaded.load()
        XCTAssertEqual(after.availability, .available, "the library stays readable")
        XCTAssertEqual(after.playable.count + after.pending.count + after.quarantined.count,
                       before.playable.count + before.pending.count + before.quarantined.count,
                       "the library reloads with the same presets")
        XCTAssertGreaterThan(before.pending.count + before.quarantined.count, 0)
    }
}
