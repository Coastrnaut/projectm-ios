// RecordingQualityProfile.swift — REC-005 record quality profiles (spec specs/150-rec-005-quality-profiles,
// contracts/quality-profiles.md C1, research REC-005-D1). Plain Swift; builds on Linux.
//
// | Profile  | Long side at most | Codec            | Average bit rate                 | Frame rate |
// |----------|-------------------|------------------|----------------------------------|------------|
// | Draft    | 1280 (720p)       | H.264            | 4 Mb/s                           | 30 fps     |
// | Standard | 1920 (1080p)      | HEVC, else H.264 | REC-003 rule (≈7.5 Mb/s 1080p30) | 30 fps     |
// | High     | 2560 (1440p)      | HEVC             | 20 Mb/s                          | 60 fps     |
// | Max      | the screen        | HEVC             | 40 Mb/s                          | 60 fps     |
//
// Standard is `RecordingSettings.standard` exactly (REC-005-R3). No profile upscales (REC-005-R2): the
// geometry only scales down to the cap.

/// A documented recording quality (REC-005-R1). The raw value is what Settings stores.
public enum RecordingQualityProfile: String, Sendable, CaseIterable, Equatable {
    case draft
    case standard
    case high
    case max

    /// The default (today's settings).
    public static let defaultProfile = RecordingQualityProfile.standard

    /// Best first: the order a Record fallback walks down (REC-005-D5).
    public static let fallbackOrder: [RecordingQualityProfile] = [.max, .high, .standard, .draft]

    public var title: String {
        switch self {
        case .draft: "Draft"
        case .standard: "Standard"
        case .high: "High"
        case .max: "Max"
        }
    }

    /// The long-side cap; nil for Max (the drawable's own size).
    public var maxLongSide: Int? {
        switch self {
        case .draft: 1280
        case .standard: 1920
        case .high: 2560
        case .max: nil
        }
    }

    public var codecPreference: [RecordingCodec] {
        switch self {
        case .draft: [.h264]
        case .standard: [.hevc, .h264]
        case .high, .max: [.hevc]
        }
    }

    /// The fixed average bit rate in bits per second; nil for Standard (REC-003's per-pixel rule).
    public var fixedBitRate: Int? {
        switch self {
        case .draft: 4_000_000
        case .standard: nil
        case .high: 20_000_000
        case .max: 40_000_000
        }
    }

    public var frameRate: Int {
        switch self {
        case .draft, .standard: 30
        case .high, .max: 60
        }
    }

    /// The recorder settings of this profile (Standard: `RecordingSettings.standard`).
    public var settings: RecordingSettings {
        if self == .standard { return .standard }
        return RecordingSettings(maxFrameRate: frameRate, maxLongSide: maxLongSide ?? RecordingSettings.nativeLongSide,
                                 codecPreference: codecPreference, fixedBitRate: fixedBitRate)
    }

    /// REC-006-R1, R12: the profile's settings at `frameRate` (nil: the profile's own rate). Only the rate
    /// changes; Standard's per-pixel bit rate follows it, fixed bit rates stay.
    public func settings(frameRate: Int?) -> RecordingSettings {
        var result: RecordingSettings = settings
        if let frameRate, frameRate != result.maxFrameRate {
            result.maxFrameRate = Swift.min(Swift.max(frameRate, 1), 60)
        }
        return result
    }

    /// The documented row of the profile table: "Up to 1280 px · H.264 · 4 Mb/s · 30 fps".
    public var documentation: String {
        let size: String = maxLongSide.map { (side: Int) -> String in "Up to \(side) px" } ?? "Screen size"
        let codec: String = codecPreference.map { (c: RecordingCodec) -> String in c.title }.joined(separator: " or ")
        let rate: String = fixedBitRate.map { (bits: Int) -> String in Self.megabits(bits) } ?? "about 7.5 Mb/s at 1080p"
        return "\(size) · \(codec) · \(rate) · \(frameRate) fps"
    }

    /// "4 Mb/s", "7.5 Mb/s".
    public static func megabits(_ bits: Int) -> String {
        let tenths: Int = (bits + 50_000) / 100_000
        return tenths % 10 == 0 ? "\(tenths / 10) Mb/s" : "\(tenths / 10).\(tenths % 10) Mb/s"
    }
}
