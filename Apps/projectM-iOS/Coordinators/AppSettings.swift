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
// * Linear spectrum (VIS-002-R11): `settings.visual` may also be `linearSpectrum`; its orientation,
//   key `settings.linearSpectrum.orientation` (`vertical`/`horizontal`; anything else → vertical),
//   and spacing, key `settings.linearSpectrum.spacing` (0, 0.2 or 0.5; anything else → 0.2). Bars
//   and Glow are shared by both native spectra and keep their keys (spec 025, Clarifications).
// * Oscilloscope (VIS-003-R10): `settings.visual` may also be `oscilloscope`; its line, key
//   `settings.oscilloscope.line` (`thin`/`medium`/`thick`; anything else → medium), and window, key
//   `settings.oscilloscope.window` (10, 20 or 40 ms as an Int; anything else → 20). Glow is shared with
//   the spectra; Bars does not apply.
// * Spectral smoothing (ANL-003-R6): the circular and linear spectra's attack and release, keys
//   `settings.spectrum.attack` (0, 25, 50 or 100) and `settings.spectrum.release` (0, 100, 250 or
//   500), Int milliseconds; anything else → 0 (Instant, today's look).
// * Camera (CAM-001-R1, R11): `visual` may be `.camera` for the session only. It is never written,
//   so the key keeps the visual chosen before it, and a stored `camera` (never written by the app)
//   reads as projectM: the camera starts only from the user's choice in the running session.
// * Camera position and mirror (CAM-002-R1, R3, R6): `settings.camera.position` (`back`/`front`;
//   anything else → back), `settings.camera.mirrorFront` (Bool, absent → on) and
//   `settings.camera.mirrorBack` (Bool, absent → off). Ordinary settings: they never start the camera
//   (the Camera choice stays session only) and are not recorded in scenes or cues.
// * Photo (MED-001-R8): `visual` may be `photo`, stored like the spectra (no sensor is involved).
//   The chosen photo's identifier is `settings.photo.id` (PhotoStore.idKey; absent = no photo); the
//   copy itself lives in Application Support/Photos.
// * Video (MED-002-R8): `visual` may be `video`, stored like Photo. The chosen video's identifier is
//   `settings.video.id` (VideoStore.idKey); the copy lives in Application Support/Videos. The playback
//   position is never stored.
// * Text (MED-009-R10, R11): `visual` may be `text`, stored like Photo. The message and its style are
//   one versioned JSON value, key `settings.text.overlay` (TextOverlayStore.key).
// * OSC receiver (OSC-001-R15): key `settings.osc.enabled` (Bool, absent → off, so a fresh install
//   opens no listener) and `settings.osc.port` (Int, absent or outside 1024-65535 → 9000).
// All keys are "user settings" in the FR-065 list of what may be stored (FR-123 adds the scope,
// VIS-001-R11 the two visual keys, FX-001-R11 the four glow keys, VIS-002-R11 the two linear keys,
// VIS-003-R10 the two oscilloscope keys, ANL-003-R6 the two smoothing keys).
import AnalysisFeatures
import CameraLayer
import Foundation
import Observation
import PerformanceControl
import VisualEffects
import VisualGenerators

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
    static let linearSpectrumOrientationKey = "settings.linearSpectrum.orientation"
    static let linearSpectrumSpacingKey = "settings.linearSpectrum.spacing"
    static let oscilloscopeLineKey = "settings.oscilloscope.line"
    static let oscilloscopeWindowKey = "settings.oscilloscope.window"
    static let spectrumAttackKey = "settings.spectrum.attack"
    static let spectrumReleaseKey = "settings.spectrum.release"
    static let oscEnabledKey = "settings.osc.enabled"
    static let oscPortKey = "settings.osc.port"
    static let cameraPositionKey = "settings.camera.position"       // CAM-002
    static let cameraMirrorFrontKey = "settings.camera.mirrorFront"
    static let cameraMirrorBackKey = "settings.camera.mirrorBack"
    /// MED-001: the stored photo's identifier (written by PhotoStore).
    static let photoIDKey = PhotoStore.idKey
    /// MED-002: the stored video's identifier (written by VideoStore).
    static let videoIDKey = VideoStore.idKey
    /// MED-009: the Text visual's message and style (written by TextOverlayStore).
    static let textOverlayKey = TextOverlayStore.key
    static let allKeys = [performanceOverlayKey, reduceFlashingKey, presetScopeKey, visualKey, circularSpectrumBarsKey,
                          glowKey, glowIntensityKey, glowRadiusKey, glowThresholdKey,
                          linearSpectrumOrientationKey, linearSpectrumSpacingKey, oscEnabledKey, oscPortKey, photoIDKey, videoIDKey,
                          textOverlayKey, oscilloscopeLineKey, oscilloscopeWindowKey, spectrumAttackKey, spectrumReleaseKey,
                          cameraPositionKey, cameraMirrorFrontKey, cameraMirrorBackKey]
    /// VIS-002-R4: the spacings offered for the linear spectrum.
    static let linearSpectrumSpacingChoices: [(title: String, value: Double)] = [("None", 0), ("Narrow", 0.2), ("Wide", 0.5)]
    static let defaultLinearSpectrumSpacing = 0.2
    /// VIS-003-R10: the oscilloscope's windows in milliseconds.
    static let oscilloscopeWindowChoices = [10, 20, 40]
    static let defaultOscilloscopeWindow = 20
    /// ANL-003-R6: the offered attack and release times in milliseconds (0 = Instant, the default).
    static let spectrumAttackChoices = [0, 25, 50, 100]
    static let spectrumReleaseChoices = [0, 100, 250, 500]
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
        didSet {
            guard !visual.usesCamera else { return }   // CAM-001-R11: session only
            defaults.set(visual.rawValue, forKey: Self.visualKey)
        }
    }

    /// CAM-012-R5: the visual chosen before Camera, read from the stored key (Camera never writes
    /// it); projectM when absent, unknown or `camera`. Read only: nothing is written.
    var visualBeforeCamera: VisualChoice {
        let stored = defaults.string(forKey: Self.visualKey).flatMap(VisualChoice.init(rawValue:)) ?? .projectM
        return stored.usesCamera ? .projectM : stored
    }

    /// CAM-002-R1: which camera the Camera visual uses (back by default). Never starts the camera.
    var cameraPosition: CameraPosition {
        didSet { defaults.set(cameraPosition.rawValue, forKey: Self.cameraPositionKey) }
    }

    /// CAM-002-R3: the front camera's mirror (on by default).
    var cameraMirrorFront: Bool {
        didSet { defaults.set(cameraMirrorFront, forKey: Self.cameraMirrorFrontKey) }
    }

    /// CAM-002-R3: the rear camera's mirror (off by default).
    var cameraMirrorBack: Bool {
        didSet { defaults.set(cameraMirrorBack, forKey: Self.cameraMirrorBackKey) }
    }

    /// CAM-002-R3: the mirror of the chosen camera (each camera keeps its own).
    var cameraMirrored: Bool {
        get { cameraPosition == .front ? cameraMirrorFront : cameraMirrorBack }
        set {
            if cameraPosition == .front { cameraMirrorFront = newValue } else { cameraMirrorBack = newValue }
        }
    }

    /// Bars of the circular spectrum: 16, 32, 64 or 128.
    var circularSpectrumBars: Int {
        didSet {
            if !Self.circularSpectrumBarChoices.contains(circularSpectrumBars) { circularSpectrumBars = Self.defaultCircularSpectrumBars }
            defaults.set(circularSpectrumBars, forKey: Self.circularSpectrumBarsKey)
        }
    }

    /// VIS-002: which way the linear spectrum's bars grow (vertical by default).
    var linearSpectrumOrientation: LinearSpectrumOrientation {
        didSet { defaults.set(linearSpectrumOrientation.rawValue, forKey: Self.linearSpectrumOrientationKey) }
    }

    /// VIS-002: the linear spectrum's bar spacing, one of `linearSpectrumSpacingChoices` (0.2 otherwise).
    var linearSpectrumSpacing: Double {
        didSet {
            if !Self.isSpacingChoice(linearSpectrumSpacing) { linearSpectrumSpacing = Self.defaultLinearSpectrumSpacing }
            defaults.set(linearSpectrumSpacing, forKey: Self.linearSpectrumSpacingKey)
        }
    }

    private static func isSpacingChoice(_ value: Double) -> Bool {
        linearSpectrumSpacingChoices.contains { $0.value == value }
    }

    /// VIS-003: the oscilloscope's line thickness (Medium by default).
    var oscilloscopeLine: OscilloscopeLine {
        didSet { defaults.set(oscilloscopeLine.rawValue, forKey: Self.oscilloscopeLineKey) }
    }

    /// VIS-003: the oscilloscope's window, one of `oscilloscopeWindowChoices` (20 otherwise).
    var oscilloscopeWindowMilliseconds: Int {
        didSet {
            if !Self.oscilloscopeWindowChoices.contains(oscilloscopeWindowMilliseconds) {
                oscilloscopeWindowMilliseconds = Self.defaultOscilloscopeWindow
            }
            defaults.set(oscilloscopeWindowMilliseconds, forKey: Self.oscilloscopeWindowKey)
        }
    }

    /// ANL-003: the spectra's attack, one of `spectrumAttackChoices` (0 otherwise).
    var spectrumAttackMilliseconds: Int {
        didSet {
            if !Self.spectrumAttackChoices.contains(spectrumAttackMilliseconds) { spectrumAttackMilliseconds = 0 }
            defaults.set(spectrumAttackMilliseconds, forKey: Self.spectrumAttackKey)
        }
    }

    /// ANL-003: the spectra's release, one of `spectrumReleaseChoices` (0 otherwise).
    var spectrumReleaseMilliseconds: Int {
        didSet {
            if !Self.spectrumReleaseChoices.contains(spectrumReleaseMilliseconds) { spectrumReleaseMilliseconds = 0 }
            defaults.set(spectrumReleaseMilliseconds, forKey: Self.spectrumReleaseKey)
        }
    }

    /// What the native spectrum host's smoother uses (ANL-003-R3).
    var spectrumSmoothing: SmoothingTimes {
        let attack: Double = Double(spectrumAttackMilliseconds) / 1_000
        let release: Double = Double(spectrumReleaseMilliseconds) / 1_000
        return SmoothingTimes(attackSeconds: attack, releaseSeconds: release)
    }

    /// The display title of a smoothing choice ("Instant" for 0).
    static func smoothingTitle(milliseconds: Int) -> String {
        milliseconds == 0 ? "Instant" : "\(milliseconds) ms"
    }

    /// FX-001: the native spectra's glow (off by default).
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

    /// OSC-001: the OSC receiver (off by default; OSC-001-R1).
    var oscEnabled: Bool {
        didSet { defaults.set(oscEnabled, forKey: Self.oscEnabledKey) }
    }

    /// OSC-001: the UDP port, 1024-65535 (9000 otherwise).
    var oscPort: Int {
        didSet {
            if !OSCPort.isValid(oscPort) { oscPort = Int(OSCPort.defaultPort) }
            defaults.set(oscPort, forKey: Self.oscPortKey)
        }
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
        let storedVisual = defaults.string(forKey: Self.visualKey).flatMap(VisualChoice.init(rawValue:)) ?? .projectM
        visual = storedVisual.usesCamera ? .projectM : storedVisual   // CAM-001-R11
        cameraPosition = defaults.string(forKey: Self.cameraPositionKey).flatMap(CameraPosition.init(rawValue:)) ?? .back
        cameraMirrorFront = defaults.object(forKey: Self.cameraMirrorFrontKey) as? Bool ?? CameraPosition.front.defaultMirrored
        cameraMirrorBack = defaults.object(forKey: Self.cameraMirrorBackKey) as? Bool ?? CameraPosition.back.defaultMirrored
        let bars = defaults.integer(forKey: Self.circularSpectrumBarsKey)
        circularSpectrumBars = Self.circularSpectrumBarChoices.contains(bars) ? bars : Self.defaultCircularSpectrumBars
        linearSpectrumOrientation = defaults.string(forKey: Self.linearSpectrumOrientationKey)
            .flatMap(LinearSpectrumOrientation.init(rawValue:)) ?? .vertical
        let spacing = defaults.object(forKey: Self.linearSpectrumSpacingKey) as? Double
        linearSpectrumSpacing = spacing.map(Self.isSpacingChoice) == true ? spacing! : Self.defaultLinearSpectrumSpacing
        oscilloscopeLine = defaults.string(forKey: Self.oscilloscopeLineKey).flatMap(OscilloscopeLine.init(rawValue:)) ?? .medium
        let window = defaults.integer(forKey: Self.oscilloscopeWindowKey)
        oscilloscopeWindowMilliseconds = Self.oscilloscopeWindowChoices.contains(window) ? window : Self.defaultOscilloscopeWindow
        let attack = defaults.integer(forKey: Self.spectrumAttackKey)
        spectrumAttackMilliseconds = Self.spectrumAttackChoices.contains(attack) ? attack : 0
        let release = defaults.integer(forKey: Self.spectrumReleaseKey)
        spectrumReleaseMilliseconds = Self.spectrumReleaseChoices.contains(release) ? release : 0
        glowEnabled = defaults.bool(forKey: Self.glowKey)
        oscEnabled = defaults.bool(forKey: Self.oscEnabledKey)
        let port = defaults.integer(forKey: Self.oscPortKey)
        oscPort = OSCPort.isValid(port) ? port : Int(OSCPort.defaultPort)
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
    /// The native linear spectrum (VIS-002).
    case linearSpectrum
    /// The native waveform oscilloscope (VIS-003).
    case oscilloscope
    /// The rear or front camera (CAM-002) with the circular spectrum over it (CAM-001; session only).
    case camera
    /// The imported photo with the circular spectrum over it (MED-001; persisted).
    case photo
    /// The imported video with the circular spectrum over it (MED-002; persisted).
    case video
    /// The circular spectrum with the user's text over it (MED-009; persisted).
    case text

    var title: String {
        switch self {
        case .projectM: "projectM"
        case .circularSpectrum: "Circular Spectrum"
        case .linearSpectrum: "Linear Spectrum"
        case .oscilloscope: "Oscilloscope"
        case .camera: "Camera"
        case .photo: "Photo"
        case .video: "Video"
        case .text: "Text"
        }
    }

    /// Drawn by the native spectrum host instead of projectM.
    var isNative: Bool { self == .circularSpectrum || self == .linearSpectrum || self == .oscilloscope }

    /// Shown instead of projectM (a native spectrum, the camera or the photo visual).
    var replacesProjectM: Bool { self != .projectM }

    /// The camera visual (CAM-001): uses the chosen camera (CAM-002) while shown.
    var usesCamera: Bool { self == .camera }

    /// The photo visual (MED-001).
    var usesPhoto: Bool { self == .photo }

    /// The video visual (MED-002).
    var usesVideo: Bool { self == .video }

    /// The text visual (MED-009).
    var usesText: Bool { self == .text }
}

/// The oscilloscope's line thickness (VIS-003-R10). Stored as the raw value.
enum OscilloscopeLine: String, CaseIterable, Sendable {
    case thin, medium, thick

    var title: String {
        switch self {
        case .thin: "Thin"
        case .medium: "Medium"
        case .thick: "Thick"
        }
    }

    /// Fraction of the output's shorter side (OscilloscopeConfiguration.lineThickness).
    var thickness: Double {
        switch self {
        case .thin: 0.004
        case .medium: 0.008
        case .thick: 0.016
        }
    }
}
