// PresetArchiveConflictAppTests.swift — FILE-004-T08 (specs/111-file-004-import-conflict-resolver;
// FILE-004-R1, R3, R8, R9): per-conflict choices through the app's coordinator. A real
// UserPresetLibrary in a temporary folder and a passing trial; the archive is the DEBUG fixture, which
// clashes by name with a preset imported first. No main-actor state is touched in setUp or tearDown.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetArchiveConflictAppTests: XCTestCase {
    private struct PassingTrial: PresetTrialRunning {
        func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult { .passed }
    }

    private final class Spoken {
        var general: [String] = []
        var library: [String] = []
    }

    private static let harborID = "user/file003-fixture-harbor"

    /// A coordinator whose library holds "Fixture Harbor" (another text), with the fixture archive's
    /// preview open: one name conflict (Fixture Harbor) and one new preset (Fixture Drift).
    private func previewing() async throws -> (coordinator: UserPresetsCoordinator, spoken: Spoken, existingID: String) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("PresetArchiveConflictAppTests-\(UUID().uuidString)", isDirectory: true)
        let picked = base.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let library = UserPresetLibrary(directory: base.appendingPathComponent("UserPresets"))
        let spoken = Spoken()
        let coordinator = UserPresetsCoordinator(library: library, announce: { (text: String) in spoken.general.append(text) },
                                                 exportDirectory: base.appendingPathComponent("PresetExport"),
                                                 libraryRoots: [base.appendingPathComponent("UserPresets")])
        coordinator.announceLibrary = { (text: String) in spoken.library.append(text) }
        await coordinator.load()
        await coordinator.rendererReady(trial: PassingTrial(), presentedFrames: { () -> Int in 0 })
        let lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=1.05",
                               "per_frame_1=rot = 0.02*sin(time);", ""]
        let milk = picked.appendingPathComponent("Fixture Harbor.milk")
        try Data(lines.joined(separator: "\n").utf8).write(to: milk)
        await coordinator.importPicked(.success(milk))
        let existing = try XCTUnwrap(coordinator.playable.first { (preset: UserPreset) -> Bool in preset.name == "Fixture Harbor" })
        let archive = picked.appendingPathComponent("Shared.zip")
        try XCTUnwrap(UserPresetsCoordinator.fixtureArchive()).write(to: archive)
        await coordinator.importPicked(.success(archive))
        return (coordinator, spoken, existing.id)
    }

    func testARowChoiceReplansAndReplaceKeepsTheIdentifier() async throws {
        let p = try await previewing()
        let plan = try XCTUnwrap(p.coordinator.archiveReview?.plan)
        XCTAssertEqual(plan.counts.nameConflicts, 1)
        XCTAssertEqual(plan.actions.map(\.name), ["Fixture Drift", "Fixture Harbor copy"])

        await p.coordinator.setArchiveChoice(.skip, for: Self.harborID)
        XCTAssertEqual(p.coordinator.archiveReview?.plan.overrides, [Self.harborID: .skip])
        XCTAssertEqual(p.coordinator.archiveReview?.plan.counts.toInstall, 1)
        await p.coordinator.setArchiveChoice(.keepBoth, for: Self.harborID)
        XCTAssertEqual(p.coordinator.archiveReview?.plan.overrides, [:], "the default is stored as no override")

        await p.coordinator.setArchiveChoice(.replace, for: Self.harborID)
        let replace = try XCTUnwrap(p.coordinator.archiveReview?.plan)
        XCTAssertEqual(replace.actions.map(\.id), ["user/file003-fixture-drift", p.existingID])
        await p.coordinator.installArchive()
        XCTAssertNil(p.coordinator.archiveReview)
        XCTAssertEqual(p.spoken.library.last, "Installed 2 presets (1 replaced). They are checked before they can play.")
        XCTAssertTrue(p.spoken.general.filter { (text: String) -> Bool in text.hasPrefix("Installed") }.isEmpty,
                      "archive words go through the library lane")
        XCTAssertEqual(Set(p.coordinator.playable.map(\.name)), ["Fixture Drift", "Fixture Harbor"])
        XCTAssertTrue(p.coordinator.playable.contains { (preset: UserPreset) -> Bool in preset.id == p.existingID })
    }

    func testApplyToAllClearsTheRowChoices() async throws {
        let p = try await previewing()
        await p.coordinator.setArchiveChoice(.skip, for: Self.harborID)
        await p.coordinator.setArchivePolicy(.replace)
        let plan = try XCTUnwrap(p.coordinator.archiveReview?.plan)
        XCTAssertEqual(plan.policy, .replace)
        XCTAssertEqual(plan.overrides, [:])
        XCTAssertEqual(plan.replaceCount, 1)
        p.coordinator.cancelArchive()
    }

    func testWordsOfTheChoices() throws {
        XCTAssertEqual(UserPresetsCoordinator.policyTitle(.replace), "Replace")
        let library: [UserPreset] = []
        let plan = PresetArchiveImportPlanner.plan(archive: try XCTUnwrap(UserPresetsCoordinator.fixtureArchive()), library: library,
                                                   context: .empty, policy: .replace)
        XCTAssertNil(UserPresetsCoordinator.archiveInstallText(try XCTUnwrap(plan.entries.first)), "a new preset installs as it is")
    }

    func testRowWordsForReplaceSkipAndFallback() async throws {
        let p = try await previewing()
        await p.coordinator.setArchiveChoice(.replace, for: Self.harborID)
        let replace = try XCTUnwrap(p.coordinator.archiveReview?.plan.entries.first { (e: PresetArchivePlanEntry) -> Bool in e.isConflict })
        XCTAssertEqual(UserPresetsCoordinator.archiveInstallText(replace), "Replaces “Fixture Harbor”; collections that list it keep it.")
        await p.coordinator.setArchiveChoice(.skip, for: Self.harborID)
        let skip = try XCTUnwrap(p.coordinator.archiveReview?.plan.entries.first { (e: PresetArchivePlanEntry) -> Bool in e.isConflict })
        XCTAssertEqual(UserPresetsCoordinator.archiveInstallText(skip), "Left out. Your preset is not changed.")
        p.coordinator.cancelArchive()
    }
}
