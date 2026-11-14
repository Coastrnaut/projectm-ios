// ParameterMacroAppTests.swift — MOD-010-T06 (US2; MOD-010-R5, R6, R9, S1, S3, S4; contract M4): a macro writes its
// targets' base values through the Settings path, reports what it skips, round-trips through SCN-002's capture and
// restore, and one macro drag is one SCN-010 undo step. Real `AppSettings` over a private defaults suite.
import Foundation
import ParameterGraph
import SceneFormat
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParameterMacroAppTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private func settings() throws -> AppSettings {
        let name = "ParameterMacroAppTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults, systemReduceMotion: false)
    }

    private func coordinator(_ settings: AppSettings, macro: ParameterMacro = UITestMacroFixture.acceptance) -> MacroCoordinator {
        let macros = MacroCoordinator.makeDefault(settings: settings)
        macros.restore([SceneMacroEntry(macro)])
        return macros
    }

    /// The app's inputs for these settings and macros (the fields `AppCoordinator.sceneInputs` reads).
    private func inputs(_ settings: AppSettings, _ macros: MacroCoordinator) -> SceneInputs {
        var inputs = SceneAutosaveFixtures.inputs(visual: .circularSpectrum, bars: settings.circularSpectrumBars)
        inputs.glowIntensity = settings.glowIntensity
        inputs.glowRadius = settings.glowRadius
        inputs.glowThreshold = settings.glowThreshold
        inputs.macros = macros.entries
        return inputs
    }

    // MARK: S1 — the targets follow their curves through the Settings path

    func testAcceptanceMacroSetsEverySettingAlongItsOwnCurve() throws {
        let settings = try settings()
        let macros = coordinator(settings)
        let bars: [Double: Int] = [0: 16, 0.25: 32, 0.5: 64, 1: 128]
        for m: Double in [0, 0.25, 0.5, 1] {
            let report = try XCTUnwrap(macros.setValue(m, at: 0))
            XCTAssertEqual(report.applied, [IDs.bloomIntensity, IDs.bloomRadius, IDs.circularSpectrumBarCount])
            XCTAssertTrue(report.skipped.isEmpty)
            XCTAssertEqual(settings.glowIntensity, 0.1 + pow(m, 2) * 0.8, accuracy: 1e-9, "m = \(m)")
            XCTAssertEqual(settings.glowRadius, 0.01 + log(1 + 9 * (1 - m)) / log(10) * 0.04, accuracy: 1e-9, "m = \(m)")
            XCTAssertEqual(settings.circularSpectrumBars, bars[m], "m = \(m)")
            XCTAssertEqual(macros.macros.first??.value, m)
            XCTAssertEqual(macros.entries?.first?.fields["value"], .double(m))
        }
        _ = macros.setValue(0, at: 0)
        XCTAssertEqual(settings.glowIntensity, 0.1, "exact end")
        XCTAssertEqual(settings.glowRadius, 0.05, "exact end")
        XCTAssertNil(macros.setValue(0.5, at: 3), "no such macro")
    }

    // MARK: S3 — skips are reported, the other targets still move

    func testTargetWithoutAnAppControlIsSkippedAndReported() throws {
        let settings = try settings()
        let macro = ParameterMacro(name: "Knee and intensity", targets: [
            MacroTarget(parameter: IDs.bloomKnee),   // registered, but no Settings control writes it
            MacroTarget(parameter: IDs.bloomIntensity, outputMinimum: 0.2, outputMaximum: 0.4),
        ])
        let macros = coordinator(settings, macro: macro)
        let report = try XCTUnwrap(macros.setValue(1, at: 0))
        XCTAssertEqual(report.applied, [IDs.bloomIntensity])
        XCTAssertEqual(report.skipped, [MacroSkippedTarget(parameter: IDs.bloomKnee, reason: MacroCoordinator.noAppControl)])
        XCTAssertEqual(settings.glowIntensity, 0.4)
        XCTAssertEqual(macros.lastReport, report)
    }

    // MARK: Scene round trip (SCN-002 capture → restore)

    func testMacrosRoundTripThroughTheCurrentSceneAndReproduceTheirValues() throws {
        let settings = try settings()
        let macros = coordinator(settings)
        _ = macros.setValue(0.25, at: 0)
        let registry = try SceneAutosaveFixtures.registry()
        let captured = SceneAutosaveCapture.document(inputs(settings, macros), carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        let document = try SceneDocument.decode(captured.encoded()).document
        let live = try document.liveState(registry: registry).state
        let restored = SceneAutosaveCapture.restoredValues(document, live: live, registry: registry)
        XCTAssertEqual(restored.macros, macros.entries)

        let other = try self.settings()
        SceneAutosaveCapture.apply(restored, to: other)
        let reopened = MacroCoordinator.makeDefault(settings: other)
        reopened.restore(restored.macros)
        XCTAssertEqual(other.glowIntensity, settings.glowIntensity, "restore applies the saved values, not the macro")
        XCTAssertEqual(reopened.macros, macros.macros, "curves, ranges and the value come back")
        for m: Double in [0, 0.5, 1] {
            _ = macros.setValue(m, at: 0)
            _ = reopened.setValue(m, at: 0)
            XCTAssertEqual(other.glowIntensity, settings.glowIntensity, "m = \(m)")
            XCTAssertEqual(other.glowRadius, settings.glowRadius, "m = \(m)")
            XCTAssertEqual(other.circularSpectrumBars, settings.circularSpectrumBars, "m = \(m)")
        }
    }

    // MARK: S4 — one macro drag is one undo step

    func testOneMacroDragIsOneUndoStepRestoringEveryTarget() throws {
        let settings = try settings()
        let macros = coordinator(settings)
        _ = macros.setValue(0, at: 0)
        let history = SceneHistoryCoordinator()
        history.inputs = { [unowned self] () -> SceneInputs in self.inputs(settings, macros) }
        history.carry = { () -> SceneAutosaveCarry in SceneAutosaveFixtures.carry }
        history.apply = { (state: SceneInputs) -> Void in
            settings.circularSpectrumBars = state.bars
            settings.glowIntensity = state.glowIntensity
            settings.glowRadius = state.glowRadius
            macros.restore(state.macros)
        }
        history.start(observing: false)
        let before: (Double, Double, Int) = (settings.glowIntensity, settings.glowRadius, settings.circularSpectrumBars)

        for m: Double in [0.2, 0.4, 0.6] {   // one drag: three moves, then the drag ends
            _ = macros.setValue(m, at: 0)
            history.capture()
        }
        history.endCoalescing()
        XCTAssertEqual(history.undoLabel, "Macro Glow sweep 60%")
        XCTAssertEqual(settings.circularSpectrumBars, 64)

        history.undo()
        XCTAssertEqual(settings.glowIntensity, before.0)
        XCTAssertEqual(settings.glowRadius, before.1)
        XCTAssertEqual(settings.circularSpectrumBars, before.2)
        XCTAssertEqual(macros.macros.first??.value, 0)
        XCTAssertFalse(history.canUndo, "the drag was a single step")
        history.redo()
        XCTAssertEqual(macros.macros.first??.value, 0.6)
        XCTAssertEqual(settings.circularSpectrumBars, 64)
    }
}
