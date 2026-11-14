// RecordingFrameRate.swift — REC-006 record frame rate: the choice, which rates are available and how Record
// resolves them (spec specs/164-rec-006-record-frame-rate, contracts/frame-rate.md C3, C4, research
// REC-006-D4, D5). Plain Swift; builds on Linux.

/// The user's frame-rate choice (REC-006-R1). The raw value is what Settings stores.
public enum RecordingFrameRateChoice: String, Sendable, CaseIterable, Equatable {
    case profileDefault = "profile"
    case fps24 = "24"
    case fps30 = "30"
    case fps60 = "60"

    public static let defaultChoice = RecordingFrameRateChoice.profileDefault
    /// The export targets, lowest first.
    public static let supportedRates: [Int] = [24, 30, 60]

    /// The explicit rate, nil for Profile default.
    public var rate: Int? {
        switch self {
        case .profileDefault: nil
        case .fps24: 24
        case .fps30: 30
        case .fps60: 60
        }
    }

    /// The choice of an explicit rate (nil when it is not 24, 30 or 60).
    public init?(rate: Int) {
        switch rate {
        case 24: self = .fps24
        case 30: self = .fps30
        case 60: self = .fps60
        default: return nil
        }
    }

    /// "Profile default (30 fps)", "24 fps".
    public func title(profileRate: Int) -> String {
        switch self {
        case .profileDefault: "Profile default (\(profileRate) fps)"
        default: "\(rate ?? profileRate) fps"
        }
    }
}

/// Why the render loop runs below the display's rate (REC-006-D4; the app's QualityGovernor).
public struct RecordingRenderLimit: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case lowPowerMode
        case thermal
        /// PERF-008-R8: the user's Battery saver power profile.
        case batterySaver
    }

    public let reason: Reason
    public let maximumFramesPerSecond: Int

    public init(reason: Reason, maximumFramesPerSecond: Int = 30) {
        self.reason = reason
        self.maximumFramesPerSecond = max(maximumFramesPerSecond, 1)
    }
}

/// Why a rate cannot be recorded here (REC-006-R6). The texts are shown and spoken as they are.
public enum RecordingFrameRateUnavailableReason: Sendable, Equatable {
    case displayLimit(maximum: Int)
    case renderLimit(RecordingRenderLimit)
    case encoderLimit(maximum: Int, width: Int, height: Int)

    public var text: String {
        switch self {
        case .displayLimit(let maximum):
            "This display shows at most \(maximum) fps."
        case .renderLimit(let limit):
            switch limit.reason {
            case .lowPowerMode: "Low Power Mode limits the visual to \(limit.maximumFramesPerSecond) fps."
            case .thermal: "The device is too warm; the visual is limited to \(limit.maximumFramesPerSecond) fps."
            case .batterySaver: "Battery saver limits the visual to \(limit.maximumFramesPerSecond) fps."
            }
        case .encoderLimit(let maximum, let width, let height):
            "This device encodes at most \(maximum) fps at \(width)×\(height)."
        }
    }
}

public enum RecordingFrameRateAvailability: Sendable, Equatable {
    case available
    case unavailable(RecordingFrameRateUnavailableReason)

    public var isAvailable: Bool { self == .available }

    public var reason: RecordingFrameRateUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// What Record does (REC-006-R7): REC-005's profile resolution with the effective rate, plus the rate
/// fallback when the rate was lowered.
public struct RecordingRecordResolution: Sendable, Equatable {
    /// REC-005's resolution; its plan's settings carry the effective rate.
    public let profile: RecordingProfileResolution
    /// The rate actually recorded and why it is lower than asked (nil when not lowered).
    public let rateFallback: (rate: Int, reason: RecordingFrameRateUnavailableReason)?

    public static func == (a: RecordingRecordResolution, b: RecordingRecordResolution) -> Bool {
        a.profile == b.profile && a.rateFallback?.rate == b.rateFallback?.rate && a.rateFallback?.reason == b.rateFallback?.reason
    }

    /// The plan to record with (nil: refuse).
    public var plan: RecordingProfilePlan? {
        if case .record(let plan, _, _) = profile { return plan }
        return nil
    }

    /// The profile notice, then the rate notice, joined by a space (nil without a fallback). Both start with
    /// "Recording at ", so the status router shows them as row X9c.
    public var notice: String? {
        let rateNotice: String? = rateFallback.map { (f: (rate: Int, reason: RecordingFrameRateUnavailableReason)) -> String in
            RecordingFrameRateCatalog.fallbackNotice(rate: f.rate, reason: f.reason)
        }
        let parts: [String] = [profile.fallbackNotice, rateNotice].compactMap { (s: String?) -> String? in s }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

public enum RecordingFrameRateCatalog {
    /// "Recording at 30 fps: Low Power Mode limits the visual to 30 fps."
    public static func fallbackNotice(rate: Int, reason: RecordingFrameRateUnavailableReason) -> String {
        RecordingQualityCatalog.fallbackPrefix + "\(rate) fps: " + reason.text
    }

    /// Contract C3: display, then render cap, then (with a codec and size) the encoder's rate limit.
    public static func availability(rate: Int, codec: RecordingCodec? = nil, width: Int = 0, height: Int = 0,
                                    capabilities: any RecordingEncoderCapabilities) -> RecordingFrameRateAvailability {
        if rate > capabilities.maxFramesPerSecond { return .unavailable(.displayLimit(maximum: capabilities.maxFramesPerSecond)) }
        if let limit = capabilities.renderLimit, rate > limit.maximumFramesPerSecond { return .unavailable(.renderLimit(limit)) }
        if let codec, width > 0, height > 0 {
            let maximum: Int = capabilities.maxEncodedFramesPerSecond(codec, width: width, height: height)
            if rate > maximum { return .unavailable(.encoderLimit(maximum: maximum, width: width, height: height)) }
        }
        return .available
    }

    /// The row of `choice` for the selected profile on this drawable: Profile default is always selectable
    /// (REC-005 decides its availability); an explicit rate is checked against the display, the render cap and
    /// the encoder limit at the profile's planned codec and size.
    public static func availability(of choice: RecordingFrameRateChoice, profile: RecordingQualityProfile,
                                    drawableWidth: Int, drawableHeight: Int,
                                    capabilities: any RecordingEncoderCapabilities) -> RecordingFrameRateAvailability {
        guard let rate = choice.rate else { return .available }
        let base = availability(rate: rate, capabilities: capabilities)
        guard base.isAvailable else { return base }
        let plan: RecordingProfilePlan? = RecordingQualityCatalog.availability(of: profile, frameRate: rate, drawableWidth: drawableWidth,
                                                                                drawableHeight: drawableHeight, capabilities: capabilities).plan
        guard let plan else { return .available }
        return availability(rate: rate, codec: plan.codec, width: plan.geometry.outputWidth, height: plan.geometry.outputHeight,
                            capabilities: capabilities)
    }

    /// The highest supported rate at most `ceiling` that passes `isAllowed`.
    static func highestRate(atMost ceiling: Int, where isAllowed: (Int) -> Bool) -> Int? {
        RecordingFrameRateChoice.supportedRates.reversed().first { (r: Int) -> Bool in r <= ceiling && isAllowed(r) }
    }

    /// Contract C4: the explicit rate's fallback (display, render cap), REC-005's profile resolution at that
    /// rate, then the render cap (Profile default) and the encoder limit of the plan's codec and size.
    public static func resolve(profile: RecordingQualityProfile, choice: RecordingFrameRateChoice,
                               drawableWidth: Int, drawableHeight: Int,
                               capabilities: any RecordingEncoderCapabilities) -> RecordingRecordResolution {
        var fallback: (rate: Int, reason: RecordingFrameRateUnavailableReason)?
        var explicit: Int? = choice.rate
        if let asked = explicit, let reason = availability(rate: asked, capabilities: capabilities).reason {
            let lower: Int = highestRate(atMost: asked) { (r: Int) -> Bool in availability(rate: r, capabilities: capabilities).isAvailable }
                ?? RecordingFrameRateChoice.supportedRates[0]
            explicit = lower
            fallback = (lower, reason)
        }
        let resolution = RecordingQualityCatalog.resolve(profile, frameRate: explicit, drawableWidth: drawableWidth,
                                                         drawableHeight: drawableHeight, capabilities: capabilities)
        guard case .record(let plan, let from, let profileReason) = resolution else {
            return RecordingRecordResolution(profile: resolution, rateFallback: nil)
        }
        let codec: RecordingCodec = plan.codec
        let width: Int = plan.geometry.outputWidth, height: Int = plan.geometry.outputHeight
        let rate: Int = plan.settings.maxFrameRate
        // The display limit is REC-005's (profile fallback) for Profile default, and already met for an explicit rate.
        let allowed: (Int) -> Bool = { (r: Int) -> Bool in
            let a = availability(rate: r, codec: codec, width: width, height: height, capabilities: capabilities)
            if case .unavailable(.displayLimit) = a { return true }
            return a.isAvailable
        }
        guard !allowed(rate), let reason = availability(rate: rate, codec: codec, width: width, height: height,
                                                         capabilities: capabilities).reason else {
            return RecordingRecordResolution(profile: resolution, rateFallback: fallback)
        }
        let lower: Int = highestRate(atMost: rate, where: allowed) ?? RecordingFrameRateChoice.supportedRates[0]
        var settings: RecordingSettings = plan.settings
        settings.maxFrameRate = lower
        let lowered = RecordingProfilePlan(profile: plan.profile, geometry: plan.geometry, codec: codec, settings: settings)
        return RecordingRecordResolution(profile: .record(lowered, fallbackFrom: from, reason: profileReason),
                                         rateFallback: (lower, reason))
    }
}
