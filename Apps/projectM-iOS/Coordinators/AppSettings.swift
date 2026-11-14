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
// * Lissajous (VIS-004-R11): `settings.visual` may also be `lissajous`; its plot, key `settings.lissajous.mode`
//   (`xy`/`midSide`; anything else → xy), and persistence, key `settings.lissajous.persistence` (Bool, absent →
//   off). Glow is shared; Bars does not apply.
// * Radial waveform (VIS-005-R9): `settings.visual` may also be `radialWaveform`; its ring, key
//   `settings.radialWaveform.ring` (`small`/`medium`/`large`; anything else → medium), and amplitude, key
//   `settings.radialWaveform.amplitude` (`low`/`medium`/`high`; anything else → medium). Glow is shared; Bars
//   does not apply.
// * Beat rings (VIS-006-R9): `settings.visual` may also be `beatRings`; its ring life, key `settings.beatRings.life`
//   (`short`/`medium`/`long`; anything else → medium). Glow is shared; Bars does not apply.
// * Mandala (VIS-007-R9): `settings.visual` may also be `mandala`; its symmetry, key `settings.mandala.symmetry` (Int:
//   3, 4, 5, 6, 8 or 12; anything else → 6), mirror, key `settings.mandala.mirror` (Bool, off), and petal style, key
//   `settings.mandala.petal` (`petal`/`round`/`spike`; anything else → petal). Glow is shared; Bars does not apply.
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
// * Camera crop (CAM-007-R1, R6): `settings.camera.cropMode` (`fill`/`fit`; else fill),
//   `settings.camera.cropAnchor` (`center`/`top`/`bottom`; else center) and `settings.camera.zoom`
//   (1, 1.5, 2 or 3; else 1), one set for both cameras. Same rules as position and mirror.
// * Camera lens (CAM-003-R4, R5): `settings.camera.lens` (`ultraWide`/`wide`/`telephoto`; else wide),
//   the back camera's last chosen lens. A lens this device lacks is used as wide (the coordinator
//   resolves it against the device's lenses); the stored value is kept. Same rules as position.
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
// VIS-003-R10 the two oscilloscope keys, VIS-004-R11 the two Lissajous keys, VIS-005-R9 the two radial waveform keys, VIS-006-R9 the beat rings' key, VIS-007-R9 the three mandala keys, ANL-003-R6 the two smoothing keys, ACC-003-R13 the palette key
// `settings.visual.colorBlindSafePalette`).
// * Sensory safety (ACC-012-R8): the profile and its custom limits, four `settings.sensorySafety.*` keys owned by
//   `SensorySafetySetting`; `safetyClamp` combines them with Reduce flashing (stricter wins, ADR-0049).
import AnalysisFeatures
import CameraLayer
import FlashSafety
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
    static let lissajousModeKey = "settings.lissajous.mode"                 // VIS-004
    static let lissajousPersistenceKey = "settings.lissajous.persistence"
    static let radialWaveformRingKey = "settings.radialWaveform.ring"       // VIS-005
    static let radialWaveformAmplitudeKey = "settings.radialWaveform.amplitude"
    static let beatRingsLifeKey = "settings.beatRings.life"                 // VIS-006
    static let mandalaSymmetryKey = "settings.mandala.symmetry"             // VIS-007
    static let mandalaMirrorKey = "settings.mandala.mirror"
    static let mandalaPetalKey = "settings.mandala.petal"
    static let spectrumAttackKey = "settings.spectrum.attack"
    static let spectrumReleaseKey = "settings.spectrum.release"
    static let oscEnabledKey = "settings.osc.enabled"
    static let oscPortKey = "settings.osc.port"
    static let midiEnabledKey = "settings.midi.enabled"   // MIDI-001-R8
    static let colorBlindSafePaletteKey = "settings.visual.colorBlindSafePalette"   // ACC-003-R13
    static let cameraPositionKey = "settings.camera.position"       // CAM-002
    static let cameraMirrorFrontKey = "settings.camera.mirrorFront"
    static let cameraMirrorBackKey = "settings.camera.mirrorBack"
    static let cameraCropModeKey = "settings.camera.cropMode"       // CAM-007
    static let cameraCropAnchorKey = "settings.camera.cropAnchor"
    static let cameraZoomKey = "settings.camera.zoom"
    static let cameraLensKey = "settings.camera.lens"               // CAM-003
    /// MED-001: the stored photo's identifier (written by PhotoStore).
    static let photoIDKey = PhotoStore.idKey
    /// MED-006: the image slideshow (written by SlideshowStore).
    static let slideshowKey = SlideshowStore.key
    /// MED-002: the stored video's identifier (written by VideoStore).
    static let videoIDKey = VideoStore.idKey
    /// MED-003: the stored video's loop region (written by VideoStore).
    static let videoLoopKey = VideoStore.loopKey
    /// MED-004: the stored video's playback speed (written by VideoStore).
    static let videoSpeedKey = VideoStore.speedKey
    /// MED-009: the Text visual's message and style (written by TextOverlayStore).
    static let textOverlayKey = TextOverlayStore.key
    /// MED-010: the logo's identifier and placement (written by LogoStore).
    static let logoIDKey = LogoStore.idKey
    static let logoPlacementKey = LogoStore.placementKey
    static let allKeys = [performanceOverlayKey, reduceFlashingKey, presetScopeKey, visualKey, circularSpectrumBarsKey,
                          glowKey, glowIntensityKey, glowRadiusKey, glowThresholdKey,
                          linearSpectrumOrientationKey, linearSpectrumSpacingKey, oscEnabledKey, oscPortKey, photoIDKey, slideshowKey, videoIDKey, videoLoopKey, videoSpeedKey,
                          textOverlayKey, oscilloscopeLineKey, oscilloscopeWindowKey, lissajousModeKey, lissajousPersistenceKey, radialWaveformRingKey, radialWaveformAmplitudeKey, beatRingsLifeKey, mandalaSymmetryKey, mandalaMirrorKey, mandalaPetalKey, spectrumAttackKey, spectrumReleaseKey,
                          cameraPositionKey, cameraMirrorFrontKey, cameraMirrorBackKey,
                          cameraCropModeKey, cameraCropAnchorKey, cameraZoomKey, cameraLensKey, midiEnabledKey,
                          colorBlindSafePaletteKey, logoIDKey, logoPlacementKey, SceneLock.key] + SensorySafetySetting.allKeys   // ACC-012-R8, MED-010, SCN-015
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

    /// CAM-003-R4: the back camera's chosen lens (wide by default). Never starts the camera.
    var cameraLens: CameraLens {
        didSet { defaults.set(cameraLens.rawValue, forKey: Self.cameraLensKey) }
    }

    /// CAM-002-R3: the front camera's mirror (on by default).
    var cameraMirrorFront: Bool {
        didSet { defaults.set(cameraMirrorFront, forKey: Self.cameraMirrorFrontKey) }
    }

    /// CAM-002-R3: the rear camera's mirror (off by default).
    var cameraMirrorBack: Bool {
        didSet { defaults.set(cameraMirrorBack, forKey: Self.cameraMirrorBackKey) }
    }

    /// CAM-007-R1: Fill (default) or Fit, for both cameras. Never starts the camera.
    var cameraCropMode: CameraCropMode {
        didSet { defaults.set(cameraCropMode.rawValue, forKey: Self.cameraCropModeKey) }
    }

    /// CAM-007-R1: the point of the picture a crop keeps (Center by default).
    var cameraCropAnchor: CameraCropAnchor {
        didSet { defaults.set(cameraCropAnchor.rawValue, forKey: Self.cameraCropAnchorKey) }
    }

    /// CAM-007-R1: 1, 1.5, 2 or 3 (1 by default); any other value is stored as its valid step.
    var cameraZoom: Double {
        didSet {
            let valid: Double = Double(CameraCrop.validZoom(Float(cameraZoom)))
            if valid != cameraZoom { cameraZoom = valid }   // inside didSet: no second didSet
            defaults.set(cameraZoom, forKey: Self.cameraZoomKey)
        }
    }

    /// CAM-007: the crop the camera layer draws with.
    var cameraCrop: CameraCrop {
        CameraCrop(mode: cameraCropMode, anchor: cameraCropAnchor, zoom: Float(cameraZoom))
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

    /// VIS-004: how the Lissajous plots the stereo pair (X/Y by default).
    var lissajousMode: LissajousMode {
        didSet { defaults.set(lissajousMode.rawValue, forKey: Self.lissajousModeKey) }
    }

    /// VIS-004: the Lissajous's persistence (off by default).
    var lissajousPersistence: Bool {
        didSet { defaults.set(lissajousPersistence, forKey: Self.lissajousPersistenceKey) }
    }

    /// VIS-005: the radial waveform's ring size (Medium by default).
    var radialWaveformRing: RadialWaveformRing {
        didSet { defaults.set(radialWaveformRing.rawValue, forKey: Self.radialWaveformRingKey) }
    }

    /// VIS-005: the radial waveform's amplitude (Medium by default).
    var radialWaveformAmplitude: RadialWaveformAmplitude {
        didSet { defaults.set(radialWaveformAmplitude.rawValue, forKey: Self.radialWaveformAmplitudeKey) }
    }

    /// VIS-006: how long a beat ring lasts (Medium by default).
    var beatRingsLife: BeatRingLife {
        didSet { defaults.set(beatRingsLife.rawValue, forKey: Self.beatRingsLifeKey) }
    }

    /// VIS-007: the mandala's rotational symmetry N (6 by default; only `MandalaConfiguration.supportedSymmetries`).
    var mandalaSymmetry: Int {
        didSet {
            if !MandalaConfiguration.supportedSymmetries.contains(mandalaSymmetry) { mandalaSymmetry = MandalaConfiguration.defaultSymmetry }
            defaults.set(mandalaSymmetry, forKey: Self.mandalaSymmetryKey)
        }
    }

    /// VIS-007: mirror within each sector (off by default).
    var mandalaMirror: Bool {
        didSet { defaults.set(mandalaMirror, forKey: Self.mandalaMirrorKey) }
    }

    /// VIS-007: the petal style (Petal by default).
    var mandalaPetal: MandalaPetalStyle {
        didSet { defaults.set(mandalaPetal.rawValue, forKey: Self.mandalaPetalKey) }
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

    /// ACC-003-R13: the native spectra's colour-blind-safe palette (Bool, absent → off).
    var colorBlindSafePalette: Bool {
        didSet { defaults.set(colorBlindSafePalette, forKey: Self.colorBlindSafePaletteKey) }
    }

    /// The palette the native spectra draw with (VIS-001's default, or ACC-003's colour-blind-safe ramp).
    var spectrumPalette: VisualPalette { colorBlindSafePalette ? .colorBlindSafe : .spectrum }

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

    /// MIDI-001: "Listen for MIDI devices" (off by default; MIDI-001-R8). The only MIDI value stored.
    var midiEnabled: Bool {
        didSet { defaults.set(midiEnabled, forKey: Self.midiEnabledKey) }
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

    /// ACC-012: the stored sensory safety profile.
    let sensorySafety: SensorySafetySetting
    /// SCN-015: the scene lock (key `settings.scene.locked`), shared by every holder of the settings.
    let sceneLock: SceneLock

    init(defaults: UserDefaults, systemReduceMotion: Bool) {
        self.defaults = defaults
        self.systemReduceMotion = systemReduceMotion
        sensorySafety = SensorySafetySetting(defaults: defaults)
        sceneLock = SceneLock(defaults: defaults)   // SCN-015
        showsPerformanceOverlay = defaults.bool(forKey: Self.performanceOverlayKey)
        reduceFlashingChoice = defaults.object(forKey: Self.reduceFlashingKey) as? Bool
        let storedVisual = defaults.string(forKey: Self.visualKey).flatMap(VisualChoice.init(rawValue:)) ?? .projectM
        visual = storedVisual.usesCamera ? .projectM : storedVisual   // CAM-001-R11
        cameraPosition = defaults.string(forKey: Self.cameraPositionKey).flatMap(CameraPosition.init(rawValue:)) ?? .back
        cameraLens = CameraLens(stored: defaults.string(forKey: Self.cameraLensKey))   // CAM-003
        cameraMirrorFront = defaults.object(forKey: Self.cameraMirrorFrontKey) as? Bool ?? CameraPosition.front.defaultMirrored
        cameraMirrorBack = defaults.object(forKey: Self.cameraMirrorBackKey) as? Bool ?? CameraPosition.back.defaultMirrored
        cameraCropMode = defaults.string(forKey: Self.cameraCropModeKey).flatMap(CameraCropMode.init(rawValue:)) ?? .fill   // CAM-007
        cameraCropAnchor = defaults.string(forKey: Self.cameraCropAnchorKey).flatMap(CameraCropAnchor.init(rawValue:)) ?? .center
        let storedZoom: Double = defaults.object(forKey: Self.cameraZoomKey) as? Double ?? 1
        cameraZoom = Double(CameraCrop.validZoom(Float(storedZoom)))
        let bars = defaults.integer(forKey: Self.circularSpectrumBarsKey)
        circularSpectrumBars = Self.circularSpectrumBarChoices.contains(bars) ? bars : Self.defaultCircularSpectrumBars
        linearSpectrumOrientation = defaults.string(forKey: Self.linearSpectrumOrientationKey)
            .flatMap(LinearSpectrumOrientation.init(rawValue:)) ?? .vertical
        let spacing = defaults.object(forKey: Self.linearSpectrumSpacingKey) as? Double
        linearSpectrumSpacing = spacing.map(Self.isSpacingChoice) == true ? spacing! : Self.defaultLinearSpectrumSpacing
        oscilloscopeLine = defaults.string(forKey: Self.oscilloscopeLineKey).flatMap(OscilloscopeLine.init(rawValue:)) ?? .medium
        let window = defaults.integer(forKey: Self.oscilloscopeWindowKey)
        oscilloscopeWindowMilliseconds = Self.oscilloscopeWindowChoices.contains(window) ? window : Self.defaultOscilloscopeWindow
        lissajousMode = defaults.string(forKey: Self.lissajousModeKey).flatMap(LissajousMode.init(rawValue:)) ?? .xy   // VIS-004
        lissajousPersistence = defaults.bool(forKey: Self.lissajousPersistenceKey)
        radialWaveformRing = defaults.string(forKey: Self.radialWaveformRingKey).flatMap(RadialWaveformRing.init(rawValue:)) ?? .medium   // VIS-005
        radialWaveformAmplitude = defaults.string(forKey: Self.radialWaveformAmplitudeKey).flatMap(RadialWaveformAmplitude.init(rawValue:)) ?? .medium
        beatRingsLife = defaults.string(forKey: Self.beatRingsLifeKey).flatMap(BeatRingLife.init(rawValue:)) ?? .medium   // VIS-006
        let symmetry: Int = (defaults.object(forKey: Self.mandalaSymmetryKey) as? Int) ?? MandalaConfiguration.defaultSymmetry   // VIS-007
        mandalaSymmetry = MandalaConfiguration.supportedSymmetries.contains(symmetry) ? symmetry : MandalaConfiguration.defaultSymmetry
        mandalaMirror = defaults.bool(forKey: Self.mandalaMirrorKey)
        mandalaPetal = defaults.string(forKey: Self.mandalaPetalKey).flatMap(MandalaPetalStyle.init(rawValue:)) ?? .petal
        let attack = defaults.integer(forKey: Self.spectrumAttackKey)
        spectrumAttackMilliseconds = Self.spectrumAttackChoices.contains(attack) ? attack : 0
        let release = defaults.integer(forKey: Self.spectrumReleaseKey)
        spectrumReleaseMilliseconds = Self.spectrumReleaseChoices.contains(release) ? release : 0
        glowEnabled = defaults.bool(forKey: Self.glowKey)
        colorBlindSafePalette = defaults.bool(forKey: Self.colorBlindSafePaletteKey)   // ACC-003-R13
        oscEnabled = defaults.bool(forKey: Self.oscEnabledKey)
        midiEnabled = defaults.bool(forKey: Self.midiEnabledKey)
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

    /// ACC-012-R4, R7: the one clamp every frame resolver applies: the profile raised by the effective
    /// Reduce flashing setting (stricter wins per limit).
    var safetyClamp: SafetyClamp {
        SafetyClamp(profile: sensorySafety.profile, reduceFlashingSetting: reduceFlashing)
    }

    /// ACC-012-R7: what everything Reduce flashing governs follows (bar slew, ACC-002's policy, the restore
    /// fade): the setting, or a profile whose flash limit is stricter than Standard's. Never written back.
    var effectiveReduceFlashing: Bool { safetyClamp.reducesFlashing }

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
    /// The native Lissajous scope (VIS-004).
    case lissajous
    /// The native radial waveform (VIS-005).
    case radialWaveform
    /// The native beat pulse rings (VIS-006).
    case beatRings
    /// The native mandala (VIS-007).
    case mandala
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
        case .lissajous: "Lissajous"
        case .radialWaveform: "Radial Waveform"
        case .beatRings: "Beat Rings"
        case .mandala: "Mandala"
        case .camera: "Camera"
        case .photo: "Photo"
        case .video: "Video"
        case .text: "Text"
        }
    }

    /// Drawn by the native spectrum host instead of projectM.
    var isNative: Bool { self == .circularSpectrum || self == .linearSpectrum || self == .oscilloscope || self == .lissajous
        || self == .radialWaveform || self == .beatRings || self == .mandala }

    /// The native visual draws frequency bars, so Bars applies (not the oscilloscope or the Lissajous).
    var usesBars: Bool { self == .circularSpectrum || self == .linearSpectrum }

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

extension LissajousMode {
    /// Settings and VoiceOver (VIS-004-R11, R14).
    var title: String {
        switch self {
        case .xy: "X/Y"
        case .midSide: "Mid/Side"
        }
    }
}

/// VIS-005-R6: the radial waveform's ring size; `value` is R₀ as a fraction of half the shorter side.
enum RadialWaveformRing: String, CaseIterable, Sendable {
    case small, medium, large

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var value: Double {
        switch self {
        case .small: 0.40
        case .medium: 0.55
        case .large: 0.70
        }
    }
}

/// VIS-005-R6: how far the waveform moves the ring; `value` is A as a fraction of half the shorter side.
enum RadialWaveformAmplitude: String, CaseIterable, Sendable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var value: Double {
        switch self {
        case .low: 0.10
        case .medium: 0.18
        case .high: 0.25
        }
    }
}

/// VIS-006-R9: how long a beat ring lasts; `seconds` is its life L.
enum BeatRingLife: String, CaseIterable, Sendable {
    case short, medium, long

    var title: String {
        switch self {
        case .short: "Short"
        case .medium: "Medium"
        case .long: "Long"
        }
    }

    var seconds: Double {
        switch self {
        case .short: 1.0
        case .medium: 1.5
        case .long: 2.5
        }
    }
}

/// VIS-007-R9: the petal style's Settings and VoiceOver title.
extension MandalaPetalStyle {
    var title: String {
        switch self {
        case .petal: "Petal"
        case .round: "Round"
        case .spike: "Spike"
        }
    }
}
