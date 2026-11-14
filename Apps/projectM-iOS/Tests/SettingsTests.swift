// Task T103: settings defaults and persistence (FR-048, FR-072, FR-065) and the bundled license
// manifest (FR-067).
import XCTest
@testable import projectM_iOS

@MainActor
final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "SettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testPerformanceOverlayIsOffByDefaultAndPersists() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertFalse(settings.showsPerformanceOverlay, "FR-048: off by default")
        settings.showsPerformanceOverlay = true
        XCTAssertTrue(AppSettings(defaults: defaults, systemReduceMotion: false).showsPerformanceOverlay)
    }

    func testReduceFlashingFollowsReduceMotionUntilChosen() {
        XCTAssertFalse(AppSettings(defaults: defaults, systemReduceMotion: false).reduceFlashing)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: true)
        XCTAssertTrue(settings.reduceFlashing, "FR-072: on by default with Reduce Motion")
        XCTAssertTrue(settings.reduceFlashingFollowsSystem)
        settings.systemReduceMotion = false
        XCTAssertFalse(settings.reduceFlashing, "still following the system")

        settings.reduceFlashing = true
        settings.systemReduceMotion = false
        XCTAssertTrue(settings.reduceFlashing, "the user's choice wins")
        XCTAssertTrue(AppSettings(defaults: defaults, systemReduceMotion: false).reduceFlashing, "persisted")

        settings.followSystemForReduceFlashing()
        XCTAssertFalse(settings.reduceFlashing)
        XCTAssertNil(defaults.object(forKey: AppSettings.reduceFlashingKey))
    }

    func testOnlyTheSettingsKeysAreWritten() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.showsPerformanceOverlay = true
        settings.reduceFlashing = true
        settings.presetScope = "all"
        settings.visual = .circularSpectrum
        settings.circularSpectrumBars = 32
        settings.glowEnabled = true            // FX-001-R11
        settings.glowIntensity = 0.8
        settings.glowRadius = 0.03
        settings.glowThreshold = 0.5
        settings.linearSpectrumOrientation = .horizontal   // VIS-002-R11
        settings.linearSpectrumSpacing = 0.5
        settings.oscilloscopeLine = .thick     // VIS-003-R10
        settings.oscilloscopeWindowMilliseconds = 40
        settings.lissajousMode = .midSide      // VIS-004-R11
        settings.lissajousPersistence = true
        settings.radialWaveformRing = .small   // VIS-005-R9
        settings.radialWaveformAmplitude = .high
        settings.beatRingsLife = .long         // VIS-006-R9
        settings.mandalaSymmetry = 8           // VIS-007-R9
        settings.mandalaMirror = true
        settings.mandalaPetal = .spike
        settings.particleGravity = .low        // VIS-008-R10
        settings.particleOrbitRadius = .large  // VIS-009-R10
        settings.spectrumAttackMilliseconds = 25    // ANL-003-R6
        settings.spectrumReleaseMilliseconds = 250
        settings.oscEnabled = true             // OSC-001-R15
        settings.oscPort = 8000
        settings.midiEnabled = true            // MIDI-001-R8
        settings.cameraPosition = .front       // CAM-002-R6
        settings.cameraMirrorFront = false
        settings.cameraMirrorBack = true
        settings.cameraCropMode = .fit         // CAM-007-R6
        settings.cameraCropAnchor = .top
        settings.cameraZoom = 2
        settings.colorBlindSafePalette = true  // ACC-003-R13
        settings.sensorySafety.preset = .custom   // ACC-012-R8: the profile and its three custom keys
        settings.sceneLock.lock()              // SCN-015-R1
        let keys = Set(defaults.persistentDomain(forName: suite)?.keys ?? [:].keys)
        // MED-001, MED-002, MED-003, MED-004, MED-009: `settings.photo.id`, `settings.video.id`,
        // `settings.video.loop`, `settings.video.speed` and `settings.text.overlay` are in allKeys (the UI-test
        // reset) but written by PhotoStore, VideoStore and TextOverlayStore only.
        XCTAssertEqual(keys, Set(AppSettings.allKeys).subtracting([AppSettings.photoIDKey, AppSettings.videoIDKey,
                                                                   AppSettings.videoLoopKey, AppSettings.videoSpeedKey,
                                                                   AppSettings.textOverlayKey,
                                                                   AppSettings.slideshowKey,   // MED-006: SlideshowStore
                                                                   AppSettings.logoIDKey, AppSettings.logoPlacementKey]), "FR-065")   // MED-010: LogoStore
    }

    /// VIS-001-T19 (VIS-001-R11): the visual choice and the bar count, with safe readings of bad values.
    func testVisualChoiceDefaultsToProjectMAndPersists() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.visual, .projectM, "projectM stays the default")
        settings.visual = .circularSpectrum
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "circularSpectrum")
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .circularSpectrum, "persisted")
        defaults.set("kaleidoscope", forKey: AppSettings.visualKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).visual, .projectM, "unknown → projectM")
    }

    func testCircularSpectrumBarsDefaultTo64AndPersist() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.circularSpectrumBars, 64)
        settings.circularSpectrumBars = 16
        XCTAssertEqual(defaults.integer(forKey: "settings.circularSpectrum.bars"), 16)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).circularSpectrumBars, 16)
        defaults.set(24, forKey: AppSettings.circularSpectrumBarsKey)
        XCTAssertEqual(AppSettings(defaults: defaults, systemReduceMotion: false).circularSpectrumBars, 64, "not a band count → 64")
        XCTAssertTrue(AppSettings.allKeys.contains("settings.visual"))
        XCTAssertTrue(AppSettings.allKeys.contains("settings.circularSpectrum.bars"))
    }

    /// VIS-002-T11 (VIS-002-R11): the third visual, its orientation and spacing, with safe readings.
    func testLinearSpectrumOptionsDefaultPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(settings.linearSpectrumOrientation, .vertical, "vertical by default")
        XCTAssertEqual(settings.linearSpectrumSpacing, 0.2, "Narrow by default")
        XCTAssertEqual(AppSettings.linearSpectrumSpacingChoices.map(\.value), [0, 0.2, 0.5])
        XCTAssertEqual(AppSettings.linearSpectrumSpacingChoices.map(\.title), ["None", "Narrow", "Wide"])
        settings.visual = .linearSpectrum
        settings.linearSpectrumOrientation = .horizontal
        settings.linearSpectrumSpacing = 0.5
        XCTAssertEqual(defaults.string(forKey: "settings.visual"), "linearSpectrum")
        XCTAssertEqual(defaults.string(forKey: "settings.linearSpectrum.orientation"), "horizontal")
        XCTAssertEqual(defaults.double(forKey: "settings.linearSpectrum.spacing"), 0.5)
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reloaded.visual, .linearSpectrum)
        XCTAssertEqual(reloaded.linearSpectrumOrientation, .horizontal)
        XCTAssertEqual(reloaded.linearSpectrumSpacing, 0.5)
        settings.linearSpectrumSpacing = 0.7
        XCTAssertEqual(settings.linearSpectrumSpacing, 0.2, "not a choice → Narrow")
        defaults.set("diagonal", forKey: AppSettings.linearSpectrumOrientationKey)
        defaults.set(0.33, forKey: AppSettings.linearSpectrumSpacingKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.linearSpectrumOrientation, .vertical, "unknown → vertical")
        XCTAssertEqual(bad.linearSpectrumSpacing, 0.2, "unknown → Narrow")
        XCTAssertTrue(AppSettings.allKeys.contains("settings.linearSpectrum.orientation"))
        XCTAssertTrue(AppSettings.allKeys.contains("settings.linearSpectrum.spacing"))
        XCTAssertEqual(VisualChoice.allCases.filter(\.isNative), [.circularSpectrum, .linearSpectrum, .oscilloscope, .lissajous, .radialWaveform, .beatRings, .mandala, .particleFountain, .particleOrbit])   // VIS-003, VIS-004, VIS-005, VIS-006, VIS-007, VIS-008, VIS-009
        XCTAssertEqual(VisualChoice.linearSpectrum.title, "Linear Spectrum")
    }

    /// OSC-001-T16 (OSC-001-R1, R15): off by default (a fresh install opens no listener), port 9000,
    /// both persisted; an invalid stored or assigned port reads as 9000.
    func testOSCReceiverDefaultsPersistAndReadSafely() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertFalse(settings.oscEnabled)
        XCTAssertEqual(settings.oscPort, 9000)
        settings.oscEnabled = true
        settings.oscPort = 8000
        var reread = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertTrue(reread.oscEnabled)
        XCTAssertEqual(reread.oscPort, 8000)
        reread.oscPort = 80
        XCTAssertEqual(reread.oscPort, 9000)
        defaults.set(70000, forKey: AppSettings.oscPortKey)
        reread = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(reread.oscPort, 9000)
    }

    func testTheBundledLicenseManifestIsComplete() throws {
        let catalog = try XCTUnwrap(LicenseCatalog.bundled(Bundle(for: AppSettings.self)) ?? LicenseCatalog.bundled())
        let ids = Set(catalog.components.map(\.id))
        for required in ["app", "projectm", "glad", "glm", "hlslparser", "projectm-eval", "stb_image", "angle-ANGLE", "presets"] {
            XCTAssertTrue(ids.contains(required), required)
        }
        for component in catalog.components {
            XCTAssertNotEqual(LicenseCatalog.text(of: component), "License text missing.", component.id)
        }
        XCTAssertTrue(catalog.lgplNote.text.contains("github.com/Coastrnaut/projectm"))
        let engine = try XCTUnwrap(catalog.components.first { $0.id == "projectm" })
        XCTAssertTrue(LicenseCatalog.text(of: engine).contains("GNU LESSER GENERAL PUBLIC LICENSE"))
    }

    /// FX-001-T17 (FX-001-R4, R11): the glow settings, their defaults, persistence and safe readings.
    func testGlowSettingsDefaultPersistAndClamp() {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertFalse(settings.glowEnabled, "Glow is off by default")
        XCTAssertEqual(settings.glowIntensity, 0.5, accuracy: 1e-6)
        XCTAssertEqual(settings.glowRadius, 0.02, accuracy: 1e-6)
        XCTAssertEqual(settings.glowThreshold, 0.7, accuracy: 1e-6)
        XCTAssertTrue(settings.glowParameters.isPassThrough)

        settings.glowEnabled = true
        settings.glowIntensity = 0.9
        settings.glowRadius = 0.05
        settings.glowThreshold = 0.4
        XCTAssertTrue(defaults.bool(forKey: "settings.circularSpectrum.glow"))
        XCTAssertEqual(defaults.double(forKey: "settings.circularSpectrum.glowIntensity"), 0.9, accuracy: 1e-6)
        XCTAssertEqual(defaults.double(forKey: "settings.circularSpectrum.glowRadius"), 0.05, accuracy: 1e-6)
        XCTAssertEqual(defaults.double(forKey: "settings.circularSpectrum.glowThreshold"), 0.4, accuracy: 1e-6)
        let reloaded = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertTrue(reloaded.glowEnabled)
        let p = reloaded.glowParameters
        XCTAssertTrue(p.enabled)
        XCTAssertEqual(p.intensity, 0.9, accuracy: 1e-6)
        XCTAssertEqual(p.radius, 0.05, accuracy: 1e-6)
        XCTAssertEqual(p.threshold, 0.4, accuracy: 1e-6)
        XCTAssertEqual(p.knee, 0.5, accuracy: 1e-6, "the knee is not a setting")

        // Out of range and NaN.
        settings.glowIntensity = 7
        XCTAssertEqual(settings.glowIntensity, 1, accuracy: 1e-6)
        settings.glowRadius = -1
        XCTAssertEqual(settings.glowRadius, 0.005, accuracy: 1e-6)
        defaults.set(Double.nan, forKey: AppSettings.glowThresholdKey)
        defaults.set(42.0, forKey: AppSettings.glowRadiusKey)
        defaults.set("x", forKey: AppSettings.glowIntensityKey)
        let bad = AppSettings(defaults: defaults, systemReduceMotion: false)
        XCTAssertEqual(bad.glowThreshold, 0.7, accuracy: 1e-6, "NaN reads the default")
        XCTAssertEqual(bad.glowRadius, 0.06, accuracy: 1e-6, "clamped")
        XCTAssertEqual(bad.glowIntensity, 0.5, accuracy: 1e-6, "not a number reads the default")

        for key in ["settings.circularSpectrum.glow", "settings.circularSpectrum.glowIntensity",
                    "settings.circularSpectrum.glowRadius", "settings.circularSpectrum.glowThreshold"] {
            XCTAssertTrue(AppSettings.allKeys.contains(key), key)
        }
    }
}
