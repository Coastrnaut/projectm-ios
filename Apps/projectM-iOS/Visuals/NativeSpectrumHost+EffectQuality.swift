// NativeSpectrumHost+EffectQuality.swift — PERF-003 (specs/173-perf-003-adaptive-quality; contract C4): the native
// host's adaptive effect quality.
//
// * Inputs: the thermal state and Low Power Mode, read when they change (`refreshQuality()`, also on glow changes),
//   or their overrides (tests; DEBUG `-uitestThermalState <nominal|fair|serious|critical>`), and PERF-002's budget
//   signal, which the coordinator sets once a second while the performance overlay runs.
// * The ladder is started with the loop (the floor at once, no fade) and stepped each frame with the display-link
//   timestamp. Only when its applied level or fade weight moved does the glow change: the level goes to the bloom (a
//   plan rebuild only on a level change) and the weight is applied in `resolveEffectiveGlow()` after the ACC-012
//   clamp, an intensity-only update. Nothing here allocates.
// * The governor (FR-049) gets `adaptiveEffects` while the glow is switched on and available: the serious state then
//   lowers the glow instead of capping the frame rate (PERF-003-R7). The manual switch, not the modulated intensity,
//   decides, so the display link's range never flips from frame to frame.
import Foundation
import Rendering
import VisualEffects

extension NativeSpectrumHost {
    static let thermalStateArgument = "-uitestThermalState"

    /// DEBUG: the thermal state named after `-uitestThermalState`; nil otherwise (and always in Release).
    static var launchThermalOverride: EffectThermalState? {
        #if DEBUG
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: thermalStateArgument), index + 1 < arguments.count else { return nil }
        return EffectThermalState(label: arguments[index + 1])
        #else
        return nil
        #endif
    }

    static func effectThermal(_ state: ProcessInfo.ThermalState) -> EffectThermalState {
        switch ThermalLevel(state) {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        }
    }

    static func governorThermal(_ state: EffectThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        }
    }

    /// The glow is switched on and can run: the ladder has an effect to reduce.
    var adaptiveEffectsOn: Bool { glow.enabled && !glowUnavailable }

    /// The governor's settings for the current inputs (PERF-003-R7), capped by the power profile (PERF-008-R3).
    var governedQuality: QualitySettings {
        QualityGovernor.settings(thermal: Self.governorThermal(effectThermal), lowPower: effectLowPower,
                                 adaptiveEffects: adaptiveEffectsOn, budget: PowerProfileState.budget(lowPower: effectLowPower))
    }

    /// Reads the device's thermal state and Low Power Mode, or their overrides.
    func readEffectInputs() {
        let info = ProcessInfo.processInfo
        effectThermal = thermalOverride ?? Self.effectThermal(info.thermalState)
        effectLowPower = lowPowerOverride ?? info.isLowPowerModeEnabled
    }

    /// A fresh loop: the ladder at the floor with full weight.
    func startEffectQuality() {
        readEffectInputs()
        effectLadder.start(thermal: effectThermal, lowPower: effectLowPower)
        applyEffectLevel()
    }

    /// One frame of the ladder (also called directly by tests with an injected time).
    func stepEffectQuality(time: Double) {
        let level: EffectQualityLevel = effectLadder.applied
        let factor: Float = effectLadder.intensityFactor
        effectLadder.step(time: time, thermal: effectThermal, lowPower: effectLowPower, budget: effectBudget)
        guard effectLadder.applied != level || effectLadder.intensityFactor != factor else { return }
        applyEffectLevel()
    }

    private func applyEffectLevel() {
        if let bloom, bloom.quality != effectLadder.applied { bloom.quality = effectLadder.applied }
        resolveEffectiveGlow()
    }

    /// The level the glow is drawn at.
    var effectQualityLevel: EffectQualityLevel { effectLadder.applied }

    /// "effect quality reduced (thermal)" (PERF-003-R10).
    var effectQualityLine: String { effectLadder.overlayLine }
}
