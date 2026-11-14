// SceneCompareAcceptanceTests.swift — SCN-009-T09 (US1-US3; SCN-009-R2 to R6, R9, R11; S1 to S5): the roadmap
// acceptance "Switch never mutates saved document until user commits". The compare model is wired with the app's own
// `connect` over real AppSettings, the Settings write targets, a real SCN-002 autosave on a temporary folder, a real
// SCN-010 history and SCN-008 snapshots. Every commit trigger is fired while comparing; a write counter on the store
// (its fault hook at `writeTemporary`) and the files' bytes prove nothing is written. No clock, no simulator UI.
import Foundation
import ParameterGraph
import SceneFormat
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneCompareAcceptanceTests: XCTestCase {
    private typealias F = SceneAutosaveFixtures

    /// Counts scene writes (one `writeTemporary` per save) from the autosave's queue.
    private final class WriteCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func hit() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @MainActor
    private final class Harness {
        let folder = SceneAutosaveFixtures.folder()
        let suite = "SCN009-\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: AppSettings
        let autosave: SceneAutosaveCoordinator
        let history = SceneHistoryCoordinator()
        let snapshots = SceneSnapshotCoordinator()
        let compare = SceneCompareCoordinator()
        let writes = WriteCounter()
        var announced: [String] = []

        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            autosave = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: folder), registry: try F.registry(),
                                                clock: { () -> Double in 0 }, schedulesTimer: false)
        }

        var inputs: SceneInputs {
            SceneInputs(visual: settings.visual, bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                        spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                        glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                        text: .default, photoID: nil, videoID: nil)
        }

        /// Commits a scene, restores it as at launch, wires everything, then saves S1 (intensity 0.2) and S2 (0.8)
        /// and leaves a pending edit at 0.5.
        func load() throws {
            let writes = writes
            try autosave.store.save(SceneAutosaveCapture.document(F.inputs(), carry: F.carry, liveBindings: nil).document.encoded())
            autosave.store.fault = { (step: SceneAutosaveStep) throws -> Void in if step == .writeTemporary { writes.hit() } }
            let values = try XCTUnwrap(autosave.restore(assets: nil))
            settings.visual = .circularSpectrum
            SceneAutosaveCapture.apply(values, to: settings)
            autosave.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            autosave.startTracking(observeLifecycle: false)
            history.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            history.carry = { [unowned self] () -> SceneAutosaveCarry in self.autosave.carrySnapshot }
            history.apply = { [unowned self] (i: SceneInputs) -> Void in   // AppCoordinator.applySceneInputs' settings subset
                self.settings.circularSpectrumBars = i.bars
                self.settings.linearSpectrumOrientation = i.orientation
                self.settings.linearSpectrumSpacing = i.spacing
                self.settings.glowEnabled = i.glowEnabled
                self.settings.glowIntensity = i.glowIntensity
                self.settings.glowRadius = i.glowRadius
                self.settings.glowThreshold = i.glowThreshold
            }
            history.start(observing: false)
            let announce: (String) -> Void = { [unowned self] (text: String) -> Void in self.announced.append(text) }
            snapshots.connect(settings: settings, autosave: autosave, history: history, announce: announce)
            compare.connect(snapshots: snapshots, autosave: autosave, history: history, lock: settings.sceneLock,
                            inputs: { [unowned self] () -> SceneInputs? in self.inputs }, announce: announce)
            edit(0.2)
            XCTAssertTrue(snapshots.save())
            XCTAssertNil(snapshots.rename(at: 0, to: "S1"))
            edit(0.8)
            XCTAssertTrue(snapshots.save())
            XCTAssertNil(snapshots.rename(at: 1, to: "S2"))
            edit(0.5)
            autosave.drain()
        }

        /// A Settings slider edit, observed as the callbacks would.
        func edit(_ intensity: Double) {
            settings.glowIntensity = intensity
            history.capture()
            history.endCoalescing()
            autosave.inputsChanged()
        }

        /// Every SCN-002 trigger and SCN-010 capture the app can fire while comparing.
        func fireEveryTrigger() {
            autosave.inputsChanged()
            history.capture()
            autosave.tick()
            autosave.commitNow()           // Settings closing
            history.endCoalescing()        // Settings closing
            autosave.flushSynchronously()  // terminate
            autosave.drain()
        }

        func bytes(_ url: URL) -> Data? { try? Data(contentsOf: url) }

        var historyFingerprint: [String] {
            let h = history.history
            let undo: [String] = (h?.undoSteps ?? []).map { (s: SceneHistoryStep<SceneInputs>) -> String in s.label }
            let redo: [String] = (h?.redoSteps ?? []).map { (s: SceneHistoryStep<SceneInputs>) -> String in s.label }
            return undo + ["|"] + redo + ["|", String(h?.current.bytes.hashValue ?? 0)]
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// S1, S4, S5, R4, R5, R9: 20 switches with every trigger fired leave the scene file, its backup, the snapshot
    /// list and the undo history unchanged; a relaunch during Compare restores the pre-Compare scene; Cancel restores.
    func testTwentySwitchesLeaveEveryStoreUnchangedAndCancelRestores() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        XCTAssertTrue(h.autosave.isPending, "the 0.5 edit is pending before Compare")
        XCTAssertNil(h.compare.start(a: .snapshot(0), b: 1))
        XCTAssertFalse(h.autosave.isPending, "start committed the pending edit first (R2)")
        XCTAssertEqual(h.settings.glowIntensity, 0.2, "A (S1) is shown")
        XCTAssertEqual(h.announced.last, "Comparing A/B: A, S1")
        let baseline: SceneInputs = try XCTUnwrap(h.compare.session?.baseline)
        XCTAssertEqual(baseline.glowIntensity, 0.5)

        let main = h.bytes(h.autosave.store.main), backup = h.bytes(h.autosave.store.backup)
        XCTAssertNotNil(main)
        let entries = h.autosave.snapshotEntries, history = h.historyFingerprint, writes = h.writes.value
        for i in 1...20 {
            h.compare.toggle()
            XCTAssertEqual(h.settings.glowIntensity, i % 2 == 1 ? 0.8 : 0.2, "switch \(i) is live at once (S5)")
            h.fireEveryTrigger()
        }
        XCTAssertEqual(h.announced.last, "A, S1")
        XCTAssertEqual(h.writes.value, writes, "no scene write while comparing")
        XCTAssertEqual(h.bytes(h.autosave.store.main), main, "scene file byte-identical")
        XCTAssertEqual(h.bytes(h.autosave.store.backup), backup, "backup byte-identical")
        XCTAssertEqual(h.autosave.snapshotEntries, entries)
        XCTAssertEqual(h.historyFingerprint, history, "undo stack unchanged")

        // R4: undo, redo and snapshot edits are refused while comparing.
        h.compare.show(.b)
        h.history.undo()
        XCTAssertEqual(h.settings.glowIntensity, 0.8, "undo did nothing")
        XCTAssertFalse(h.history.canUndo)
        XCTAssertFalse(h.snapshots.save())
        XCTAssertEqual(h.snapshots.recall(at: 0).message, SceneSnapshotCoordinator.compareRefusal)
        XCTAssertEqual(h.settings.glowIntensity, 0.8)

        // R9: the app killed now; a relaunch restores the pre-Compare scene.
        let relaunched = SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: h.folder), registry: try F.registry(),
                                                  schedulesTimer: false)
        let suite2 = h.suite + "-relaunch"
        defer { UserDefaults().removePersistentDomain(forName: suite2) }
        let settings2 = AppSettings(defaults: UserDefaults(suiteName: suite2)!, systemReduceMotion: false)
        SceneAutosaveCapture.apply(try XCTUnwrap(relaunched.restore(assets: nil)), to: settings2)
        XCTAssertEqual(settings2.glowIntensity, 0.5, "the pre-Compare scene")

        // S2: Cancel restores every value and writes nothing.
        h.compare.cancel()
        XCTAssertFalse(h.compare.isActive)
        XCTAssertEqual(h.inputs, baseline)
        XCTAssertEqual(h.announced.last, SceneCompareCoordinator.cancelledMessage)
        h.autosave.inputsChanged()
        h.autosave.commitNow()
        h.history.capture()
        h.autosave.drain()
        XCTAssertEqual(h.writes.value, writes, "Cancel wrote nothing")
        XCTAssertFalse(h.autosave.isPending)
        XCTAssertEqual(h.historyFingerprint, history)
        XCTAssertTrue(h.history.canUndo, "undo works again")
    }

    /// S3, R6: Keep B writes the scene exactly once with B's values and adds one undo step "Keep S2".
    func testKeepBWritesOnceWithOneUndoStep() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        XCTAssertNil(h.compare.start(a: .snapshot(0), b: 1))
        let writes = h.writes.value
        let main = h.bytes(h.autosave.store.main)
        XCTAssertTrue(h.compare.show(.b))
        XCTAssertTrue(h.compare.keep(.b))
        h.autosave.drain()
        XCTAssertEqual(h.writes.value, writes + 1, "exactly one write")
        XCTAssertNotEqual(h.bytes(h.autosave.store.main), main)
        h.fireEveryTrigger()
        XCTAssertEqual(h.writes.value, writes + 1, "still one write")
        let saved = try SceneDocument.decode([UInt8](try XCTUnwrap(h.bytes(h.autosave.store.main)))).document
        XCTAssertEqual(saved.parameters[VisualParameterIDs.bloomIntensity], .continuous(0.8))
        XCTAssertEqual(h.settings.glowIntensity, 0.8)
        XCTAssertEqual(h.history.undoLabel, "Keep S2")
        XCTAssertEqual(h.announced.last, "Kept S2")
        h.history.undo()
        XCTAssertEqual(h.settings.glowIntensity, 0.5, "undo returns to the pre-Compare scene")
    }

    /// R2, R6 (research SCN-009-D6): the lock refuses start, switch and Keep; Cancel always works.
    func testLockRefusesStartSwitchAndKeepButCancelWorks() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        h.autosave.drain()
        h.settings.sceneLock.lock()
        XCTAssertEqual(h.compare.start(a: .snapshot(0), b: 1), SceneLock.refusalMessage)
        XCTAssertFalse(h.compare.isActive)
        XCTAssertEqual(h.settings.glowIntensity, 0.5)
        h.settings.sceneLock.unlock()
        XCTAssertNil(h.compare.start(a: .snapshot(0), b: 1))
        let writes = h.writes.value
        h.settings.sceneLock.lock()
        XCTAssertFalse(h.compare.show(.b))
        XCTAssertFalse(h.compare.keep(.a))
        XCTAssertTrue(h.compare.isActive, "Compare stays on after a refused Keep")
        XCTAssertEqual(h.compare.status, SceneLock.refusalMessage)
        h.compare.cancel()
        XCTAssertFalse(h.compare.isActive)
        XCTAssertEqual(h.settings.glowIntensity, 0.5, "Cancel restored while locked")
        h.fireEveryTrigger()
        XCTAssertEqual(h.writes.value, writes)
    }

    /// US3, R11: the current scene as A changes nothing and Keep A writes nothing; a history restart (a cue) during
    /// Compare ends it without restoring and the autosave sees the change under its normal rules.
    func testCurrentSceneSideAndRestartAbandons() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        XCTAssertEqual(h.compare.start(a: .snapshot(1), b: 1), SceneCompareCoordinator.sameStateRefusal)
        XCTAssertNil(h.compare.start(a: .current, b: 0))
        XCTAssertEqual(h.settings.glowIntensity, 0.5, "A is the current scene")
        XCTAssertEqual(h.compare.session?.aName, SceneCompareCoordinator.currentName)
        let writes = h.writes.value, history = h.historyFingerprint
        XCTAssertTrue(h.compare.keep(.a))
        h.autosave.drain()
        XCTAssertEqual(h.writes.value, writes, "nothing differs: nothing written")
        XCTAssertEqual(h.historyFingerprint, history, "no undo step")
        XCTAssertEqual(h.announced.last, "Kept Current scene")

        XCTAssertNil(h.compare.start(a: .current, b: 0))
        h.compare.show(.b)
        XCTAssertEqual(h.settings.glowIntensity, 0.2)
        h.history.restart()   // what a cue, Reopen or a replaced photo does
        XCTAssertFalse(h.compare.isActive)
        XCTAssertEqual(h.announced.last, SceneCompareCoordinator.endedMessage)
        XCTAssertFalse(h.autosave.isSuspended)
        XCTAssertFalse(h.history.isSuspended)
        XCTAssertTrue(h.autosave.isPending, "the live change is an ordinary pending edit again")
    }
}
