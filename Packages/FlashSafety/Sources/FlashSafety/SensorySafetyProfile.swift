// SensorySafetyProfile.swift — the viewer's sensory safety limits (ACC-012-R1 to R3; spec
// specs/121-acc-012-sensory-safety-profile, data-model.md; ADR-0045).
//
// * Flash: FX-019's own envelope knobs, never a second limiter. "Flashes per second" f ∈ 1…3 is the
//   envelope's transition budget 2f per 1 s window; the rise limit is its `riseRatePerSecond` (nil = none).
// * Intensity: one 0…1 limit on glow intensity, binding excursions and speed-type parameters
//   (`SafetyClamp`). 1.0 changes nothing.
// * Presets: Standard = today's app (`FlashEnvelopeConfiguration.alwaysOn`, no intensity cap); Reduced =
//   today's Reduce flashing envelope (`.reduceFlashing`) plus intensity 0.5; Strict = 1 flash per second,
//   0.10/s rise, intensity 0.25. Custom values are clamped so they are never looser than Standard.
// Haptics: the app has no haptic output (ACC-012-R9), so there is no haptics limit to store.
// Plain Swift; builds and is tested on Linux.

/// The profiles offered in Settings. Raw values are stored (`settings.sensorySafety.profile`).
public enum SensorySafetyPreset: String, CaseIterable, Sendable, Codable {
    case standard
    case reduced
    case strict
    case custom

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .reduced: "Reduced"
        case .strict: "Strict"
        case .custom: "Custom"
        }
    }
}

/// One set of limits. Every initializer clamps its inputs (data-model.md).
public struct SensorySafetyLimits: Sendable, Equatable, Codable {
    public static let flashesRange: ClosedRange<Int> = 1...3
    public static let riseRange: ClosedRange<Double> = 0.05...1.0
    public static let intensityRange: ClosedRange<Double> = 0...1

    /// At most this many flashes (two opposing transitions each) in any 1 s window, 1…3.
    public let flashesPerSecond: Int
    /// The largest rise of any area's signal per second; nil = no rate limit.
    public let riseLimitPerSecond: Double?
    /// 0…1 cap on intensity-type parameters; 1 = no cap.
    public let intensityLimit: Double

    public init(flashesPerSecond: Int, riseLimitPerSecond: Double?, intensityLimit: Double) {
        self.flashesPerSecond = min(max(flashesPerSecond, Self.flashesRange.lowerBound), Self.flashesRange.upperBound)
        if let rise = riseLimitPerSecond, rise.isFinite, rise > 0 {
            self.riseLimitPerSecond = min(max(rise, Self.riseRange.lowerBound), Self.riseRange.upperBound)
        } else {
            self.riseLimitPerSecond = nil
        }
        self.intensityLimit = intensityLimit.isNaN ? 1 : min(max(intensityLimit, 0), 1)
    }

    public static let standard = SensorySafetyLimits(flashesPerSecond: 3, riseLimitPerSecond: nil, intensityLimit: 1)
    public static let reduced = SensorySafetyLimits(flashesPerSecond: 2, riseLimitPerSecond: 0.25, intensityLimit: 0.5)
    public static let strict = SensorySafetyLimits(flashesPerSecond: 1, riseLimitPerSecond: 0.10, intensityLimit: 0.25)

    /// FX-019's configuration for these limits (thresholds, window and margins unchanged).
    public var flashConfiguration: FlashEnvelopeConfiguration {
        FlashEnvelopeConfiguration(transitionBudget: 2 * flashesPerSecond, riseRatePerSecond: riseLimitPerSecond)
    }

    /// The rise limit with "none" as +∞ (for comparisons).
    var riseOrInfinity: Double { riseLimitPerSecond ?? .infinity }

    /// The flash part is stricter than Standard's (fewer flashes or any rise limit).
    public var limitsFlashMoreThanStandard: Bool {
        flashesPerSecond < Self.standard.flashesPerSecond || riseLimitPerSecond != nil
    }

    /// Per limit, the stricter of the two (fewer flashes, lower rise, lower intensity).
    public func stricter(than other: SensorySafetyLimits) -> SensorySafetyLimits {
        let rise: Double = min(riseOrInfinity, other.riseOrInfinity)
        return SensorySafetyLimits(flashesPerSecond: min(flashesPerSecond, other.flashesPerSecond),
                                   riseLimitPerSecond: rise.isFinite ? rise : nil,
                                   intensityLimit: min(intensityLimit, other.intensityLimit))
    }

    /// The flash part of `other` with this intensity limit.
    public func withFlash(of other: SensorySafetyLimits) -> SensorySafetyLimits {
        SensorySafetyLimits(flashesPerSecond: other.flashesPerSecond, riseLimitPerSecond: other.riseLimitPerSecond,
                            intensityLimit: intensityLimit)
    }
}

/// The chosen preset and the stored custom limits.
public struct SensorySafetyProfile: Sendable, Equatable, Codable {
    public var preset: SensorySafetyPreset
    public var custom: SensorySafetyLimits

    public init(preset: SensorySafetyPreset = .standard, custom: SensorySafetyLimits = .reduced) {
        self.preset = preset
        self.custom = custom
    }

    public static let standard = SensorySafetyProfile()

    /// The limits of a fixed preset (Custom reads `custom`).
    public static func limits(of preset: SensorySafetyPreset, custom: SensorySafetyLimits) -> SensorySafetyLimits {
        switch preset {
        case .standard: .standard
        case .reduced: .reduced
        case .strict: .strict
        case .custom: custom
        }
    }

    /// The limits this profile asks for, before the system settings raise them.
    public var limits: SensorySafetyLimits { Self.limits(of: preset, custom: custom) }
}
