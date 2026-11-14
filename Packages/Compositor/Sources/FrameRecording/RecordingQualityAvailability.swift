// RecordingQualityAvailability.swift — REC-005 which profiles this device and screen can record
// (contracts/quality-profiles.md C2, research REC-005-D2, D3, D5). Plain Swift; builds on Linux. The real
// capability source is `VideoToolboxEncoderCapabilities` (Apple only); tests inject their own.

/// What the device can encode and show (REC-005-R4).
public protocol RecordingEncoderCapabilities: Sendable {
    /// True when an encoder for `codec` exists at `width × height`.
    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool
    /// The display's highest frame rate.
    var maxFramesPerSecond: Int { get }
}

/// Why a profile cannot record here (REC-005-R5). The texts are shown and spoken as they are.
public enum RecordingUnavailableReason: Sendable, Equatable {
    case hevcUnavailable
    case sizeUnsupported(width: Int, height: Int)
    case frameRateUnsupported(maximum: Int)
    case noPicture

    public var text: String {
        switch self {
        case .hevcUnavailable: "Needs HEVC, which this device cannot encode."
        case .sizeUnsupported(let width, let height): "This device cannot encode \(width)×\(height)."
        case .frameRateUnsupported(let maximum): "Needs 60 fps; this display shows at most \(maximum)."
        case .noPicture: "No picture to record."
        }
    }
}

/// An available profile: what it will encode on this drawable.
public struct RecordingProfilePlan: Sendable, Equatable {
    public let profile: RecordingQualityProfile
    public let geometry: RecordingGeometry
    /// The codec the writer will use (the first encodable one of the profile's preference).
    public let codec: RecordingCodec
    public let settings: RecordingSettings

    /// The average bit rate of the planned file (bits per second).
    public var averageBitRate: Int {
        settings.averageBitRate(codec: codec, width: geometry.outputWidth, height: geometry.outputHeight)
    }

    /// "1178×2560 · HEVC · 20 Mb/s · 60 fps" (the row's detail line).
    public var summary: String {
        let size: String = "\(geometry.outputWidth)×\(geometry.outputHeight)"
        let rate: String = RecordingQualityProfile.megabits(averageBitRate)
        return "\(size) · \(codec.title) · \(rate) · \(settings.maxFrameRate) fps"
    }
}

public enum RecordingProfileAvailability: Sendable, Equatable {
    case available(RecordingProfilePlan)
    case unavailable(RecordingUnavailableReason)

    public var plan: RecordingProfilePlan? {
        if case .available(let plan) = self { return plan }
        return nil
    }

    public var reason: RecordingUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// What Record does with the selected profile (REC-005-R6).
public enum RecordingProfileResolution: Sendable, Equatable {
    /// Record with `plan`; `fallbackFrom` and `reason` are set when the selected profile was unavailable.
    case record(RecordingProfilePlan, fallbackFrom: RecordingQualityProfile?, reason: RecordingUnavailableReason?)
    /// No profile can record here.
    case refuse

    /// "Recording at Standard: Needs HEVC, which this device cannot encode." (nil without a fallback).
    public var fallbackNotice: String? {
        guard case .record(let plan, let from, let reason) = self, from != nil, let reason else { return nil }
        return RecordingQualityCatalog.fallbackNotice(profile: plan.profile, reason: reason)
    }
}

public enum RecordingQualityCatalog {
    /// The size used to tell "no HEVC at all" from "not at this size" (REC-005-D2).
    static let probeWidth = 1280
    static let probeHeight = 720

    /// The fallback notice's prefix (status row X9c classifies notices by it).
    public static let fallbackPrefix = "Recording at "

    public static func fallbackNotice(profile: RecordingQualityProfile, reason: RecordingUnavailableReason) -> String {
        fallbackPrefix + profile.title + ": " + reason.text
    }

    /// Contract C2: frame rate, then codec, then size.
    public static func availability(of profile: RecordingQualityProfile, drawableWidth: Int, drawableHeight: Int,
                                    capabilities: any RecordingEncoderCapabilities) -> RecordingProfileAvailability {
        let settings: RecordingSettings = profile.settings
        guard let geometry = RecordingGeometry(drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                               maxLongSide: settings.maxLongSide) else { return .unavailable(.noPicture) }
        if settings.maxFrameRate > capabilities.maxFramesPerSecond {
            return .unavailable(.frameRateUnsupported(maximum: capabilities.maxFramesPerSecond))
        }
        let width: Int = geometry.outputWidth, height: Int = geometry.outputHeight
        if let codec = settings.codecPreference.first(where: { (c: RecordingCodec) -> Bool in
            capabilities.canEncode(c, width: width, height: height)
        }) {
            return .available(RecordingProfilePlan(profile: profile, geometry: geometry, codec: codec, settings: settings))
        }
        let hevcOnly: Bool = settings.codecPreference == [.hevc]
        if hevcOnly && !capabilities.canEncode(.hevc, width: probeWidth, height: probeHeight) {
            return .unavailable(.hevcUnavailable)
        }
        return .unavailable(.sizeUnsupported(width: width, height: height))
    }

    /// Every profile's availability, in table order (the Settings rows).
    public static func availabilities(drawableWidth: Int, drawableHeight: Int,
                                      capabilities: any RecordingEncoderCapabilities)
        -> [(profile: RecordingQualityProfile, availability: RecordingProfileAvailability)] {
        RecordingQualityProfile.allCases.map { (p: RecordingQualityProfile) -> (profile: RecordingQualityProfile, availability: RecordingProfileAvailability) in
            (p, availability(of: p, drawableWidth: drawableWidth, drawableHeight: drawableHeight, capabilities: capabilities))
        }
    }

    /// The selected profile when available, else the first available one below it (REC-005-D5), else refuse.
    public static func resolve(_ selected: RecordingQualityProfile, drawableWidth: Int, drawableHeight: Int,
                               capabilities: any RecordingEncoderCapabilities) -> RecordingProfileResolution {
        let first = availability(of: selected, drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                 capabilities: capabilities)
        if let plan = first.plan { return .record(plan, fallbackFrom: nil, reason: nil) }
        let order: [RecordingQualityProfile] = RecordingQualityProfile.fallbackOrder
        guard let start = order.firstIndex(of: selected) else { return .refuse }
        for profile in order[(start + 1)...] {
            let candidate = availability(of: profile, drawableWidth: drawableWidth, drawableHeight: drawableHeight,
                                         capabilities: capabilities)
            if let plan = candidate.plan { return .record(plan, fallbackFrom: selected, reason: first.reason) }
        }
        return .refuse
    }
}
