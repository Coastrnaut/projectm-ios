// SafetyClamp.swift — the one clamp every frame's parameters pass through (ACC-012-R4 to R7;
// contracts/safety-clamp.md C1; ADR-0045).
//
// Built on the main actor whenever the profile or the effective Reduce flashing setting changes, then
// copied (a small value) to each frame resolver: native glow after MOD-002 modulation, the native
// generators' frame context, projectM's envelope pass, the compositor's flash guards and graph speed.
//
// Precedence (ACC-012-R7, research R4): per limit the stricter value wins. The effective Reduce flashing
// setting (the stored choice, else the system Reduce Motion setting) floors the flash part at Reduced's;
// it never touches the intensity limit (ACC-001-R5). A flash part stricter than Standard turns
// `reducesFlashing` on, so everything Reduce flashing governs follows.
//
// Standard bit identity (ACC-012-R6): `flashLimitsOverride` is nil whenever the configuration equals
// `FlashEnvelopeConfiguration.forReduceFlashing(reducesFlashing)`, and every cap returns its input
// unchanged at intensity limit 1, so no arithmetic touches a Standard value.
// Real-time safety: plain value, no allocation; every function is a few comparisons.

public struct SafetyClamp: Sendable, Equatable {
    /// Standard with Reduce flashing off: today's app.
    public static let standard = SafetyClamp(profile: .standard, reduceFlashingSetting: false)

    /// The effective limits after precedence.
    public let limits: SensorySafetyLimits
    /// Everything Reduce flashing governs is on (bar slew, ACC-002's policy, the restore fade).
    public let reducesFlashing: Bool

    public init(profile: SensorySafetyProfile, reduceFlashingSetting: Bool) {
        let requested: SensorySafetyLimits = profile.limits
        if reduceFlashingSetting {
            let floor: SensorySafetyLimits = requested.withFlash(of: .reduced)
            limits = requested.stricter(than: floor)
        } else {
            limits = requested
        }
        reducesFlashing = reduceFlashingSetting || limits.limitsFlashMoreThanStandard
    }

    /// FX-019's envelope for these limits.
    public var flashConfiguration: FlashEnvelopeConfiguration { limits.flashConfiguration }

    /// What a renderer is handed: nil when its own `forReduceFlashing(reducesFlashing)` is already this
    /// configuration (Standard and Reduced), so the existing code path runs unchanged.
    public var flashLimitsOverride: FlashEnvelopeConfiguration? {
        let configuration: FlashEnvelopeConfiguration = flashConfiguration
        return configuration == FlashEnvelopeConfiguration.forReduceFlashing(reducesFlashing) ? nil : configuration
    }

    /// No intensity cap applies.
    public var capsIntensity: Bool { limits.intensityLimit < 1 }

    /// Standard limits with Reduce flashing off.
    public var isIdentity: Bool { self == Self.standard }

    /// An intensity-type value capped at `limit × maximum`; unchanged at limit 1 (NaN passes through to the
    /// parameter's own sanitizing).
    public func intensity(_ value: Float, maximum: Float) -> Float {
        guard capsIntensity, !value.isNaN else { return value }
        let cap: Float = maximum * Float(limits.intensityLimit)
        return min(value, cap)
    }

    /// A binding's effective value with its excursion from the manual value scaled by the limit
    /// (research R5); unchanged at limit 1. The target's own cap is applied after this.
    public func modulated(manual: Double, modulated: Double) -> Double {
        guard capsIntensity, modulated.isFinite, manual.isFinite else { return modulated }
        let excursion: Double = modulated - manual
        return manual + excursion * limits.intensityLimit
    }

    /// A speed-type value whose magnitude is at most `limit × cap`; unchanged at limit 1.
    public func speed(_ value: Double, cap: Double) -> Double {
        guard capsIntensity, value.isFinite, cap.isFinite else { return value }
        let bound: Double = abs(cap) * limits.intensityLimit
        return min(max(value, -bound), bound)
    }
}
