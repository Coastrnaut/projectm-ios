// SceneSnapshotAcceptanceTests.swift — SCN-008-T10 (US1, US2; SCN-008-R5 to R8, R10; S1, S3, S4): the roadmap
// acceptance "Recall restores mapped values without reloading media assets". The snapshot coordinator is wired
// with the app's own `connect` (real AppSettings, the Settings write targets, a real SCN-002 autosave on a
// temporary folder and a real SCN-010 history) over a restored scene with a photo. The DEBUG media-load spy
// must not move, and the scene's media inputs must be identical. No clock, no simulator UI.
import Foundation
import ParameterGraph
import SceneFormat
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneSnapshotAcceptanceTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    @MainActor
    private final class Harness {
        let folder = SceneAutosaveFixtures.folder()
        let suite = "SCN008-\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: AppSettings
        let photoID = UUID()
        let autosave: SceneAutosaveCoordinator
        let history = SceneHistoryCoordinator()
        let snapshots = SceneSnapshotCoordinator()
        var announced: [String] = []

        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            autosave = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: folder), registry: try F.registry(),
                                                clock: { () -> Double in 0 }, schedulesTimer: false)
        }

        /// The app's `sceneInputs`, with a stored photo (the Photo visual).
        var inputs: SceneInputs {
            SceneInputs(visual: settings.visual, bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                        spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                        glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                        text: .default, photoID: photoID, videoID: nil)
        }

        /// Commits a scene with a photo, restores it as the app does at launch, and wires everything.
        func loadPhotoScene() throws {
            var scene = SceneAutosaveFixtures.inputs(visual: .photo)
            scene.photoID = photoID
            scene.glowEnabled = true
            try autosave.store.save(SceneAutosaveCapture.document(scene, carry: F.carry, liveBindings: nil).document.encoded())
            let values = try XCTUnwrap(autosave.restore(assets: nil))
            settings.visual = .photo
            SceneAutosaveCapture.apply(values, to: settings)
            autosave.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            autosave.startTracking(observeLifecycle: false)
            history.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            history.carry = { [unowned self] () -> SceneAutosaveCarry in self.autosave.carrySnapshot }
            history.apply = { [unowned self] (i: SceneInputs) -> Void in   // AppCoordinator.applySceneInputs' glow subset
                self.settings.glowEnabled = i.glowEnabled
                self.settings.glowIntensity = i.glowIntensity
                self.settings.glowRadius = i.glowRadius
            }
            history.start(observing: false)
            snapshots.connect(settings: settings, autosave: autosave, history: history,
                              announce: { [unowned self] (text: String) -> Void in self.announced.append(text) })
        }

        /// A Settings slider edit, recorded as the observation callback would.
        func edit(intensity: Double, radius: Double) {
            settings.glowIntensity = intensity
            history.capture()
            history.endCoalescing()
            settings.glowRadius = radius
            history.capture()
            history.endCoalescing()
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    @MainActor
    private struct MediaCounts: Equatable {
        let photo: Int, video: Int, logo: Int, host: Int
        init() {
            let spy = MediaLoadSpy.shared
            photo = spy.count(.photo)
            video = spy.count(.video)
            logo = spy.count(.logo)
            host = spy.count(.host)
        }
    }

    /// S1, S4: capture S1 at 0.2 / 0.05 on a photo scene, change both, recall: exact values, no media reload,
    /// identical media inputs, one undo step named "Recall S1".
    func testRecallRestoresMappedValuesWithoutReloadingMedia() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.loadPhotoScene()
        XCTAssertEqual(h.autosave.carrySnapshot.layers.map(\.kind).first, "photo", "the scene has a photo layer")
        h.edit(intensity: 0.2, radius: 0.05)
        XCTAssertTrue(h.snapshots.save())
        XCTAssertNil(h.snapshots.rename(at: 0, to: "S1"))
        XCTAssertEqual(h.snapshots.rows.map(\.name), ["S1"])
        XCTAssertEqual(h.snapshots.rows.first?.summary, "7 values")

        h.edit(intensity: 0.8, radius: 0.03)
        let before: SceneInputs = h.inputs
        let media = MediaCounts()

        let result = h.snapshots.recall(at: 0)
        XCTAssertEqual(h.settings.glowIntensity, 0.2, "exactly")
        XCTAssertEqual(h.settings.glowRadius, 0.05, "exactly")
        XCTAssertEqual(Set(result.written), [VisualParameterIDs.bloomIntensity, VisualParameterIDs.bloomRadius], "only values that differ")
        XCTAssertEqual(result.skipped, [])
        XCTAssertEqual(MediaCounts(), media, "no photo decode, video seek, logo upload or new visual instance")
        var expected: SceneInputs = before
        expected.glowIntensity = 0.2
        expected.glowRadius = 0.05
        XCTAssertEqual(h.inputs, expected, "the visual, photo, video, logo, slideshow, text and layers are unchanged")
        XCTAssertEqual(h.announced.last, "Recalled S1")
        XCTAssertEqual(h.snapshots.status, "Recalled S1")

        // One undo step puts both changed values back.
        XCTAssertEqual(h.history.undoLabel, "Recall S1")
        h.history.undo()
        XCTAssertEqual(h.settings.glowIntensity, 0.8)
        XCTAssertEqual(h.settings.glowRadius, 0.03)
        XCTAssertEqual(h.history.undoLabel, "Glow Radius 3.0%", "the edit before the recall is its own step")
        // Recalling again when nothing differs records no step.
        h.history.redo()
        XCTAssertEqual(h.snapshots.recall(at: 0).message, "S1 is already applied")
        XCTAssertEqual(h.history.undoLabel, "Recall S1")
    }

    /// S2/R10: the current scene's snapshots survive commit and restore, byte-identically.
    func testSnapshotsSurviveCommitAndRestore() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.loadPhotoScene()
        h.edit(intensity: 0.2, radius: 0.05)
        XCTAssertTrue(h.snapshots.save())
        h.autosave.drain()
        XCTAssertFalse(h.autosave.isPending, "Save commits the scene at once")
        let stored = try Data(contentsOf: h.autosave.store.main)
        let reopened = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: h.folder), registry: try F.registry(),
                                                schedulesTimer: false)
        XCTAssertNotNil(reopened.restore(assets: nil))
        XCTAssertEqual(reopened.snapshotEntries, h.autosave.snapshotEntries)
        let document = try SceneDocument.decode([UInt8](stored)).document
        XCTAssertEqual(document.encoded(), [UInt8](stored), "byte-identical round trip")
        XCTAssertEqual(document.usableSnapshots.first??.values[VisualParameterIDs.bloomIntensity], .continuous(0.2))
    }

    /// S3, S4: an unknown parameter is skipped and reported; the 17th snapshot is refused.
    func testUnknownParameterIsSkippedAndTheLimitIsEnforced() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.loadPhotoScene()
        let future = SceneSnapshot(name: "Future", values: [VisualParameterIDs.bloomIntensity: .continuous(0.3),
                                                            "effect.future.size": .continuous(1)])
        h.autosave.replaceSnapshots([SceneSnapshotEntry(future)])
        h.snapshots.reload()
        let result = h.snapshots.recall(at: 0)
        XCTAssertEqual(h.settings.glowIntensity, 0.3)
        XCTAssertEqual(result.skipped, [SceneSnapshotRecallPlan.Skip(id: "effect.future.size", reason: .unknownParameter)])
        XCTAssertEqual(h.announced.last, "Recalled Future; 1 value skipped: effect.future.size")

        for _ in 1..<SceneLimits.maximumSnapshots { XCTAssertTrue(h.snapshots.save()) }
        XCTAssertEqual(h.snapshots.rows.count, 16)
        XCTAssertFalse(h.snapshots.canSave)
        XCTAssertFalse(h.snapshots.save())
        XCTAssertEqual(h.snapshots.status, "A scene holds at most 16 snapshots.")
        XCTAssertEqual(h.autosave.snapshotEntries.count, 16)
        // Delete frees a place; the next default name reuses the smallest free number.
        h.snapshots.delete(at: 3)
        XCTAssertTrue(h.snapshots.save())
        XCTAssertEqual(h.snapshots.rows.last?.name, "Snapshot 3")
    }
}
