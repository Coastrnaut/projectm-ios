// FlashEnvelopeConfiguration.swift — the limits of the strobe safety envelope (FX-019-R2, R3, R7,
// R8, R14; ADR-0011; research FX-019-D1, D7).
//
// Basis: W3C WCAG 2.x SC 2.3.1 "Three Flashes or Below Threshold" and its definition of the general
// flash and red flash thresholds (a pair of opposing changes in relative luminance of 10 % or more of
// the maximum relative luminance; red: a change of (R − G − B) × 320 greater than 20; no more than
// three flashes in any one-second period); ITU-R BT.1702 and the Ofcom guidance use the same limits.
// The app is stricter (ADR-0011 decision 1): no darker-state exemption, no red saturation
// condition, and with Reduce flashing on at most two flashes per second and a rise rate.

/// The two signals the envelope limits in every area (FX-019-R3).
public enum FlashSignal: Int, CaseIterable, Sendable {
    /// WCAG relative luminance (sRGB-decoded, 0.2126 R + 0.7152 G + 0.0722 B).
    case luminance = 0
    /// max(R − G − B, 0) on linear channels (WCAG's red-flash working definition).
    case redness = 1
}

/// Mean levels of one area.
public struct FlashLevels: Sendable, Equatable {
    public var luminance: Double
    public var redness: Double

    public init(luminance: Double, redness: Double) {
        self.luminance = luminance
        self.redness = redness
    }

    public static let zero = FlashLevels(luminance: 0, redness: 0)

    public subscript(signal: FlashSignal) -> Double {
        get { signal == .luminance ? luminance : redness }
        set { if signal == .luminance { luminance = newValue } else { redness = newValue } }
    }
}

/// The areas (FX-019-R4, research FX-019-D3): tiles 0…15 of a 4 × 4 grid (row-major, row 0 at the
/// top of the picture) and the whole frame.
public enum FlashZones {
    public static let gridSide = 4
    public static let tileCount = 16
    public static let wholeFrame = 16
    public static let count = 17
}

public struct FlashEnvelopeConfiguration: Sendable, Equatable {
    public static let minTransitionBudget = 2
    /// The state holds this many transition ages per area and signal.
    public static let maxTransitionBudget = 6

    /// Length of the sliding window in seconds (WCAG: "any one-second period").
    public var window: Double
    /// Opposing change of relative luminance that makes a transition (WCAG: 10 % of 1.0).
    public var luminanceThreshold: Double
    /// Opposing change of redness that makes a transition (WCAG: 20 / 320).
    public var rednessThreshold: Double
    private var budget: Int
    /// Most transitions allowed in any window, per area and signal; clamped to 2…6.
    public var transitionBudget: Int {
        get { budget }
        set { budget = min(max(newValue, Self.minTransitionBudget), Self.maxTransitionBudget) }
    }
    /// Largest rise of any area's signal per second of frame time; nil = no rate limit.
    public var riseRatePerSecond: Double?
    /// A held rise stays this far below the threshold (absorbs 8-bit rounding on the GPU path).
    public var gateMargin: Double
    /// Frame times are clamped to 0…this, so a stall never opens the window early.
    public var maxFrameTime: Double

    public init(window: Double = 1, luminanceThreshold: Double = 0.10, rednessThreshold: Double = 20.0 / 320.0,
                transitionBudget: Int, riseRatePerSecond: Double?, gateMargin: Double = 0.005, maxFrameTime: Double = 0.1) {
        self.window = window
        self.luminanceThreshold = luminanceThreshold
        self.rednessThreshold = rednessThreshold
        budget = min(max(transitionBudget, Self.minTransitionBudget), Self.maxTransitionBudget)
        self.riseRatePerSecond = riseRatePerSecond
        self.gateMargin = gateMargin
        self.maxFrameTime = maxFrameTime
    }

    /// Reduce flashing on (FR-072, FX-019-R8): at most 4 transitions (2 flashes) per window and a
    /// rise of at most 0.25 per second (VIS-001-R10's constant).
    public static let reduceFlashing = FlashEnvelopeConfiguration(transitionBudget: 4, riseRatePerSecond: 0.25)
    /// Reduce flashing off (FX-019-R7): the guideline's own limit, 6 transitions (3 flashes) per
    /// window, no rate limit.
    public static let alwaysOn = FlashEnvelopeConfiguration(transitionBudget: 6, riseRatePerSecond: nil)

    public static func forReduceFlashing(_ on: Bool) -> FlashEnvelopeConfiguration {
        on ? reduceFlashing : alwaysOn
    }

    @inlinable
    public func threshold(for signal: FlashSignal) -> Double {
        signal == .luminance ? luminanceThreshold : rednessThreshold
    }

    /// 0…`maxFrameTime`; NaN and negative values are 0.
    @inlinable
    public func clampedFrameTime(_ t: Double) -> Double {
        t > 0 ? min(t, maxFrameTime) : 0
    }
}
