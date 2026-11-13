// SceneRepairCoordinatorTests.swift — SCN-012-T09, T11 in the app: a show step to a cue whose scene
// needs review requests the repair report and applies nothing; Open with repairs applies the repaired
// scene and leaves the stored file byte-identical; Open as is is refused when the scene has errors;
// Cancel applies nothing; a newer-version scene requests "Cannot open" (Close only); a newer request
// cancels the pending one; clean cues apply with no report (SHOW-001 unchanged); Reopen's decision
// (PERF-010) and its repaired held scene. Each store is a fresh temporary folder; no clock.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneRepairCoordinatorTests: XCTestCase {
    private static let missingPhotoID = "0DDBA11E-0000-4000-8000-0000000000AA"

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneRepairCoordinatorTests-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    /// A circular scene plus a photo no store holds and a mapping to a parameter this version lacks.
    private func broken() -> SceneDocument {
        var document = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "Broken")
        document.layers.insert(SceneLayer(instance: 2, content: .photo(asset: ShowSceneSnapshot.photoKey)), at: 0)
        document.assets[ShowSceneSnapshot.photoKey] = .photo(storeID: Self.missingPhotoID)
        document.bindings = [SceneBinding(sourceID: "audio.onset", target: "visual.future.thing",
                                          mapping: LinearMapping(outputStart: 0, outputEnd: 1))]
        return document
    }

    private struct World {
        let show: ShowCoordinator
        let repair: SceneRepairCoordinator
        let url: URL
        var applied: () -> [SceneDocument]
    }

    private func world() throws -> World {
        let url = folder()
        let registry = try SceneArchiveService.appRegistry()
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: registry)
        let repair = SceneRepairCoordinator(registry: registry)
        repair.announce = { (_: String) in }
        show.announce = { (_: String) in }
        var applied: [SceneDocument] = []
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            applied.append(document)
            return []
        }
        show.requestRepair = { (request: SceneRepairRequest) in repair.present(request) }
        return World(show: show, repair: repair, url: url, applied: { applied })
    }

    func testABrokenCueShowsTheReportAndOpensRepairedWithoutWritingTheFile() throws {
        let w = try world()
        let good = ShowSceneSnapshot.document(look(.linearSpectrum), id: UUID().uuidString, name: "Good")
        let bad = broken()
        XCTAssertTrue(w.show.addScene(good, label: "Good"))
        XCTAssertTrue(w.show.addScene(bad, label: "Broken"))
        let file = ShowStore(directory: w.url).sceneFile(bad.id)
        let stored = try Data(contentsOf: file)

        w.show.next()
        XCTAssertEqual(w.applied().map(\.id), [good.id], "a clean cue applies without a report")
        XCTAssertNil(w.repair.pending)
        XCTAssertEqual(w.show.next().outcome, .moved, "the position still moves")
        let request = try XCTUnwrap(w.repair.pending)
        XCTAssertEqual(request.title, "Cue 2 · Broken")
        XCTAssertEqual(request.report.groups, [.missingMedia, .invalidMappings])
        XCTAssertTrue(request.canOpenAsIs)
        XCTAssertTrue(request.canOpenWithRepairs)
        XCTAssertEqual(request.cancelTitle, "Cancel")
        XCTAssertEqual(w.applied().map(\.id), [good.id], "nothing is applied before the user chooses")
        XCTAssertNil(w.show.notice)

        XCTAssertTrue(w.repair.openWithRepairs())
        XCTAssertNil(w.repair.pending)
        let opened = try XCTUnwrap(w.applied().last)
        XCTAssertEqual(opened.id, bad.id)
        XCTAssertEqual(opened.layers.map(\.kind), ["spectrum.circular"], "the photo layer is dropped")
        XCTAssertEqual(opened.bindings, [], "the dead mapping is dropped")
        XCTAssertEqual(w.show.appliedSceneID, bad.id)
        XCTAssertEqual(try Data(contentsOf: file), stored, "the stored scene is not written")
    }

    func testOpenAsIsAppliesTheStoredScene() throws {
        let w = try world()
        let bad = broken()
        XCTAssertTrue(w.show.addScene(bad, label: "Broken"))
        w.show.next()
        XCTAssertTrue(w.repair.openAsIs())
        XCTAssertEqual(w.applied(), [bad], "as stored")
    }

    func testAnErrorRefusesOpenAsIsAndCancelAppliesNothing() throws {
        let w = try world()
        let invalid = SceneDocument(id: UUID().uuidString, name: "Invalid",
                                    layers: [SceneLayer(instance: 1, content: .photo(asset: "nope")),
                                             SceneLayer(instance: 2, content: .linearSpectrum)])
        XCTAssertTrue(w.show.addScene(invalid, label: "Invalid"))
        w.show.next()
        let request = try XCTUnwrap(w.repair.pending)
        XCTAssertFalse(request.canOpenAsIs)
        XCTAssertTrue(w.show.isSceneMissing(w.show.list.cues[0]), "flagged until it opens")
        XCTAssertFalse(w.repair.openAsIs(), "a scene with errors does not open as is")
        w.repair.cancel()
        XCTAssertNil(w.repair.pending)
        XCTAssertEqual(w.applied(), [], "cancel applies nothing")
    }

    func testANewerVersionCueCannotOpen() throws {
        let w = try world()
        let document = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "Future")
        XCTAssertTrue(w.show.addScene(document, label: "Future"))
        let text = String(decoding: document.encoded(), as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        try Data(text.utf8).write(to: ShowStore(directory: w.url).sceneFile(document.id))
        w.show.next()
        let request = try XCTUnwrap(w.repair.pending)
        XCTAssertNil(request.document)
        XCTAssertTrue(request.report.cannotOpen)
        XCTAssertEqual(request.report.groups, [.unsupportedVersion])
        XCTAssertEqual(request.cancelTitle, "Close")
        XCTAssertFalse(w.repair.openWithRepairs())
        XCTAssertFalse(w.repair.openAsIs())
        w.repair.cancel()
        XCTAssertEqual(w.applied(), [])
    }

    func testANewerRequestCancelsThePendingOne() throws {
        let repair = SceneRepairCoordinator(registry: try SceneArchiveService.appRegistry())
        repair.announce = { (_: String) in }
        var cancelled: [String] = []
        let report = SceneRepairReport(refusal: .empty)
        repair.present(SceneRepairRequest(title: "A", report: report, document: nil, cancel: { cancelled.append("A") }))
        repair.present(SceneRepairRequest(title: "B", report: report, document: nil, cancel: { cancelled.append("B") }))
        XCTAssertEqual(cancelled, ["A"])
        XCTAssertEqual(repair.pending?.title, "B")
        repair.cancel()
        XCTAssertEqual(cancelled, ["A", "B"])
        XCTAssertNil(repair.pending)
    }

    // MARK: Reopen (PERF-010, SCN-012-R10)

    func testReopenShowsTheReportOnlyWhenTheHeldSceneNeedsReview() throws {
        let registry = try SceneArchiveService.appRegistry()
        let clean = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "Clean")
        let held = SceneAutosaveHeldScene(document: clean, live: try clean.liveState(registry: registry).state, source: .main)
        let none = StoredMediaAvailability(photos: [], videos: [])
        XCTAssertNil(AppCoordinator.reopenReport(for: held, registry: registry, assets: none))

        let bad = broken()
        let heldBad = SceneAutosaveHeldScene(document: bad, live: try bad.liveState(registry: registry, assets: none).state, source: .backup)
        let report = try XCTUnwrap(AppCoordinator.reopenReport(for: heldBad, registry: registry, assets: none))
        XCTAssertEqual(report.groups, [.missingMedia, .invalidMappings])
        let repaired = bad.repairing(with: report, registry: registry, assets: none)
        let replacement = AppCoordinator.held(repaired, replacing: heldBad, registry: registry)
        XCTAssertEqual(replacement.document, repaired)
        XCTAssertEqual(replacement.source, .backup)
        XCTAssertEqual(replacement.live.bindings.count, 0)
    }
}
