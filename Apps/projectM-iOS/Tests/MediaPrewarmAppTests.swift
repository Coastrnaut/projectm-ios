// MediaPrewarmAppTests.swift — PERF-005-T13 (US1; R11, R12; S5): stepping a show A (spectrum) → B (photo) prewarms
// B's photo in the background with exactly one decode, and applying B adopts that decoded picture: the photo layer
// is ready at once and starts no load of its own. The show, the scheduler, the photo loader and the photo layer are
// the app's real types (default executor, zero settle delay so the test does not wait); the scene apply is the
// photo subset of the app's. No wall-clock assertion: waits poll with a timeout only.
import Foundation
import ImageLayer
import Metal
import PresentationLifecycle
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
final class MediaPrewarmAppTests: XCTestCase {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MediaPrewarmAppTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice, photoID: UUID? = nil) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: photoID, videoID: nil)
    }

    private func writePhoto(in folder: URL) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48), format: format).pngData { (context: UIGraphicsImageRendererContext) in
            UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        let url = folder.appendingPathComponent("photo.png")
        try data.write(to: url)
        return url
    }

    private func waitUntil(_ condition: () -> Bool, _ message: String) {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), message)
    }

    func testSteppingCuesPrewarmsTheNextPhotoOnceAndApplyingReusesIt() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let root = folder()
        let photoURL = try writePhoto(in: root)
        let show = ShowCoordinator(store: ShowStore(directory: root.appendingPathComponent("show")), registry: try SceneArchiveService.appRegistry())
        show.announce = { (_: String) in }
        let a = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "A")
        let b = ShowSceneSnapshot.document(look(.photo, photoID: UUID()), id: UUID().uuidString, name: "B")
        let c = ShowSceneSnapshot.document(look(.linearSpectrum), id: UUID().uuidString, name: "C")
        for document in [a, b, c] { XCTAssertTrue(show.addScene(document, label: document.name)) }

        let loader = PhotoPrewarmLoader(device: device)
        let scheduler = PrewarmScheduler(budgetBytes: PrewarmBudget.current, loader: loader, settleDelay: .zero)
        let prewarm = MediaPrewarmCoordinator(scheduler: scheduler, loader: loader)
        let layer = ImageLayerSource(device: device)   // the Photo visual's layer
        prewarm.attach(layer)
        let registry = try SceneArchiveService.appRegistry()
        let photoOf: (SceneDocument) -> URL? = { (document: SceneDocument) -> URL? in
            ShowSceneSnapshot.apply(of: document, warnings: [], registry: registry).visual.usesPhoto ? photoURL : nil
        }
        var stateAtApply: ImageLayerState?
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            let isPhoto = photoOf(document) != nil
            layer.content = isPhoto ? .file(photoURL) : .none
            if isPhoto { stateAtApply = layer.state }
            prewarm.replan(show: show, photoURL: photoOf, liveURL: isPhoto ? photoURL : nil)
            return []
        }

        // Cue A (spectrum): the next cue B is a photo scene, prewarmed in the background.
        show.next()
        XCTAssertEqual(scheduler.plannedKeys, [PrewarmKey.photo(photoURL)], "rank 0: the next cue's photo")
        waitUntil({ scheduler.isCached(.photo(photoURL)) }, "B's photo is prewarmed while A plays")
        XCTAssertEqual(loader.decodes, 1)
        XCTAssertGreaterThan(scheduler.heldBytes, 64 * 48 * 4, "the texture and its mips are accounted")

        // Cue B: the photo layer adopts the decoded picture; no second decode.
        show.next()
        XCTAssertEqual(stateAtApply, .ready(width: 64, height: 48), "ready on the apply itself")
        XCTAssertEqual(layer.loadsStarted, 0, "the layer started no load of its own")
        XCTAssertEqual(layer.prewarmedAdoptions, 1)
        XCTAssertEqual(scheduler.stats.taken, 1)
        XCTAssertEqual(scheduler.heldBytes, 0, "a taken picture leaves the prewarm accounting")

        // Cue C (spectrum) next: nothing to decode; the live photo is never loaded again.
        waitUntil({ scheduler.inFlightKey == nil }, "idle")
        XCTAssertEqual(loader.decodes, 1, "one decode in total")
        scheduler.shutdown()
    }
}
