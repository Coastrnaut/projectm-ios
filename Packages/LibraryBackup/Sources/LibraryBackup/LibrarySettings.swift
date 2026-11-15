// LibrarySettings.swift — FILE-005 (research FILE-005-D6): the settings a backup carries, as typed
// values. The app reads them from UserDefaults (and writes them back); this package only knows the
// key names, so it stays Foundation-only and testable on Linux.
import Foundation

/// One setting's value, typed as UserDefaults stores it.
public enum LibrarySettingValue: Sendable, Hashable, Codable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])
    case data(Data)

    private enum CodingKeys: String, CodingKey { case type, value }

    public var typeName: String {
        switch self {
        case .bool: "bool"
        case .int: "int"
        case .double: "double"
        case .string: "string"
        case .strings: "strings"
        case .data: "data"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "bool": self = .bool(try container.decode(Bool.self, forKey: .value))
        case "int": self = .int(try container.decode(Int.self, forKey: .value))
        case "double": self = .double(try container.decode(Double.self, forKey: .value))
        case "string": self = .string(try container.decode(String.self, forKey: .value))
        case "strings": self = .strings(try container.decode([String].self, forKey: .value))
        case "data": self = .data(try container.decode(Data.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "unknown setting type")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case let .bool(value): try container.encode(value, forKey: .value)
        case let .int(value): try container.encode(value, forKey: .value)
        case let .double(value): try container.encode(value, forKey: .value)
        case let .string(value): try container.encode(value, forKey: .value)
        case let .strings(value): try container.encode(value, forKey: .value)
        case let .data(value): try container.encode(value, forKey: .value)
        }
    }

    /// Sorted-key JSON (the logical record's encoding).
    public var canonicalBytes: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// Which UserDefaults keys a backup carries (spec Baseline). Device switches (OSC on, MIDI on),
/// notices, permission explanations, session recovery, the guide, the video, its loop region and its
/// playback speed (MED-004) are never read.
public enum LibrarySettingsPolicy {
    public static let favoritesKey = "favorites"
    public static let lastPresetKey = "lastPresetID"
    public static let photoKey = "settings.photo.id"
    /// MED-006-R10: the image slideshow (order and timing); its pictures are photos of the folder.
    public static let slideshowKey = "settings.photo.slideshow"
    /// MED-010-R9: the logo overlay's picture (a reference in the photo folder) and its placement.
    public static let logoKey = "settings.logo.id"
    public static let logoPlacementKey = "settings.logo.placement"
    /// PRE-006-R7: the recently played preset IDs: personal usage data, never backed up or restored
    /// (excluded), erased with "Collections, tags, favorites and history".
    public static let recentPresetsKey = "recentPresets"
    /// PRE-006-R3: "Remember Recently Played" (a preference: backed up, erased with Settings).
    public static let recentPresetsEnabledKey = "settings.recentPresets.enabled"

    public static let includedKeys: [String] = [
        favoritesKey, lastPresetKey,
        "settings.performanceOverlay", "settings.reduceFlashing", "settings.presetScope", "settings.visual",
        "settings.circularSpectrum.bars", "settings.circularSpectrum.glow", "settings.circularSpectrum.glowIntensity",
        "settings.circularSpectrum.glowRadius", "settings.circularSpectrum.glowThreshold",
        "settings.linearSpectrum.orientation", "settings.linearSpectrum.spacing",
        "settings.visual.colorBlindSafePalette",   // ACC-003-R13 (integrated alongside FILE-005)
        "settings.sensorySafety.profile", "settings.sensorySafety.flashesPerSecond",   // ACC-012-R8
        "settings.sensorySafety.riseLimit", "settings.sensorySafety.intensityLimit",
        "settings.haptics.beatPulses", "settings.haptics.beatEvent", "settings.haptics.strength",   // ACC-007-R8
        "settings.motion.range",   // CAM-011-R12: Settings › Motion range (calibration is never stored)
        "settings.colorGrade.temperature", "settings.colorGrade.lift", "settings.colorGrade.gamma",   // FX-003-R8
        "settings.colorGrade.gain", "settings.colorGrade.saturation", "settings.colorGrade.hue",   // FX-004-R8
        "settings.colorGrade.contrast", "settings.colorGrade.contrastStrength",   // FX-005-R8
        "settings.colorGrade.posterize", "settings.colorGrade.posterizeLevels",   // FX-013-R8
        "settings.colorGrade.posterizeDither",   // FX-013-R8
        "settings.feedback.enabled", "settings.feedback.halfLife",   // FX-009-R11: Trails
        "settings.noiseEditor.values",   // SHD-006-R7: the Noise editor's values
        "settings.colorGrade.enabled", "settings.effectChain.order", "settings.effectChain.presets",   // FX-020-R8, R10
        "settings.chromatic.enabled", "settings.chromatic.amount", "settings.chromatic.angle", "settings.chromatic.radial",   // FX-006-R9
        "settings.directionalBlur.enabled", "settings.directionalBlur.radius", "settings.directionalBlur.angle",   // FX-007-R10
        "settings.radialBlur.enabled", "settings.radialBlur.strength", "settings.radialBlur.centerX", "settings.radialBlur.centerY",   // FX-008-R9
        "settings.echo.enabled", "settings.echo.count", "settings.echo.delay", "settings.echo.decay",   // FX-010-R13
        "settings.mosaic.enabled", "settings.mosaic.size", "settings.mosaic.shape",   // FX-012-R9
        "settings.edgeOutline.enabled", "settings.edgeOutline.threshold", "settings.edgeOutline.width",   // FX-014-R10
        "settings.edgeOutline.color", "settings.edgeOutline.mode",
        "settings.vignette.enabled", "settings.vignette.intensity", "settings.vignette.softness",   // FX-015-R9
        "settings.vignette.centerX", "settings.vignette.centerY",
        "settings.oscilloscope.line", "settings.oscilloscope.window",
        "settings.lissajous.mode", "settings.lissajous.persistence",   // VIS-004-R11
        "settings.radialWaveform.ring", "settings.radialWaveform.amplitude",   // VIS-005-R9
        "settings.beatRings.life",   // VIS-006-R9
        "settings.mandala.symmetry", "settings.mandala.mirror", "settings.mandala.petal",   // VIS-007-R9
        "settings.particleFountain.gravity",   // VIS-008-R10
        "settings.particleFountain.emitter",   // SHD-007-R8: the Particle emitter editor (absent at defaults)
        "settings.particleOrbit.radius",   // VIS-009-R10
        "settings.particleTrails",   // VIS-010-R9
        "settings.noiseField.frequency", "settings.noiseField.octaves", "settings.noiseField.seed",   // VIS-013-R9
        "settings.kaleidoscope.wedges",   // VIS-014-R9
        "settings.tunnel.pace",   // VIS-015-R9
        "settings.reactionDiffusion.preset",   // VIS-012-R13
        "settings.reactionDiffusion.pattern",
        "settings.reactionDiffusion.seed",
        "settings.reactionDiffusion.speed",
        "settings.starfield.speed", "settings.starfield.density",   // VIS-016-R8
        "settings.signedDistance.quality",   // VIS-017-R8
        "settings.spectrum.attack", "settings.spectrum.release",
        "settings.camera.position", "settings.camera.mirrorFront", "settings.camera.mirrorBack",
        "settings.camera.cropMode", "settings.camera.cropAnchor", "settings.camera.zoom", "settings.camera.lens", "settings.camera.personMask",
        "settings.osc.port",
        "settings.osc.disabledRoutes", "settings.osc.aliases",   // OSC-003-R9: route addresses and parameter IDs only
        "settings.midi.mappings",   // MIDI-003-R9: channel, controller and parameter ID per line; erased with Settings
        "settings.parameterShelf.pins",   // UIX-004-R10: ordered pinned parameter IDs; erased with Settings
        "settings.inputTrim.decibels", "settings.analysisChannel.mode",
        "settings.playbackBalance.position",   // AUD-010-R7: the In-App Playback monitoring balance
        "settings.noiseGate.enabled", "settings.noiseGate.thresholdDecibels",
        "settings.latencyOffset.microphone", "settings.latencyOffset.inAppPlayback", "settings.latencyOffset.systemAppCapture",
        photoKey, slideshowKey, "settings.text.overlay",
        "settings.photo.kenBurns",   // MED-007-R9: a preference (the photo's pan and zoom); erased with Settings
        logoKey, logoPlacementKey,   // MED-010
        "settings.clock.overlay",   // MED-011-R9: a preference (shown, format, placement); erased with Settings
        "settings.countdown.overlay",   // MED-012-R10: a preference (shown, duration, cues, placement); erased with Settings
        recentPresetsEnabledKey,   // PRE-006-R7
        "settings.recording.countdown",   // REC-007-R8: a preference (off, 3, 5, 10); erased with Settings
        "settings.visualizer.sceneHUD",   // UIX-013-R11: a preference (Bool); erased with Settings
        "settings.gestures.shortcuts",   // UIX-006-R9: a preference (JSON: switch and mapping); erased with Settings
        "settings.visualizer.guides", "settings.visualizer.guides.actionSafe",   // OUT-005-R6: preferences; erased with Settings
        "settings.visualizer.guides.titleSafe", "settings.visualizer.guides.centreCross",
        "settings.controls.oneHanded",   // ACC-009-R9: a preference ("left"/"right"); erased with Settings
        "settings.controls.leftHanded",   // ACC-010-R7: a preference (Bool); erased with Settings
        "settings.recording.timedStop",   // REC-008-R9: a preference (off, 10, 30, 60, 300); erased with Settings
        "settings.performance.powerProfile",   // PERF-008-R6: a preference (standard, followLowPowerMode, batterySaver)
    ]

    /// Read by the app but deliberately left out (documented; a test checks none is included).
    public static let excludedKeys: [String] = [
        "settings.osc.enabled", "settings.midi.enabled",
        "settings.midi.followClock",   // MIDI-010-R6: this device's MIDI setup (Follow MIDI clock), like Listen for MIDI
        "settings.scene.locked",   // SCN-015: a performance lock is session state of this device
        "settings.osc.peerAllowlist.enabled", "settings.osc.approvedPeers",   // OSC-008-R10: this device's network only
        "settings.osc.send.enabled", "settings.osc.send.host", "settings.osc.send.port",   // OSC-005-R12: this device's
        "settings.osc.send.kinds", "settings.osc.send.sceneNames",                         // network output setup
        "settings.osc.discovery.browse", "settings.osc.discovery.advertise",   // OSC-011-R10: this device's network
        "settings.osc.cueSync.role",   // OSC-012-R12: this device's network role (lead or follow a peer)
        "settings.modulation.quantize",   // MOD-017: a performance timing choice of this device
        "settings.show.quantizeCues",   // SHOW-003: a performance timing choice of this device
        "settings.show.loop",   // SHOW-007: a performance choice of this device (Loop the show timeline)
        "settings.show.rotation",   // SHOW-013: a performance choice of this device (auto scene rotation)
        "settings.recording.includeMicrophone",   // REC-004-R3: a consent never travels to another device
        "settings.camera.faceTracking", "settings.camera.faceTrackingConsent",   // CAM-009-R3: likewise (face tracking)
        "settings.camera.handTracking", "settings.camera.handTrackingConsent",   // CAM-010-R3: likewise (hand tracking)
        "settings.recording.qualityProfile",   // REC-005-R7: depends on this device's encoder and screen
        "settings.recording.frameRate",   // REC-006-R8: depends on this device's display and encoder
        "settings.recording.aspect", "settings.recording.customWidth",   // REC-014-R7: sizes depend on this device's
        "settings.recording.customHeight",                               // screen and memory class
        "settings.externalDisplay.fit", "settings.externalDisplay.shape",   // OUT-004-R8: the user's display hardware
        "settings.externalDisplay.pixelAspect",
        "settings.externalDisplay.resolution", "settings.externalDisplay.resolutionPercent",   // OUT-003-R7: likewise
        "settings.externalDisplay.outputMode",   // OUT-006-R7: likewise
        "settings.externalDisplay.cornerPin",   // OUT-007-R9: likewise (one projector's geometry)
        "settings.externalDisplay.calibration",   // OUT-009-R9: likewise (one display's colour response)
        "settings.splitEditor.width",   // UIX-007-R7: the iPad split editor width depends on this device's screen
        "settings.video.id", "settings.video.loop", "settings.video.speed", "settings.video.reverse",   // MED-005
        recentPresetsKey,   // PRE-006-R7: recently played history stays on this device
        "notice.photosensitivityAcknowledged", "permission.explained.camera", "permission.explained.localNetwork",
        "session.recovery.open", "session.recovery.heldVisual", "session.recovery.sessionsSinceReopen", "guide.firstScene",
    ]

    static let includedSet: Set<String> = Set(includedKeys)

    public static func isIncluded(_ key: String) -> Bool { includedSet.contains(key) }

    /// Only the included keys of `settings`.
    public static func filtered(_ settings: [String: LibrarySettingValue]) -> [String: LibrarySettingValue] {
        settings.filter { (entry: (key: String, value: LibrarySettingValue)) -> Bool in includedSet.contains(entry.key) }
    }
}
