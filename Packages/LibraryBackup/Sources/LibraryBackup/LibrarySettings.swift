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

    public static let includedKeys: [String] = [
        favoritesKey, lastPresetKey,
        "settings.performanceOverlay", "settings.reduceFlashing", "settings.presetScope", "settings.visual",
        "settings.circularSpectrum.bars", "settings.circularSpectrum.glow", "settings.circularSpectrum.glowIntensity",
        "settings.circularSpectrum.glowRadius", "settings.circularSpectrum.glowThreshold",
        "settings.linearSpectrum.orientation", "settings.linearSpectrum.spacing",
        "settings.visual.colorBlindSafePalette",   // ACC-003-R13 (integrated alongside FILE-005)
        "settings.sensorySafety.profile", "settings.sensorySafety.flashesPerSecond",   // ACC-012-R8
        "settings.sensorySafety.riseLimit", "settings.sensorySafety.intensityLimit",
        "settings.colorGrade.temperature", "settings.colorGrade.lift", "settings.colorGrade.gamma",   // FX-003-R8
        "settings.colorGrade.gain", "settings.colorGrade.saturation", "settings.colorGrade.hue",   // FX-004-R8
        "settings.feedback.enabled", "settings.feedback.halfLife",   // FX-009-R11: Trails
        "settings.oscilloscope.line", "settings.oscilloscope.window",
        "settings.spectrum.attack", "settings.spectrum.release",
        "settings.camera.position", "settings.camera.mirrorFront", "settings.camera.mirrorBack",
        "settings.camera.cropMode", "settings.camera.cropAnchor", "settings.camera.zoom",
        "settings.osc.port",
        "settings.midi.mappings",   // MIDI-003-R9: channel, controller and parameter ID per line; erased with Settings
        "settings.inputTrim.decibels", "settings.analysisChannel.mode",
        "settings.noiseGate.enabled", "settings.noiseGate.thresholdDecibels",
        "settings.latencyOffset.microphone", "settings.latencyOffset.inAppPlayback", "settings.latencyOffset.systemAppCapture",
        photoKey, slideshowKey, "settings.text.overlay",
        logoKey, logoPlacementKey,   // MED-010
    ]

    /// Read by the app but deliberately left out (documented; a test checks none is included).
    public static let excludedKeys: [String] = [
        "settings.osc.enabled", "settings.midi.enabled", "settings.video.id", "settings.video.loop", "settings.video.speed",
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
