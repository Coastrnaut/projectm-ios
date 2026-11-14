// PresetArchiveImportAppTests.swift — FILE-003-T09, T12: the preset archive preview through the
// app's coordinator (FILE-003-R1, R2, R6, R8, R10, R11, R13; S1, S4, S5). A real UserPresetLibrary in
// a temporary folder and a passing trial. The archive is the DEBUG fixture (two presets, one without
// licence lines) or one written here. No main-actor state is touched in setUp or tearDown.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetArchiveImportAppTests: XCTestCase {
    private struct PassingTrial: PresetTrialRunning {
        func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult { .passed }
    }

    private final class Spoken {
        var general: [String] = []
        var library: [String] = []
    }

    private struct Harness {
        let base: URL
        let coordinator: UserPresetsCoordinator
        let library: UserPresetLibrary
        let spoken: Spoken
        let roots: [URL]
        var picked: URL { base.appendingPathComponent("picked", isDirectory: true) }
    }

    private func harness() async throws -> Harness {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("PresetArchiveImportAppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("picked"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let collections = base.appendingPathComponent(PresetCollectionStore.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: collections, withIntermediateDirectories: true)
        try Data("{\"collections\":[]}".utf8).write(to: collections.appendingPathComponent(PresetCollectionStore.fileName))
        let library = UserPresetLibrary(directory: base.appendingPathComponent("UserPresets"))
        let spoken = Spoken()
        let coordinator = UserPresetsCoordinator(library: library, announce: { (text: String) in spoken.general.append(text) },
                                                 exportDirectory: base.appendingPathComponent("PresetExport"),
                                                 libraryRoots: [base.appendingPathComponent("UserPresets"), collections])
        coordinator.announceLibrary = { (text: String) in spoken.library.append(text) }
        await coordinator.load()
        await coordinator.rendererReady(trial: PassingTrial(), presentedFrames: { () -> Int in 0 })
        return Harness(base: base, coordinator: coordinator, library: library, spoken: spoken, roots: coordinator.libraryRoots)
    }

    private func text(_ zoom: String) -> String {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=\(zoom)", "per_frame_1=rot = 0.02*sin(time);", ""]
            .joined(separator: "\n")
    }

    private func importMilk(_ contents: String, named name: String, _ h: Harness) async throws {
        let url = h.picked.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        await h.coordinator.importPicked(.success(url))
    }

    private func writeArchive(_ data: Data, named name: String = "Shared Presets.zip", _ h: Harness) throws -> URL {
        let url = h.picked.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func fixture() throws -> Data { try XCTUnwrap(UserPresetsCoordinator.fixtureArchive()) }

    /// Every UserDefaults key whose name mentions presets or collections (the preset screens own none today).
    private func presetKeys() -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            let lowered = key.lowercased()
            if lowered.contains("preset") || lowered.contains("collection") { result[key] = String(describing: value) }
        }
        return result
    }

    // MARK: - Preview and Cancel (S1)

    func testPreviewThenCancelLeavesTheLibraryByteForByteUnchanged() async throws {
        let h = try await harness()
        try await importMilk(text("1.01"), named: "Alpha.milk", h)
        let url = try writeArchive(try fixture(), h)
        let before = LibraryTreeSnapshot.take(h.roots)
        let keysBefore = presetKeys()

        await h.coordinator.importPicked(.success(url))
        let review = try XCTUnwrap(h.coordinator.archiveReview)
        XCTAssertNil(review.plan.refusal)
        XCTAssertEqual(review.plan.counts.new, 2)
        XCTAssertEqual(review.plan.missingLicense, ["Fixture Drift"])
        XCTAssertEqual(h.spoken.library.last, "Import preview: 2 new, 0 already in My Presets, 0 conflicts, 0 refused.")
        XCTAssertEqual(LibraryTreeSnapshot.take(h.roots), before, "the dry run writes nothing")

        h.coordinator.cancelArchive()
        XCTAssertNil(h.coordinator.archiveReview)
        let after = LibraryTreeSnapshot.take(h.roots)
        XCTAssertEqual(after, before, after.differences(from: before).joined(separator: ", "))
        XCTAssertEqual(presetKeys(), keysBefore)
        XCTAssertEqual(h.coordinator.playable.map(\.name), ["Alpha"])
    }

    // MARK: - Install (S4)

    func testInstallAddsThePlannedPresetsAnnouncesAndRunsTheirTrials() async throws {
        let h = try await harness()
        await h.coordinator.importPicked(.success(try writeArchive(try fixture(), h)))
        await h.coordinator.installArchive()
        XCTAssertNil(h.coordinator.archiveReview)
        XCTAssertEqual(h.spoken.library.last, "Installed 2 presets. They are checked before they can play.")
        XCTAssertEqual(h.coordinator.playable.map(\.name), ["Fixture Drift", "Fixture Harbor"])
        XCTAssertEqual(Set(h.coordinator.playable.map(\.id)), ["user/file003-fixture-drift", "user/file003-fixture-harbor"])
        XCTAssertTrue(h.spoken.general.isEmpty, "archive words go through the library lane")

        // Picking the same archive again: both identical, nothing to install.
        await h.coordinator.importPicked(.success(try writeArchive(try fixture(), named: "Again.zip", h)))
        let again = try XCTUnwrap(h.coordinator.archiveReview)
        XCTAssertEqual(again.plan.counts.identical, 2)
        XCTAssertFalse(again.plan.canInstall)
        h.coordinator.cancelArchive()
    }

    // MARK: - Conflict policy and re-validation (S5)

    func testPolicySwitchAndAChangedLibraryShowTheNewPlan() async throws {
        let h = try await harness()
        try await importMilk(text("1.05"), named: "Fixture Harbor.milk", h)   // same name, other text
        await h.coordinator.importPicked(.success(try writeArchive(try fixture(), h)))
        let review = try XCTUnwrap(h.coordinator.archiveReview)
        XCTAssertEqual(review.plan.counts.nameConflicts, 1)
        XCTAssertEqual(review.plan.actions.map(\.name), ["Fixture Drift", "Fixture Harbor copy"])

        await h.coordinator.setArchivePolicy(.skip)
        XCTAssertEqual(h.coordinator.archiveReview?.plan.actions.map(\.name), ["Fixture Drift"])
        await h.coordinator.setArchivePolicy(.keepBoth)

        // Meanwhile the clashing preset is removed: Install shows the new plan and writes nothing.
        let existing = try XCTUnwrap(h.coordinator.playable.first)
        await h.coordinator.remove(existing)
        let before = LibraryTreeSnapshot.take(h.roots)
        await h.coordinator.installArchive()
        let changed = try XCTUnwrap(h.coordinator.archiveReview)
        XCTAssertEqual(changed.notice, PresetArchiveText.changed)
        XCTAssertEqual(changed.plan.counts.nameConflicts, 0)
        XCTAssertEqual(h.spoken.library.last, PresetArchiveText.changed)
        XCTAssertEqual(LibraryTreeSnapshot.take(h.roots), before)

        await h.coordinator.installArchive()
        XCTAssertNil(h.coordinator.archiveReview)
        XCTAssertEqual(h.coordinator.playable.map(\.name), ["Fixture Drift", "Fixture Harbor"])
    }

    // MARK: - Refusals and routing

    func testARefusedArchiveIsShownWithItsReasonAndAMilkStillImportsDirectly() async throws {
        let h = try await harness()
        let broken = try writeArchive(Data("PK not really an archive".utf8), named: "Broken.zip", h)
        await h.coordinator.importPicked(.success(broken))
        let review = try XCTUnwrap(h.coordinator.archiveReview)
        XCTAssertNotNil(review.plan.refusal)
        XCTAssertFalse(review.plan.canInstall)
        XCTAssertTrue(h.spoken.library.last?.hasPrefix("Import preview: the archive cannot be imported.") == true)
        h.coordinator.cancelArchive()

        try await importMilk(text("1.07"), named: "Direct.milk", h)
        XCTAssertNil(h.coordinator.archiveReview)
        XCTAssertEqual(h.coordinator.playable.map(\.name), ["Direct"])
    }

    func testWordsOfTheRows() throws {
        let plan = PresetArchiveImportPlanner.plan(archive: try fixture(), library: [], context: .empty)
        let entry = try XCTUnwrap(plan.entries.first)
        XCTAssertEqual(UserPresetsCoordinator.archiveEntryText(entry), "Fixture Drift")
        XCTAssertNil(UserPresetsCoordinator.archiveInstallText(entry))
        XCTAssertEqual(UserPresetsCoordinator.policyTitle(.keepBoth), "Keep both")
        XCTAssertEqual(PresetArchiveReadRefusal.unreadable.message, "The archive could not be read.")
    }
}
