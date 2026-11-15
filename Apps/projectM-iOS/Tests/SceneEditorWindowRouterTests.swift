// SceneEditorWindowRouterTests.swift — UIX-008-T11 (UIX-008-S3, S4; contract W2, W5): opening a scene that already
// has an editor window brings that window forward and never creates a second editor; a closed window frees its
// scene; one main window performs and the next takes over; creating routers and editors and saving creates no
// AppCoordinator (so no CaptureManager) and no renderer (EngineInstanceLedger).
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneEditorWindowRouterTests: XCTestCase {
    private func library() -> (show: ShowCoordinator, ids: [String]) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneEditorWindowRouterTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try? SceneArchiveService.appRegistry())
        show.announce = { (_: String) in }
        var ids: [String] = []
        for name in ["One", "Two"] {
            let look = ShowLook(visual: .circularSpectrum, bars: 32, orientation: .horizontal, spacing: 0.5, glowEnabled: false,
                                glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                                photoID: nil, videoID: nil)
            let document = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: name)
            XCTAssertTrue(show.addScene(document, label: name))
            ids.append(document.id)
        }
        return (show, ids)
    }

    func testOpeningTheSameSceneTwiceFocusesTheExistingWindow() {
        let (show, ids) = library()
        let router = SceneEditorWindowRouter(library: show)
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(router.request(ids[0]), .openNew)
        let editor = router.editor(for: ids[0], window: first)
        XCTAssertNotNil(editor)
        XCTAssertEqual(router.request(ids[0]), .focusExisting, "the open window comes forward")
        XCTAssertNil(router.editor(for: ids[0], window: second), "no second editor for the same scene")
        XCTAssertTrue(router.editor(for: ids[0], window: first) === editor, "the owner keeps its editor")
        XCTAssertEqual(router.request(ids[1]), .openNew, "another scene opens its own window")
        let other = router.editor(for: ids[1], window: second)
        XCTAssertNotNil(other)
        XCTAssertFalse(other === editor)
        XCTAssertEqual(router.openSceneIDs, Set(ids))

        router.release(window: first)
        XCTAssertEqual(router.request(ids[0]), .openNew, "a closed window frees its scene")
        XCTAssertEqual(router.openSceneIDs, [ids[1]])
    }

    func testOneMainWindowPerformsAndTheNextTakesOver() {
        let claim = PerformanceWindowClaim()
        let main = UUID()
        let extra = UUID()
        XCTAssertTrue(claim.claim(main))
        XCTAssertFalse(claim.claim(extra), "a second main window shows the notice")
        XCTAssertTrue(claim.isPerformer(main))
        claim.release(extra)
        XCTAssertTrue(claim.isPerformer(main), "a non-performer leaving changes nothing")
        claim.release(main)
        XCTAssertTrue(claim.claim(extra), "the next window takes over")
    }

    func testEditorWindowsCreateNoEngineOrCapture() throws {
        let coordinators: Int = EngineInstanceLedger.coordinators
        let renderers: Int = EngineInstanceLedger.renderers
        let (show, ids) = library()
        let router = SceneEditorWindowRouter(library: show)
        let a = try XCTUnwrap(router.editor(for: ids[0], window: UUID()))
        let b = try XCTUnwrap(router.editor(for: ids[1], window: UUID()))
        a.rename("One edited")
        b.rename("Two edited")
        guard case .saved = a.save(), case .saved = b.save() else { return XCTFail("both saved") }
        XCTAssertEqual(EngineInstanceLedger.coordinators, coordinators, "no AppCoordinator, so no CaptureManager")
        XCTAssertEqual(EngineInstanceLedger.renderers, renderers, "no renderer")
    }
}
