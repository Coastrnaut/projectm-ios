// ParameterInspectorTests.swift — UIX-003-T05, T09, T12 (specs/136-uix-003-parameter-inspector; S1, S3).
//
// * Acceptance (S1): for a 0…1 value, a fraction of the output, a boolean and an enum, a change through the
//   inspector's target then Reset leaves the real `AppSettings` value exactly equal to the registry's
//   declared default, and a fresh `AppSettings` on the same suite reads it (persisted).
// * Read-only parameters have no target; unknown launch-argument IDs open nothing.
// * Reset is one undo step in a scene history over the same settings.
// * Formatting of unit, range, step and default (display and spoken).
// * The modulation reading with a stub binding, a MIDI value and the safety clamp; the 10 Hz refresh.
// Each test makes its own UserDefaults suite and removes it; nothing is mutated in setUp/tearDown.
import Foundation
import ParameterGraph
import SceneFormat
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class ParameterInspectorTests: XCTestCase {
    private typealias IDs = VisualParameterIDs

    private func makeSettings() throws -> (AppSettings, UserDefaults, String) {
        let name = "ParameterInspectorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (AppSettings(defaults: defaults, systemReduceMotion: false), defaults, name)
    }

    private func descriptor(_ id: ParameterID) throws -> ParameterDescriptor {
        try XCTUnwrap(ParameterInspectorCatalog.descriptor(id))
    }

    // MARK: Acceptance: Reset restores the declared registry default (S1)

    func testResetRestoresTheDeclaredRegistryDefaultExactly() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let changes: [(ParameterID, ParameterValue)] = [
            (IDs.bloomIntensity, .continuous(0.9)),          // 0…1
            (IDs.bloomRadius, .continuous(0.05)),            // fraction of the output (Float-widened default)
            (IDs.bloomThreshold, .continuous(0.3)),
            (IDs.bloomEnabled, .boolean(true)),              // boolean
            (IDs.circularSpectrumBarCount, .enumeration("128")),   // enum
            (IDs.linearSpectrumOrientation, .enumeration("horizontal")),
            (IDs.linearSpectrumSpacing, .continuous(0.5)),   // a choice-only continuous value
        ]
        for (id, changed) in changes {
            let d = try descriptor(id)
            let target = try XCTUnwrap(ParameterInspectorTargets.target(for: id, settings: settings), "\(id)")
            target.set(changed)
            XCTAssertEqual(target.get(), changed, "\(id): the change reached the setting")
            XCTAssertNotEqual(target.get(), d.defaultValue, "\(id): the change differs from the default")
            ParameterInspectorReset.reset(d, target: target)
            XCTAssertEqual(target.get(), d.defaultValue, "\(id): Reset restores the declared registry default exactly")
            let relaunched = try XCTUnwrap(ParameterInspectorTargets.target(for: id, settings: AppSettings(defaults: defaults, systemReduceMotion: false)))
            XCTAssertEqual(relaunched.get(), d.defaultValue, "\(id): the default was saved")
        }
        // Bit-exact for the Float-widened glow defaults.
        XCTAssertEqual(settings.glowRadius.bitPattern, try descriptor(IDs.bloomRadius).defaultValue.doubleValue?.bitPattern)
        XCTAssertEqual(settings.circularSpectrumBars, 64)
    }

    func testEveryInspectableIDHasATargetAndOthersAreReadOnly() throws {
        let (settings, _, name) = try makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let registry = try XCTUnwrap(ParameterInspectorCatalog.registry)
        for id in registry.ids {
            let target = ParameterInspectorTargets.target(for: id, settings: settings)
            XCTAssertEqual(target != nil, ParameterInspectorTargets.inspectableIDs.contains(id), "\(id)")
            if let target { XCTAssertEqual(target.get().kindName, try descriptor(id).defaultValue.kindName, "\(id): same kind") }
        }
        XCTAssertNil(ParameterInspectorTargets.target(for: IDs.bloomKnee, settings: settings), "no control: read-only, no Reset")
    }

    func testResetIsOneUndoStepAndAnnouncesTheDefault() throws {
        let (settings, _, name) = try makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let history = SceneHistoryCoordinator()
        history.inputs = { () -> SceneInputs in
            var inputs = SceneAutosaveFixtures.inputs(visual: .circularSpectrum)
            inputs.glowIntensity = settings.glowIntensity
            return inputs
        }
        history.carry = { () -> SceneAutosaveCarry in SceneAutosaveFixtures.carry }
        history.apply = { (inputs: SceneInputs) -> Void in settings.glowIntensity = inputs.glowIntensity }
        history.start(observing: false)
        let d = try descriptor(IDs.bloomIntensity)
        let target = try XCTUnwrap(ParameterInspectorTargets.target(for: IDs.bloomIntensity, settings: settings))
        target.set(.continuous(0.9))
        history.endCoalescing()
        let text = ParameterInspectorReset.reset(d, target: target, endCoalescing: { () -> Void in history.endCoalescing() })
        XCTAssertEqual(text, "Intensity reset to 50 percent")
        XCTAssertEqual(settings.glowIntensity, 0.5)
        history.undo()
        XCTAssertEqual(settings.glowIntensity, 0.9, "one undo step returns the value before Reset")
    }

    func testLaunchRequestAcceptsOnlyRegisteredIDs() {
        XCTAssertEqual(InspectedParameter.request("effect.bloom.intensity")?.id, IDs.bloomIntensity)
        XCTAssertNil(InspectedParameter.request("effect.bloom.unknown"))
        XCTAssertNil(InspectedParameter.request(nil))
    }

    // MARK: Formatting (T09)

    func testSummaryShowsUnitRangeStepAndDefault() throws {
        let intensity = ParameterInspectorSummary(try descriptor(IDs.bloomIntensity))
        XCTAssertEqual(intensity.name, "Intensity")
        XCTAssertEqual(intensity.group, "Glow")
        XCTAssertEqual(intensity.unit, "Percent")
        XCTAssertEqual(intensity.range, "0%…100%")
        XCTAssertEqual(intensity.spokenRange, "0 percent to 100 percent")
        XCTAssertEqual(intensity.step, "1%")
        XCTAssertEqual(intensity.defaultText, "50%")
        XCTAssertEqual(intensity.spokenDefault, "50 percent")

        let radius = ParameterInspectorSummary(try descriptor(IDs.bloomRadius))
        XCTAssertEqual(radius.unit, "Percent of the output")
        XCTAssertEqual(radius.range, "0.5%…6.0%")
        XCTAssertEqual(radius.step, "0.1%")
        XCTAssertEqual(radius.defaultText, "2.0%")

        let bars = ParameterInspectorSummary(try descriptor(IDs.circularSpectrumBarCount))
        XCTAssertEqual(bars.range, "16, 32, 64, 128")
        XCTAssertEqual(bars.defaultText, "64")
        XCTAssertNil(bars.step)

        let glow = ParameterInspectorSummary(try descriptor(IDs.bloomEnabled))
        XCTAssertEqual(glow.range, "On or Off")
        XCTAssertEqual(glow.defaultText, "Off")
    }

    func testUnitsFormatWithTheirSymbols() {
        XCTAssertEqual(ParameterValueText.display(0.25, unit: .seconds, step: 0.01), "0.25 s")
        XCTAssertEqual(ParameterValueText.spoken(0.25, unit: .seconds, step: 0.01), "0.25 seconds")
        XCTAssertEqual(ParameterValueText.display(1.2, unit: .perSecond, step: 0.01), "1.20/s")
        XCTAssertEqual(ParameterValueText.spoken(1.2, unit: .perSecond, step: 0.01), "1.20 per second")
        XCTAssertEqual(ParameterValueText.display(30, unit: .degrees, step: 1), "30°")
        XCTAssertEqual(ParameterValueText.display(0.025, unit: .fractionOfOutput, step: 0.001), "2.5%")
        XCTAssertEqual(ParameterValueText.percentDecimals(step: 0.01), 0)
        XCTAssertEqual(ParameterValueText.percentDecimals(step: 0.001), 1)
        XCTAssertEqual(ParameterValueText.percentDecimals(step: nil), 1)
    }

    // MARK: Modulation (T12)

    func testNothingDrivingTheParameterReadsAsNotModulated() throws {
        let d = try descriptor(IDs.bloomIntensity)
        XCTAssertNil(ParameterModulationReader.reading(d, manual: 0.5, bindings: [], external: nil, modulated: nil, rendered: 0.5))
        let other = AudioFeatureBinding(source: .kick, target: IDs.bloomRadius, outputStart: 0.01, outputEnd: 0.03)
        XCTAssertNil(ParameterModulationReader.reading(d, manual: 0.5, bindings: [other], external: nil, modulated: nil, rendered: 0.5),
                     "another parameter's binding does not count")
    }

    func testAnActiveBindingIsListedWithTheEffectiveValue() throws {
        let d = try descriptor(IDs.bloomIntensity)
        let kick = AudioFeatureBinding(source: .kick, target: IDs.bloomIntensity, outputStart: 0, outputEnd: 0.4)
        // A real modulator as the stub source: the kick at 1 drives the intensity to its output end.
        let modulator = AudioFeatureModulator(registry: try XCTUnwrap(ParameterInspectorCatalog.registry))
        try modulator.bind(kick)
        let bands: [Float] = [0]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            modulator.advance(frame: AudioFeatureFrame(bands: buffer, kick: 1), timeNanoseconds: 1_000)
        }
        let modulated = modulator.value(for: IDs.bloomIntensity, manual: 0.5)
        let reading = try XCTUnwrap(ParameterModulationReader.reading(d, manual: 0.5, bindings: modulator.bindings, external: nil,
                                                                       modulated: modulated, rendered: nil))
        XCTAssertEqual(reading.sources, ["Kick → 0%…40% (replace)"])
        XCTAssertEqual(reading.effective, 0.4, accuracy: 1e-9)
        XCTAssertFalse(reading.limitedBySafety)
    }

    func testMIDIAndTheSafetyClampAreShown() throws {
        let d = try descriptor(IDs.bloomIntensity)
        let midi = try XCTUnwrap(ParameterModulationReader.reading(d, manual: 0.5, bindings: [], external: 0.8, modulated: nil, rendered: 0.6))
        XCTAssertEqual(midi.sources, ["MIDI control"])
        XCTAssertEqual(midi.effective, 0.6, "the rendered value, after the clamp")
        XCTAssertTrue(midi.limitedBySafety)
        let unclamped = try XCTUnwrap(ParameterModulationReader.reading(d, manual: 0.5, bindings: [], external: 0.8, modulated: nil,
                                                                         rendered: Double(Float(0.8))))
        XCTAssertFalse(unclamped.limitedBySafety, "Float rounding is not a clamp")
        let add = AudioFeatureBinding(source: .bandMean, target: IDs.bloomIntensity, outputStart: 0.1, outputEnd: 0.2, mixMode: .add)
        XCTAssertEqual(ParameterModulationReader.describe(add, descriptor: d), "Average level → +10%…+20% (add)")
    }

    func testRefreshIsAtMostTenTimesASecond() {
        XCTAssertEqual(ParameterInspectorTiming.refreshSeconds, 0.1)
    }
}
