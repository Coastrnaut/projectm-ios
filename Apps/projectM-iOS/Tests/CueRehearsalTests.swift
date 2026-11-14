// CueRehearsalTests.swift — SHOW-006-T10, T13 (specs/237-show-006-cue-rehearsal; contract C1-C5, C7): the rehearsal
// target, pictures, render coalescing and the sandbox draft over a real `ShowCoordinator` and temporary store, with a
// fake renderer (no GPU) and no sleeps (the minimum interval is injected as zero).
import CoreGraphics
import FlashSafety
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import UIKit
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

/// Records each render's inputs and returns a 1 × 1 picture.
private final class FakeRehearsalRenderer: CueRehearsalRendering, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(NativeSpectrumStyle, SnapshotRenderValues)] = []
    var calls: [(NativeSpectrumStyle, SnapshotRenderValues)] { lock.withLock { _calls } }

    func render(style: NativeSpectrumStyle, values: SnapshotRenderValues, reduceFlashing: Bool,
                clamp: SafetyClamp) async throws -> CGImage {
        lock.withLock { _calls.append((style, values)) }
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }
}

@MainActor
final class CueRehearsalTests: XCTestCase {
    private var show: ShowCoordinator!
    private var rehearsal: CueRehearsalCoordinator!
    private var renderer: FakeRehearsalRenderer!
    private var applied: [SceneDocument] = []
    private var announced: [String] = []
    private var changedFiles: [Set<String>] = []
    private var stored: [String: UIImage] = [:]
    private var lock: SceneLock!
    private let live = SnapshotRenderValues(barCount: .b32, orientation: .vertical, spacing: 0.2,
                                            glow: BloomParameters(enabled: false, intensity: 0.5, radius: 0.02, threshold: 0.7))

    private static func look(_ visual: VisualChoice, intensity: Double = 0.4) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: true, glowIntensity: intensity,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    /// Cues: 1 Circular, 2 Linear, 3 projectM, 4 Circular.
    override func setUp() async throws {
        let suite = "SHOW006-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { [unowned self] (document: SceneDocument, _: [SceneIssue]) -> [String] in
            self.applied.append(document)
            return []
        }
        show.sceneFilesChanged = { [unowned self] (ids: Set<String>) in self.changedFiles.append(ids) }
        lock = SceneLock(defaults: defaults)
        show.sceneLock = lock
        let visuals: [VisualChoice] = [.circularSpectrum, .linearSpectrum, .projectM, .circularSpectrum]
        for (n, visual) in visuals.enumerated() {
            let document = ShowSceneSnapshot.document(Self.look(visual), id: UUID().uuidString, name: "Scene \(n + 1)")
            XCTAssertTrue(show.addScene(document, label: "Cue \(n + 1)"))
        }
        changedFiles = []
        renderer = FakeRehearsalRenderer()
        let values = live
        rehearsal = CueRehearsalCoordinator(show: show, liveValues: { () -> SnapshotRenderValues in values },
                                            safety: { () -> (reduceFlashing: Bool, clamp: SafetyClamp) in (reduceFlashing: true, clamp: .standard) })
        let fake: FakeRehearsalRenderer = renderer
        rehearsal.makeRenderer = { () -> (any CueRehearsalRendering)? in fake }
        rehearsal.minimumInterval = .zero
        rehearsal.sleep = { (_: Duration) async -> Void in }
        rehearsal.storedPicture = { [unowned self] (id: String) async -> UIImage? in self.stored[id] }
        rehearsal.announce = { [unowned self] (text: String) in self.announced.append(text) }
    }

    private var cues: [ShowCue] { show.list.cues }

    // MARK: - T10: target and pictures (R2, R3)

    func testPreviewsTheNextCueFollowsTheShowAndNeverMovesIt() async throws {
        show.go(to: cues[0].id)
        applied = []
        rehearsal.setOn(true)
        await rehearsal.waitUntilIdle()
        XCTAssertEqual(rehearsal.titleText, "Cue 2 · Cue 2")
        XCTAssertEqual(rehearsal.draft?.visual, .linearSpectrum)
        guard case .rendered = rehearsal.picture else { return XCTFail("a rendered picture: \(rehearsal.picture)") }
        let call = try XCTUnwrap(renderer.calls.last)
        XCTAssertEqual(call.0, .linear(.horizontal, spacing: 0.5), "the cue's own values, not the live ones")
        XCTAssertEqual(call.1.glow.intensity, 0.4, accuracy: 1e-6)
        XCTAssertEqual(show.list.activeIndex, 0, "rehearsal never moves the show")
        XCTAssertTrue(applied.isEmpty, "rehearsal never applies a scene")

        show.next()   // the show moves to cue 2: rehearsal follows to cue 3 (projectM: stored picture)
        rehearsal.sync()
        await rehearsal.waitUntilIdle()
        XCTAssertEqual(rehearsal.cueNumber, 3)
        XCTAssertEqual(rehearsal.picture, .message(CueRehearsalCoordinator.noPicture))
        let image = UIImage()
        stored[cues[2].sceneID] = image
        rehearsal.nextTarget()
        rehearsal.previousTarget()   // picked: cue 3 again, now with a stored picture
        await rehearsal.waitUntilIdle()
        XCTAssertEqual(rehearsal.picture, .stored(image))
        XCTAssertEqual(show.list.activeIndex, 1, "picking never moves the show")
    }

    func testSkippedCuesEndOfShowAndUnreadableScenes() async throws {
        show.go(to: cues[0].id)
        XCTAssertTrue(show.setSkipped(cues[1].id, true))
        rehearsal.setOn(true)
        XCTAssertEqual(rehearsal.cueNumber, 3, "the skipped cue 2 is passed over")
        show.go(to: cues[3].id)
        rehearsal.sync()
        XCTAssertEqual(rehearsal.titleText, CueRehearsalCoordinator.endOfShow)
        XCTAssertEqual(rehearsal.picture, .message(CueRehearsalCoordinator.endOfShow))
        XCTAssertNil(rehearsal.draft)

        let file = try XCTUnwrap(show.sceneFileURL(cues[0].sceneID))
        try Data("not a scene".utf8).write(to: file)
        for _ in 0..<4 { rehearsal.previousTarget() }   // from the end: cue 4, 3, 2, 1
        XCTAssertEqual(rehearsal.cueNumber, 1)
        XCTAssertEqual(rehearsal.picture, .message(CueRehearsalCoordinator.unreadable))
        XCTAssertNil(rehearsal.draft, "no edits for an unreadable scene")
    }

    func testRendersAreCoalescedAndNothingRendersWhileOff() async {
        rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.glow.intensity = 0.9 }
        XCTAssertNil(rehearsal.draft, "nothing while off")
        await rehearsal.waitUntilIdle()
        XCTAssertEqual(renderer.calls.count, 0)
        XCTAssertEqual(rehearsal.renderCount, 0)

        rehearsal.setOn(true)   // Standby: cue 1 (Circular)
        for intensity in [0.6, 0.7, 0.8] as [Float] {
            rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.glow.intensity = intensity }
        }
        await rehearsal.waitUntilIdle()
        XCTAssertEqual(renderer.calls.count, 1, "load and three edits before the first render: one render")
        XCTAssertEqual(renderer.calls.last?.1.glow.intensity, 0.8, "the newest draft wins")
        rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.barCount = .b128 }
        await rehearsal.waitUntilIdle()
        XCTAssertEqual(renderer.calls.count, 2)
        XCTAssertEqual(announced, [CueRehearsalCoordinator.onAnnouncement])
        rehearsal.close()
        XCTAssertEqual(announced.last, CueRehearsalCoordinator.offAnnouncement)
    }

    // MARK: - T13: the sandbox draft and Save to Cue (R5, R6)

    func testSaveWritesTheSceneFileOnlyAndTheCueAppliesItLater() async throws {
        show.go(to: cues[0].id)
        applied = []
        rehearsal.setOn(true)   // cue 2
        rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.glow.intensity = 0.9 }
        XCTAssertTrue(rehearsal.draft?.isEdited == true)
        XCTAssertEqual(rehearsal.draft?.changes, [VisualParameterIDs.bloomIntensity: .continuous(Double(Float(0.9)))])
        XCTAssertTrue(rehearsal.saveDraft())
        XCTAssertEqual(rehearsal.saveMessage, "Saved to cue 2. Shows when the cue runs.")
        XCTAssertEqual(announced.last, "Saved to cue 2. Shows when the cue runs.")
        XCTAssertTrue(applied.isEmpty, "Save to Cue never applies")
        XCTAssertEqual(changedFiles, [[cues[1].sceneID]], "the scene previews learn the file changed")
        XCTAssertEqual(rehearsal.draft?.isEdited, false)
        let stored = try XCTUnwrap(show.rehearsalScene(of: cues[1].id))
        XCTAssertEqual(stored.document.parameters[VisualParameterIDs.bloomIntensity]?.doubleValue ?? 0, 0.9, accuracy: 1e-6)
        XCTAssertEqual(stored.document.parameters[VisualParameterIDs.bloomRadius], .continuous(0.03), "untouched values keep their bytes")
        await rehearsal.waitUntilIdle()

        show.next()   // the cue runs: now it carries the saved value
        let document = try XCTUnwrap(applied.last)
        XCTAssertEqual(document.parameters[VisualParameterIDs.bloomIntensity]?.doubleValue ?? 0, 0.9, accuracy: 1e-6)
    }

    func testRevertCloseAndTheLockDropOrRefuseTheDraft() async throws {
        rehearsal.setOn(true)
        let file = try XCTUnwrap(show.sceneFileURL(cues[0].sceneID))
        let before = try Data(contentsOf: file)
        rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.glow.enabled = false }
        rehearsal.revert()
        XCTAssertEqual(rehearsal.draft?.isEdited, false)

        rehearsal.editDraft { (v: inout SnapshotRenderValues) in v.glow.threshold = 0.9 }
        lock.lock()
        XCTAssertFalse(rehearsal.saveDraft())
        XCTAssertEqual(rehearsal.saveMessage, SceneLock.refusalMessage)
        XCTAssertEqual(try Data(contentsOf: file), before, "a locked scene is not written")
        lock.unlock()

        rehearsal.close()
        XCTAssertNil(rehearsal.draft, "closing drops the draft")
        rehearsal.setOn(true)
        XCTAssertEqual(rehearsal.draft?.isEdited, false, "a new rehearsal starts from the stored values")
        XCTAssertEqual(try Data(contentsOf: file), before)
        await rehearsal.waitUntilIdle()
    }
}
