// SceneLockAcceptanceTests.swift — SCN-015-T08 (US1-US3; R1-R5, R9; S1-S4): the roadmap acceptance "Locked scene ignores
// edit gestures but permits cue navigation". Real `AppSettings` over a private defaults suite, the app's own wiring
// for macros (`makeDefault`) and snapshots (`connect`), a real SCN-002 autosave and SCN-010 history on a temporary
// folder, and a real show over a temporary store with the lock wired as AppCoordinator does. Every edit goes through
// the coordinator API the UI calls. No clock, no simulator UI.
import Foundation
import LibraryBackup
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneLockAcceptanceTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    @MainActor
    private final class Harness {
        let folder = SceneAutosaveFixtures.folder()
        let showFolder = FileManager.default.temporaryDirectory.appendingPathComponent("SCN015-show-\(UUID().uuidString)", isDirectory: true)
        let suite = "SCN015-\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: AppSettings
        let autosave: SceneAutosaveCoordinator
        let history = SceneHistoryCoordinator()
        let snapshots = SceneSnapshotCoordinator()
        let macros: MacroCoordinator
        let show: ShowCoordinator
        var applied: [String] = []
        var announced: [String] = []

        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            autosave = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: folder), registry: try F.registry(),
                                                clock: { () -> Double in 0 }, schedulesTimer: false)
            macros = MacroCoordinator.makeDefault(settings: settings)
            show = ShowCoordinator(store: ShowStore(directory: showFolder), registry: try SceneArchiveService.appRegistry())
        }

        var inputs: SceneInputs {
            SceneInputs(visual: settings.visual, bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                        spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                        glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                        text: .default, photoID: nil, videoID: nil, macros: macros.entries)
        }

        /// A committed scene with one snapshot, one macro, one undo step and a three-cue show; the lock wired as the app does.
        func load() throws {
            settings.visual = .circularSpectrum
            try autosave.store.save(SceneAutosaveCapture.document(F.inputs(), carry: F.carry, liveBindings: nil).document.encoded())
            _ = autosave.restore(assets: nil)
            autosave.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            autosave.startTracking(observeLifecycle: false)
            history.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            history.carry = { [unowned self] () -> SceneAutosaveCarry in self.autosave.carrySnapshot }
            history.apply = { [unowned self] (i: SceneInputs) -> Void in
                self.settings.glowIntensity = i.glowIntensity
                self.settings.glowRadius = i.glowRadius
            }
            history.start(observing: false)
            snapshots.connect(settings: settings, autosave: autosave, history: history,
                              announce: { [unowned self] (text: String) -> Void in self.announced.append(text) })
            macros.restore([SceneMacroEntry(UITestMacroFixture.acceptance)])
            show.applyScene = { [unowned self] (document: SceneDocument, _: [SceneIssue]) -> [String] in
                self.applied.append(document.id)
                return []
            }
            show.announce = { (_: String) in }
            // AppCoordinator.connectSceneLock
            show.sceneLock = settings.sceneLock
            history.sceneLock = settings.sceneLock
            settings.sceneLock.announce = { [unowned self] (text: String) -> Void in self.announced.append(text) }

            // A snapshot of 0.2 / 0.05, then an edit to 0.8 (an undo step), and three cues.
            settings.glowIntensity = 0.2
            settings.glowRadius = 0.05
            history.capture()
            history.endCoalescing()
            XCTAssertTrue(snapshots.save())
            settings.glowIntensity = 0.8
            history.capture()
            history.endCoalescing()
            for (index, visual) in [VisualChoice.circularSpectrum, .linearSpectrum, .oscilloscope].enumerated() {
                let look = ShowLook(visual: visual, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false,
                                    glowIntensity: 0.5, glowRadius: 0.02, glowThreshold: 0.5, text: .default, photoID: nil, videoID: nil)
                XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Scene \(index + 1)"),
                                            label: "Cue \(index + 1)"))
            }
            autosave.commitNow()
        }

        /// Every stored byte the lock protects: the autosaved scene, the show folder, and each settings key's value.
        func fingerprint() throws -> [String: Data] {
            var bytes: [String: Data] = [:]
            for (prefix, url) in [("scene/", folder), ("show/", showFolder)] {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                for name in names.sorted() {
                    var isDirectory: ObjCBool = false
                    let file = url.appendingPathComponent(name)
                    guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                    bytes[prefix + name] = try Data(contentsOf: file)
                }
            }
            for key in AppSettings.allKeys where key != SceneLock.key {
                if let value = defaults.object(forKey: key) {
                    bytes["defaults/" + key] = try PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0)
                }
            }
            return bytes
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: showFolder)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// S1, S2 (US1, US2): locked, seven representative edits through the coordinator APIs are refused and nothing stored
    /// changes; Next, Previous and Go to cue still apply scenes; blackout and tap tempo still work.
    func testLockedSceneIgnoresEditsButPermitsCueNavigation() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        XCTAssertTrue(h.history.canUndo, "there is a step to undo")
        h.settings.sceneLock.lock()
        XCTAssertEqual(h.announced.last, "Scene locked")
        XCTAssertFalse(h.history.canUndo, "undo reads as unavailable while locked")
        h.autosave.commitNow()
        let before: [String: Data] = try h.fingerprint()
        let inputs: SceneInputs = h.inputs
        let cues: [ShowCue] = h.show.list.cues

        // 1. A settings write via the inspector target (UIX-003; the shelf uses the same target).
        ParameterInspectorTargets.target(for: VisualParameterIDs.bloomIntensity, settings: h.settings)?.set(.continuous(0.1))
        // 2. A macro move (MOD-010).
        XCTAssertNil(h.macros.setValue(1, at: 0))
        // 3. A snapshot recall (SCN-008).
        XCTAssertEqual(h.snapshots.recall(at: 0).message, SceneLock.refusalMessage)
        // 4. A cue delete, 5. a cue reorder, 6. a transition edit (SHOW-001, SCN-007).
        h.show.remove(cues[0].id)
        h.show.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        let fade = try ShowCueTransition(type: .crossfade, durationSeconds: 1, easing: .linear)
        XCTAssertFalse(h.show.setTransition(cues[1].id, to: fade))
        // 7. Undo (SCN-010).
        h.history.undo()
        // And the rest of the show editor, the folders and tags, snapshot editing.
        XCTAssertFalse(h.show.rename(cues[0].id, to: "Renamed"))
        XCTAssertNil(h.show.duplicateScene(of: cues[0].id))
        XCTAssertNil(h.show.createFolder(named: "Set B", in: nil))
        XCTAssertFalse(h.show.addTag("encore", toScene: cues[0].sceneID))
        XCTAssertFalse(h.snapshots.save())
        h.history.redo()

        XCTAssertEqual(h.settings.sceneLock.refusals, 13, "every attempt reached the choke point")
        XCTAssertEqual(h.show.editorMessage, SceneLock.refusalMessage)
        XCTAssertEqual(h.announced.last, SceneLock.refusalMessage)
        XCTAssertEqual(h.inputs, inputs, "the live scene is unchanged")
        XCTAssertEqual(h.show.list.cues, cues, "the cues, their order and transitions are unchanged")
        h.autosave.commitNow()
        XCTAssertEqual(try h.fingerprint(), before, "scene document, show file and settings are byte-identical")

        // Navigation still works (S2).
        h.applied = []
        h.show.next()
        h.show.next()
        h.show.previous()
        h.show.go(to: cues[2].id)
        XCTAssertEqual(h.applied, [cues[0].sceneID, cues[1].sceneID, cues[0].sceneID, cues[2].sceneID], "every step applied its scene")
        let external = ExternalDisplayCoordinator()
        external.usesDisplayLink = false
        external.toggleBlackout()
        XCTAssertTrue(external.isBlackoutRequested, "blackout works while locked")
        external.toggleBlackout()
        XCTAssertFalse(external.isBlackoutRequested)
        let tempo = TempoCoordinator(clock: TempoCoordinator.syntheticClock(stepMilliseconds: 500),
                                     stateClock: TempoCoordinator.syntheticClock(stepMilliseconds: 250),
                                     announce: { (_: String) -> Void in })
        for _ in 0..<4 { tempo.tap() }
        XCTAssertEqual(tempo.snapshot.bpm, 120, "tap tempo works while locked")
        XCTAssertEqual(h.settings.sceneLock.refusals, 13, "navigation never consults the lock")
    }

    /// S3 (US3): after unlocking, the same edits work again.
    func testUnlockingAllowsEditsAgain() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        h.settings.sceneLock.lock()
        h.settings.sceneLock.unlock()
        XCTAssertEqual(h.announced.last, "Scene unlocked")
        let cues: [ShowCue] = h.show.list.cues

        ParameterInspectorTargets.target(for: VisualParameterIDs.bloomIntensity, settings: h.settings)?.set(.continuous(0.1))
        XCTAssertEqual(h.settings.glowIntensity, 0.1, accuracy: 1e-9)
        XCTAssertNotNil(h.macros.setValue(1, at: 0))
        h.history.capture()
        h.history.endCoalescing()
        XCTAssertTrue(h.history.canUndo)
        h.history.undo()
        XCTAssertNotEqual(h.snapshots.recall(at: 0).message, SceneLock.refusalMessage)
        XCTAssertEqual(h.settings.glowIntensity, 0.2, accuracy: 1e-9, "the snapshot's value")
        h.show.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(h.show.list.cues.map(\.id), [cues[1].id, cues[2].id, cues[0].id])
        let fade = try ShowCueTransition(type: .crossfade, durationSeconds: 1, easing: .linear)
        XCTAssertTrue(h.show.setTransition(cues[1].id, to: fade))
        h.show.remove(cues[0].id)
        XCTAssertEqual(h.show.list.cues.count, 2)
        XCTAssertEqual(h.settings.sceneLock.refusals, 0)
    }

    /// S4 (R1, R9): off by default, persisted across launches (a new `AppSettings` on the same defaults), cleared by the
    /// UI-test reset list, excluded from backups and erased with Settings.
    func testTheLockPersistsAndIsListedWithTheSettingsKeys() throws {
        let suite = "SCN015-persist-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        XCTAssertFalse(AppSettings(defaults: defaults, systemReduceMotion: false).sceneLock.isLocked, "default off")
        AppSettings(defaults: defaults, systemReduceMotion: false).sceneLock.lock()
        XCTAssertTrue(defaults.bool(forKey: "settings.scene.locked"))
        let relaunched = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertTrue(relaunched.sceneLock.isLocked, "still locked after a relaunch")
        relaunched.sceneLock.unlock()
        XCTAssertNil(defaults.object(forKey: SceneLock.key), "unlocked removes the key")
        XCTAssertFalse(AppSettings(defaults: defaults, systemReduceMotion: false).sceneLock.isLocked)

        XCTAssertTrue(AppSettings.allKeys.contains(SceneLock.key), "cleared by -uitestResetNotice")
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(SceneLock.key), "never backed up")
        XCTAssertFalse(LibrarySettingsPolicy.isIncluded(SceneLock.key))
        XCTAssertTrue(LibraryErasePolicy.erasableKeys.contains(SceneLock.key), "erased with Settings")
    }
}
