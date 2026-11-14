// LogoArchiveTests.swift — MED-010-T22: the logo in scenes, scene archives and backups (MED-010-R9 to R11; S3,
// S5, S6). The export acceptance exports a scene archive with the fixture logo from one sandbox and imports it
// into a fresh one; the imported logo's alpha must match the original within 1/255.
import Foundation
import ImageLayer
import LibraryBackup
import LocalPortability
import SceneArchive
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class LogoArchiveTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        var photosFolder: URL { root.appendingPathComponent("Photos") }

        func photos() -> PhotoStore { PhotoStore(directory: photosFolder, defaults: defaults) }
        func logos() -> LogoStore { LogoStore(photos: photos()) }
        func service() throws -> SceneArchiveService {
            SceneArchiveService(photos: photos(), videos: VideoStore(directory: root.appendingPathComponent("Videos"), defaults: defaults),
                                registry: try SceneArchiveService.appRegistry(), temporaryRoot: root.appendingPathComponent("tmp"))
        }

        func payloads() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: photosFolder.path)) ?? [])
                .filter { (name: String) -> Bool in name != ContentAddressedMediaFolder.registryName }.sorted()
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox(_ name: String) throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LogoArchiveTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "LogoArchiveTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    private let placement = LogoPlacement(corner: .topRight, size: 0.12, margin: 0.03, opacity: 0.8)

    /// A source sandbox with the fixture logo, and the scene the app would capture (Text visual + logo).
    private func sourceScene(_ source: Sandbox) throws -> SceneDocument {
        let picked = source.root.appendingPathComponent("picked.png")
        try LogoTestFixture.png().write(to: picked)
        let logo = try source.logos().importLogo(at: picked)
        var inputs = SceneAutosaveFixtures.inputs(visual: .text, message: "Hello")
        inputs.logo = SceneLogo(storeID: logo.id.uuidString, placement: placement)
        return SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
    }

    /// S3 (the export acceptance), plus dedup on a second import and the FILE-003 dry run (analyze E2).
    func testAnExportedLogoKeepsItsAlphaAndPlacementInAFreshSandbox() async throws {
        let source = try makeSandbox("source"), target = try makeSandbox("target")
        defer { source.cleanUp(); target.cleanUp() }
        let scene = try sourceScene(source)
        XCTAssertEqual(scene.logo?.placement, placement, "the capture records the logo")
        let registry = try SceneArchiveService.appRegistry()
        XCTAssertTrue(scene.validate(registry: registry).filter(\.isError).isEmpty)
        let export = try source.service().export(scene, modified: Date(timeIntervalSince1970: 1_794_571_200))
        let received = target.root.appendingPathComponent("received.pmscene")
        try FileManager.default.copyItem(at: export.url, to: received)
        try source.service().cleanUpExport()

        let plan = await (try target.service()).planImport(at: received)
        XCTAssertNil(plan.refusal)
        XCTAssertTrue(plan.media.contains { (m: SceneArchiveImportPlan.Media) -> Bool in m.path == "assets/logo.png" && m.type == .logo },
                      "the dry run lists the logo: \(plan.media)")
        XCTAssertTrue(plan.steps.contains(.madeCurrent(.logo)))
        let result = try await (try target.service()).importArchive(at: received, plan: plan)

        let logo = try XCTUnwrap(result.logo)
        XCTAssertEqual(target.logos().current(), logo, "the imported logo is current")
        XCTAssertEqual(target.logos().placement, placement, "and its placement is restored")
        XCTAssertEqual(result.document.logo, SceneLogo(storeID: logo.id.uuidString, placement: placement))
        XCTAssertEqual(logo.url.pathExtension, "png")
        XCTAssertLessThanOrEqual(try LogoTestFixture.worstAlphaError(of: logo.url), 1, "S3: alpha within 1/255 after export and import")
        XCTAssertFalse(result.repairReport.needsReview, "\(result.repairReport.entries)")

        _ = try await (try target.service()).importArchive(at: received)
        XCTAssertEqual(target.payloads().count, 1, "S5: importing it again adds no second copy")
    }

    /// MED-010-R10: restoring a scene with a logo applies it when the picture is on the device; a missing
    /// picture leaves the current logo and is reported.
    func testRestoringASceneAppliesItsLogoOnlyWhenThePictureIsStored() throws {
        let source = try makeSandbox("restore")
        defer { source.cleanUp() }
        let scene = try sourceScene(source)
        let registry = try SceneArchiveService.appRegistry()
        let live = try scene.liveState(registry: registry).state
        let values = SceneAutosaveCapture.restoredValues(scene, live: live, registry: registry)
        XCTAssertEqual(values.logo?.placement, placement)
        let coordinator = LogoCoordinator(store: source.logos())
        coordinator.setPlacement(.default)
        XCTAssertTrue(coordinator.restore(storeID: try XCTUnwrap(values.logo?.storeID), placement: placement))
        XCTAssertEqual(coordinator.placement, placement)
        XCTAssertFalse(coordinator.restore(storeID: "0000B000-0000-4000-8000-0000000000FF", placement: .default), "missing: unchanged")
        XCTAssertEqual(coordinator.placement, placement)
        let missing = scene.validate(registry: registry, assets: StoredMediaAvailability(photos: [], videos: []))
        XCTAssertTrue(missing.contains { (i: SceneIssue) -> Bool in i.code == .missingAsset && i.path.contains("logo") })
    }

    /// S6: the logo keys are the stores' keys, included in backups and erased with "Photos and videos".
    func testBackupIncludesAndEraseRemovesTheLogoKeys() {
        XCTAssertEqual(LibrarySettingsPolicy.logoKey, LogoStore.idKey)
        XCTAssertEqual(LibrarySettingsPolicy.logoPlacementKey, LogoStore.placementKey)
        for key in [LogoStore.idKey, LogoStore.placementKey] {
            XCTAssertTrue(LibrarySettingsPolicy.isIncluded(key), key)
            XCTAssertTrue(LibraryErasePolicy.settingKeys(.media).contains(key), key)
            XCTAssertTrue(AppSettings.allKeys.contains(key), "reset by UI tests: \(key)")
        }
    }
}
