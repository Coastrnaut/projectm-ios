// PRE-014-T16: exporting user presets through the app's coordinator (specs/012-pre-014-bulk-preset-export;
// PRE-014-R1-R6, R18; S5). A real UserPresetLibrary in a temporary folder, a passing trial, an
// injected export folder, clock and app version. The preset text is written here.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class UserPresetExportAppTests: XCTestCase {
    private var base: URL!
    private var exportDirectory: URL!
    private var announcements: [String] = []
    private let exportDate = Date(timeIntervalSince1970: 1_800_000_000)

    struct PassingTrial: PresetTrialRunning {
        func run(_ contents: Data, timeout: Duration) async -> PresetTrialResult { .passed }
    }

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("UserPresetExportAppTests-\(UUID().uuidString)", isDirectory: true)
        exportDirectory = base.appendingPathComponent("PresetExport", isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("picked"), withIntermediateDirectories: true)
        announcements = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func coordinator() async -> (UserPresetsCoordinator, UserPresetLibrary) {
        let library = UserPresetLibrary(directory: base.appendingPathComponent("UserPresets"))
        let coordinator = UserPresetsCoordinator(library: library, announce: { [weak self] in self?.announcements.append($0) },
                                                 exportDirectory: exportDirectory, now: { [exportDate] in exportDate }, appVersion: "9.9 (9)")
        await coordinator.load()
        await coordinator.rendererReady(trial: PassingTrial(), presentedFrames: { 0 })
        return (coordinator, library)
    }

    private func text(_ zoom: String) -> String {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=\(zoom)", "per_frame_1=rot = 0.02*sin(time);", ""]
            .joined(separator: "\n")
    }

    private func importText(_ contents: String, named name: String, into coordinator: UserPresetsCoordinator) async throws {
        let url = base.appendingPathComponent("picked").appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        await coordinator.importPicked(.success(url))
    }

    private func filesUnderExportDirectory() -> [String] {
        (FileManager.default.enumerator(atPath: exportDirectory.path)?.allObjects as? [String]) ?? []
    }

    func testPrepareListsTheExportablePresetsAndWhatIsLeftOut() async throws {
        let (coordinator, _) = try await coordinatorWithPresets()
        await coordinator.prepareExport()
        XCTAssertEqual(coordinator.exportPlan.exportable.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(coordinator.exportPlan.excluded, [.quarantined: 1])
        XCTAssertEqual(coordinator.exportExclusionText, "Not exported: 1 file in Quarantine (it failed a check).")
        XCTAssertTrue(coordinator.canExport)
    }

    private func coordinatorWithPresets() async throws -> (UserPresetsCoordinator, UserPresetLibrary) {
        let (coordinator, library) = await coordinator()
        try await importText(text("1.01"), named: "Alpha.milk", into: coordinator)
        try await importText(text("1.02"), named: "Beta.milk", into: coordinator)
        try await importText("not a preset\n", named: "Broken.milk", into: coordinator)
        XCTAssertEqual(coordinator.playable.count, 2)
        XCTAssertEqual(coordinator.quarantined.count, 1)
        return (coordinator, library)
    }

    func testExportWritesAReadableArchiveOfTheSelectionAndAnnouncesTheSummary() async throws {
        let (coordinator, library) = try await coordinatorWithPresets()
        await coordinator.prepareExport()
        let alpha = try XCTUnwrap(coordinator.exportPlan.exportable.first { $0.name == "Alpha" })
        let urlResult = await coordinator.export(ids: [alpha.id])
        let url = try XCTUnwrap(urlResult)

        XCTAssertEqual(coordinator.exportFile, url)
        XCTAssertTrue(url.path.hasPrefix(exportDirectory.path), "written only in the private export folder")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("projectM-iOS Presets "))
        XCTAssertEqual(url.pathExtension, "zip")
        XCTAssertNotNil(url.lastPathComponent.range(of: #"^projectM-iOS Presets \d{4}-\d{2}-\d{2}\.zip$"#, options: .regularExpression))

        let archive = try UserPresetArchiveReader.read(try Data(contentsOf: url))
        XCTAssertEqual(archive.manifest.presets.map(\.id), [alpha.id])
        XCTAssertEqual(archive.manifest.appVersion, "9.9 (9)")
        XCTAssertEqual(archive.manifest.exportedAt, exportDate)
        let stored = await library.data(for: alpha.id)
        XCTAssertEqual(archive.texts[alpha.id], stored)

        let summary = "Exported 1 preset. Not exported: 1 file in Quarantine (it failed a check)."
        XCTAssertEqual(coordinator.exportSummary, summary)
        XCTAssertEqual(announcements.last, summary)
        XCTAssertNil(coordinator.exportError)
        XCTAssertFalse(coordinator.isExporting)
    }

    func testClosingTheShareSheetDeletesTheArchive() async throws {
        let (coordinator, _) = try await coordinatorWithPresets()
        await coordinator.prepareExport()
        let urlResult = await coordinator.export(ids: coordinator.exportPlan.exportable.map(\.id))
        let url = try XCTUnwrap(urlResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        coordinator.finishSharing()
        XCTAssertNil(coordinator.exportFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(filesUnderExportDirectory(), [], "S5: no temporary archive remains")
    }

    func testASecondExportReplacesTheFirstFile() async throws {
        let (coordinator, _) = try await coordinatorWithPresets()
        await coordinator.prepareExport()
        let ids = coordinator.exportPlan.exportable.map(\.id)
        let firstResult = await coordinator.export(ids: ids)
        let first = try XCTUnwrap(firstResult)
        let secondResult = await coordinator.export(ids: ids)
        let second = try XCTUnwrap(secondResult)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(filesUnderExportDirectory().filter { $0.hasSuffix(".zip") }.count, 1)
    }

    func testLeftoversFromAnEarlierLaunchAreDeletedAtLoad() async throws {
        let leftover = exportDirectory.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: leftover.appendingPathComponent("projectM-iOS Presets 2026-01-01.zip"))
        _ = await coordinator()
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportDirectory.path))
    }

    func testAFailedExportSharesNothing() async throws {
        let (coordinator, _) = try await coordinatorWithPresets()
        await coordinator.prepareExport()
        let alpha = try XCTUnwrap(coordinator.exportPlan.exportable.first { $0.name == "Alpha" })
        try Data("tampered".utf8).write(to: base.appendingPathComponent("UserPresets/files/\(alpha.sha256).milk"))
        let url = await coordinator.export(ids: [alpha.id])
        XCTAssertNil(url)
        XCTAssertNil(coordinator.exportFile)
        XCTAssertEqual(coordinator.exportError, "The presets could not be exported. Nothing was shared.")
        XCTAssertEqual(announcements.last, coordinator.exportError)
        XCTAssertEqual(filesUnderExportDirectory().filter { $0.hasSuffix(".zip") }, [])
    }

    func testExportIsUnavailableForARecordFromANewerVersion() async throws {
        let folder = base.appendingPathComponent("UserPresets")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 99, "presets": []}"#.utf8).write(to: folder.appendingPathComponent("index.json"))
        let (coordinator, _) = await coordinator()
        XCTAssertFalse(coordinator.canExport)
        await coordinator.prepareExport()
        XCTAssertEqual(coordinator.exportPlan, .empty)
        let url = await coordinator.export(ids: ["user/x"])
        XCTAssertNil(url)
    }

    func testWords() {
        XCTAssertEqual(UserPresetsCoordinator.exportRowLabel(name: "Alpha", selected: true), "Alpha, selected")
        XCTAssertEqual(UserPresetsCoordinator.exportRowLabel(name: "Alpha", selected: false), "Alpha, not selected")
        XCTAssertEqual(UserPresetsCoordinator.exportCountText(selected: 1, of: 3), "1 of 3 presets selected")
        XCTAssertEqual(UserPresetsCoordinator.exportCountText(selected: 2, of: 2), "2 of 2 presets selected")
        XCTAssertEqual(UserPresetsCoordinator.exportFileName(for: exportDate, timeZone: TimeZone(identifier: "UTC")!),
                       "projectM-iOS Presets 2027-01-15.zip")
    }
}
