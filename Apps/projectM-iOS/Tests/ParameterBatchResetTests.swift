// ParameterBatchResetTests.swift — UIX-010-T02, T06, T07: the roadmap acceptance "Undo restores all previous values
// in one action". Real MOD-001 catalog, real AppSettings write targets, a real SCN-010 `SceneHistoryCoordinator`
// whose inputs are read from the settings (with a modulation binding in the inputs) and whose `apply` writes them
// back, as `AppCoordinator.applySceneInputs` does. No clock, no simulator UI.
import Foundation
import ParameterGraph
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParameterBatchResetTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    @MainActor
    private final class Harness {
        let suite = "UIX010-\(UUID().uuidString)"
        let settings: AppSettings
        let history = SceneHistoryCoordinator()
        var bindings: [AudioFeatureBinding] = [AudioFeatureBinding(source: .kick, target: VisualParameterIDs.bloomIntensity,
                                                                  outputStart: 0, outputEnd: 0.3, mixMode: .add)]

        init() {
            settings = AppSettings(defaults: UserDefaults(suiteName: suite)!, systemReduceMotion: false)
            history.inputs = { [unowned self] () -> SceneInputs in self.inputs }
            history.carry = { () -> SceneAutosaveCarry in SceneAutosaveFixtures.carry }
            history.apply = { [unowned self] (i: SceneInputs) -> Void in self.apply(i) }
            history.start(observing: false)
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        var inputs: SceneInputs {
            var i = SceneInputs(visual: .circularSpectrum, bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                                spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                                glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                                text: .default, photoID: nil, videoID: nil)
            i.bindings = bindings
            return i
        }

        func apply(_ i: SceneInputs) {
            settings.circularSpectrumBars = i.bars
            settings.linearSpectrumOrientation = i.orientation
            settings.linearSpectrumSpacing = i.spacing
            settings.glowEnabled = i.glowEnabled
            settings.glowIntensity = i.glowIntensity
            settings.glowRadius = i.glowRadius
            settings.glowThreshold = i.glowThreshold
            bindings = i.bindings ?? []
        }

        var steps: Int { history.history?.undoSteps.count ?? 0 }

        func value(_ id: ParameterID) -> ParameterValue? { ParameterInspectorTargets.target(for: id, settings: settings)?.get() }

        func defaultValue(_ id: ParameterID) -> ParameterValue? { ParameterInspectorCatalog.descriptor(id)?.defaultValue }

        /// Sets `id` (a Settings edit) and records it as its own step.
        func edit(_ id: ParameterID, _ value: ParameterValue) {
            ParameterInspectorTargets.target(for: id, settings: settings)?.set(value)
            history.endCoalescing()
        }

        /// Four parameters away from their defaults, each its own step.
        func changeFour() {
            edit(IDs.bloomIntensity, .continuous(0.9))
            edit(IDs.bloomThreshold, .continuous(0.3))
            edit(IDs.circularSpectrumBarCount, .enumeration("16"))
            edit(IDs.linearSpectrumOrientation, .enumeration("horizontal"))
        }
    }

    private let four: [ParameterID] = [IDs.bloomIntensity, IDs.bloomThreshold, IDs.circularSpectrumBarCount, IDs.linearSpectrumOrientation]

    // MARK: US1 (T02)

    func testResetOfFourIsOneStepAndOneUndoRestoresAll() throws {
        let h = Harness()
        h.changeFour()
        h.edit(IDs.bloomRadius, .continuous(0.05))   // not selected
        let before: [ParameterID: ParameterValue] = Dictionary(uniqueKeysWithValues: four.map { (id: ParameterID) -> (ParameterID, ParameterValue) in (id, h.value(id)!) })
        for id in four { XCTAssertNotEqual(before[id], h.defaultValue(id), "\(id) starts away from its default") }
        let radius = h.value(IDs.bloomRadius)
        let stepsBefore = h.steps

        let result = ParameterBatchReset.reset(Set(four), settings: h.settings, history: h.history)

        XCTAssertEqual(result.outcome, .reset)
        XCTAssertEqual(result.message, "Reset 4 parameters")
        XCTAssertEqual(h.steps, stepsBefore + 1, "exactly one undo step")
        XCTAssertEqual(h.history.undoLabel, "Reset 4 Parameters")
        for id in four { XCTAssertEqual(h.value(id), h.defaultValue(id), "\(id) at its default") }
        XCTAssertEqual(h.value(IDs.bloomRadius), radius, "an unselected parameter is untouched")
        XCTAssertEqual(h.bindings.count, 1, "bindings stay")

        h.history.undo()
        for id in four { XCTAssertEqual(h.value(id), before[id], "one Undo restores \(id)") }
        XCTAssertEqual(h.steps, stepsBefore, "one action")
        XCTAssertEqual(h.history.undoLabel, "Glow Radius 5.0%", "the earlier edit is still its own step")

        h.history.redo()
        for id in four { XCTAssertEqual(h.value(id), h.defaultValue(id), "Redo resets \(id) again") }
        XCTAssertEqual(h.value(IDs.bloomRadius), radius)
        XCTAssertEqual(h.bindings.count, 1)
    }

    func testPartlyDefaultSelectionCountsOnlyTheChangedOnes() {
        let h = Harness()
        h.edit(IDs.bloomIntensity, .continuous(0.9))
        h.edit(IDs.circularSpectrumBarCount, .enumeration("16"))
        let selection: Set<ParameterID> = [IDs.bloomIntensity, IDs.circularSpectrumBarCount, IDs.bloomThreshold]   // threshold at default
        let stepsBefore = h.steps
        let result = ParameterBatchReset.reset(selection, settings: h.settings, history: h.history)
        XCTAssertEqual(result.written, [IDs.circularSpectrumBarCount, IDs.bloomIntensity].sorted { (a: ParameterID, b: ParameterID) -> Bool in
            self.catalogIndex(a) < self.catalogIndex(b)
        })
        XCTAssertEqual(h.history.undoLabel, "Reset 2 Parameters")
        XCTAssertEqual(h.steps, stepsBefore + 1)
        h.history.undo()
        XCTAssertEqual(h.settings.glowIntensity, 0.9)
        XCTAssertEqual(h.settings.circularSpectrumBars, 16)
    }

    func testQueuedDiscreteChangeIsDroppedAndTheResetIsImmediate() {
        let h = Harness()
        let quantizer = h.settings.parameterQuantizer
        quantizer.schedulesWakeUps = false
        quantizer.hasCues = { () -> Bool in true }
        h.edit(IDs.circularSpectrumBarCount, .enumeration("16"))
        quantizer.mode = .cue
        ParameterInspectorTargets.quantizedTarget(for: IDs.circularSpectrumBarCount, settings: h.settings)?.set(.enumeration("32"))
        XCTAssertTrue(quantizer.isQueued(IDs.circularSpectrumBarCount), "precondition: a change waits for the next cue")
        let stepsBefore = h.steps

        let result = ParameterBatchReset.reset([IDs.circularSpectrumBarCount], settings: h.settings, history: h.history)

        XCTAssertEqual(result.message, "Reset Bars")
        XCTAssertEqual(h.settings.circularSpectrumBars, 64, "written at once, not queued")
        XCTAssertFalse(quantizer.isQueued(IDs.circularSpectrumBarCount), "the queued change can no longer land after the reset")
        XCTAssertEqual(h.steps, stepsBefore + 1)
        quantizer.mode = .off
    }

    // MARK: US2 (T06)

    func testSelectionSelectAllAndLabels() {
        var selection = ParameterResetSelection()
        let glow: [ParameterID] = [IDs.bloomEnabled, IDs.bloomIntensity]
        XCTAssertEqual(selection.buttonTitle, "Reset to Defaults")
        XCTAssertFalse(selection.allSelected([]), "an empty group is never all selected")
        selection.toggle(IDs.bloomIntensity)
        XCTAssertFalse(selection.allSelected(glow))
        selection.setAll(glow, selected: true)
        XCTAssertTrue(selection.allSelected(glow))
        selection.toggle(IDs.circularSpectrumBarCount)
        XCTAssertEqual(selection.buttonTitle, "Reset 3 to Defaults")
        XCTAssertEqual(selection.buttonAccessibilityLabel, "Reset 3 parameters to defaults")
        selection.setAll(glow, selected: false)
        XCTAssertEqual(selection.ids, [IDs.circularSpectrumBarCount])
        XCTAssertEqual(selection.buttonAccessibilityLabel, "Reset 1 parameter to defaults")
        selection.clear()
        XCTAssertEqual(selection.count, 0)
    }

    func testOnlyParametersWithAControlAreResettable() throws {
        let settings = Harness().settings
        XCTAssertTrue(ParameterBatchReset.isResettable(IDs.bloomIntensity, settings: settings))
        XCTAssertFalse(ParameterBatchReset.isResettable(IDs.bloomKnee, settings: settings), "read-only: no control")
    }

    // MARK: US3 (T07)

    func testAlreadyAtDefaultsAddsNoStep() {
        let h = Harness()
        let stepsBefore = h.steps
        let result = ParameterBatchReset.reset(Set(four), settings: h.settings, history: h.history)
        XCTAssertEqual(result.outcome, .alreadyAtDefaults)
        XCTAssertEqual(result.message, "Already at defaults")
        XCTAssertNil(result.undoLabel)
        XCTAssertEqual(h.steps, stepsBefore, "no undo step")
    }

    func testLockedSceneRefusesTheReset() {
        let h = Harness()
        h.changeFour()
        let stepsBefore = h.steps
        h.settings.sceneLock.lock()
        let refusals = h.settings.sceneLock.refusals

        let result = ParameterBatchReset.reset(Set(four), settings: h.settings, history: h.history)

        XCTAssertEqual(result.outcome, .refused)
        XCTAssertEqual(result.message, SceneLock.refusalMessage)
        XCTAssertEqual(h.settings.sceneLock.refusals, refusals + 1, "the lock reports one refusal")
        XCTAssertEqual(h.steps, stepsBefore, "no undo step")
        XCTAssertEqual(h.settings.glowIntensity, 0.9, "nothing written")
        XCTAssertEqual(h.settings.circularSpectrumBars, 16)
        h.settings.sceneLock.unlock()
    }

    private func catalogIndex(_ id: ParameterID) -> Int {
        ParameterInspectorCatalog.registry?.descriptors.firstIndex { (d: ParameterDescriptor) -> Bool in d.id == id } ?? -1
    }
}
