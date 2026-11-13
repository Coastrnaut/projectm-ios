// AppSettings.swift — the user settings (task T103; FR-048, FR-072, FR-065).
//
// * Performance overlay: off by default (FR-048). Key `settings.performanceOverlay`.
// * Reduce flashing: until the user sets it, it follows the system Reduce Motion setting (FR-072:
//   on by default when Reduce Motion is on). Key `settings.reduceFlashing`; absent = follow.
// * Preset scope (feature 002 FR-119, FR-123): what Next/Previous/Random walk, as
//   PresetScope.storageValue (a search scope is stored as `all`). Key `settings.presetScope`.
// * Visual (VIS-001-R11): projectM (default) or the native Circular Spectrum, key `settings.visual`
//   (unknown → projectM), and the circular spectrum's bar count, key `settings.circularSpectrum.bars`
//   (16/32/64/128; anything else → 64).
// * Glow (FX-001-R4, R11): the circular spectrum's bloom, keys `settings.circularSpectrum.glow`
//   (Bool, absent → off), `…glowIntensity`, `…glowRadius`, `…glowThreshold` (Double; absent, NaN or
//   not a number → the default; out of range → clamped to `BloomParameters`' ranges).
// All keys are "user settings" in the FR-065 list of what may be stored (FR-123 adds the scope,
// VIS-001-R11 the two visual keys, FX-001-R11 the four glow keys).
import Foundation
import Observation
import VisualEffects

@MainActor
@Observable
final class AppSettings {
    static let performanceOverlayKey = "settings.performanceOverlay"
    static let reduceFlashingKey = "settings.reduceFlashing"
    static let presetScopeKey = "settings.presetScope"
    static let visualKey = "settings.visual"
    static let circularSpectrumBarsKey = "settings.circularSpectrum.bars"
    static let glowKey = "settings.circularSpectrum.glow"
    static let glowIntensityKey = "settings.circularSpectrum.glowIntensity"
    static let glowRadiusKey = "settings.circularSpectrum.glowRadius"
    static let glowThresholdKey = "settings.circularSpectrum.glowThreshold"
    static let allKeys = [performanceOverlayKey, reduceFlashingKey, presetScopeKey, visualKey, circularSpectrumBarsKey,
                          glowKey, glowIntensityKey, glowRadiusKey, glowThresholdKey]
    static let circularSpectrumBarChoices = [16, 32, 64, 128]
    static let defaultCircularSpectrumBars = 64

    @ObservationIgnored private let defaults: UserDefaults

    var showsPerformanceOverlay: Bool {
        didSet { defaults.set(showsPerformanceOverlay, forKey: Self.performanceOverlayKey) }
    }

    /// PresetScope.storageValue of the chosen scope; nil before any choice (FR-119).
    var presetScope: String? {
        get { defaults.string(forKey: Self.presetScopeKey) }
        set { defaults.set(newValue, forKey: Self.presetScopeKey) }
    }

    /// Which visual the visualizer shows (VIS-001-R11).
    var visual: VisualChoice {
        didSet { defaults.set(visual.rawValue, forKey: Self.visualKey) }
    }

    /// Bars of the circular spectrum: 16, 32, 64 or 128.
    var circularSpectrumBars: Int {
        didSet {
            if !Self.circularSpectrumBarChoices.contains(circularSpectrumBars) { circularSpectrumBars = Self.defaultCircularSpectrumBars }
            defaults.set(circularSpectrumBars, forKey: Self.circularSpectrumBarsKey)
        }
    }

    /// FX-001: the circular spectrum's glow (off by default).
    var glowEnabled: Bool {
        didSet { defaults.set(glowEnabled, forKey: Self.glowKey) }
    }

    /// 0…1.
    var glowIntensity: Double {
        didSet {
            let clamped = Self.clampedGlowValue(glowIntensity, range: BloomParameters.intensityRange, fallback: BloomParameters.defaultIntensity)
            if clamped != glowIntensity { glowIntensity = clamped }
            defaults.set(clamped, forKey: Self.glowIntensityKey)
        }
    }

    /// Fraction of the output's shorter side, 0.005…0.06.
    var glowRadius: Double {
        didSet {
            let clamped = Self.clampedGlowValue(glowRadius, range: BloomParameters.radiusRange, fallback: BloomParameters.defaultRadius)
            if clamped != glowRadius { glowRadius = clamped }
            defaults.set(clamped, forKey: Self.glowRadiusKey)
        }
    }

    /// 0.1…1.
    var glowThreshold: Double {
        didSet {
            let clamped = Self.clampedGlowValue(glowThreshold, range: BloomParameters.thresholdRange, fallback: BloomParameters.defaultThreshold)
            if clamped != glowThreshold { glowThreshold = clamped }
            defaults.set(clamped, forKey: Self.glowThresholdKey)
        }
    }

    /// What the circular spectrum's bloom uses.
    var glowParameters: BloomParameters {
        BloomParameters(enabled: glowEnabled, intensity: Float(glowIntensity), radius: Float(glowRadius),
                        threshold: Float(glowThreshold))
    }

    private static func clampedGlowValue(_ value: Double?, range: ClosedRange<Float>, fallback: Float) -> Double {
        guard let value, !value.isNaN else { return Double(fallback) }
        return min(max(value, Double(range.lowerBound)), Double(range.upperBound))
    }

    /// The user's choice; nil follows Reduce Motion.
    private(set) var reduceFlashingChoice: Bool?

    /// The system Reduce Motion setting (kept current by the app).
    var systemReduceMotion: Bool

    init(defaults: UserDefaults, systemReduceMotion: Bool) {
        self.defaults = defaults
        self.systemReduceMotion = systemReduceMotion
        showsPerformanceOverlay = defaults.bool(forKey: Self.performanceOverlayKey)
        reduceFlashingChoice = defaults.object(forKey: Self.reduceFlashingKey) as? Bool
        visual = defaults.string(forKey: Self.visualKey).flatMap(VisualChoice.init(rawValue:)) ?? .projectM
        let bars = defaults.integer(forKey: Self.circularSpectrumBarsKey)
        circularSpectrumBars = Self.circularSpectrumBarChoices.contains(bars) ? bars : Self.defaultCircularSpectrumBars
        glowEnabled = defaults.bool(forKey: Self.glowKey)
        glowIntensity = Self.clampedGlowValue(defaults.object(forKey: Self.glowIntensityKey) as? Double,
                                              range: BloomParameters.intensityRange, fallback: BloomParameters.defaultIntensity)
        glowRadius = Self.clampedGlowValue(defaults.object(forKey: Self.glowRadiusKey) as? Double,
                                           range: BloomParameters.radiusRange, fallback: BloomParameters.defaultRadius)
        glowThreshold = Self.clampedGlowValue(defaults.object(forKey: Self.glowThresholdKey) as? Double,
                                              range: BloomParameters.thresholdRange, fallback: BloomParameters.defaultThreshold)
    }

    /// What the renderer uses.
    var reduceFlashing: Bool {
        get { reduceFlashingChoice ?? systemReduceMotion }
        set {
            reduceFlashingChoice = newValue
            defaults.set(newValue, forKey: Self.reduceFlashingKey)
        }
    }

    var reduceFlashingFollowsSystem: Bool { reduceFlashingChoice == nil }

    /// Back to following Reduce Motion.
    func followSystemForReduceFlashing() {
        reduceFlashingChoice = nil
        defaults.removeObject(forKey: Self.reduceFlashingKey)
    }
}

/// The visual the visualizer shows (VIS-001-R11). Stored as the raw value.
enum VisualChoice: String, CaseIterable, Sendable {
    /// The projectM engine on ANGLE (the default, unchanged).
    case projectM
    /// The native circular spectrum (VIS-001).
    case circularSpectrum

    var title: String {
        switch self {
        case .projectM: "projectM"
        case .circularSpectrum: "Circular Spectrum"
        }
    }
}
