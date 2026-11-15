// DisplayCalibration.swift — OUT-009 (specs/268-out-009-output-color-calibration, contract C1; research OUT-009-D3):
// the external display's colour calibration: gamma and red, green and blue trims, its transfer function and its
// stored form. CPU only, builds on Linux. The compositor's `cmp_output_calibrated` and projectM's CFlashLimiter
// output pass apply the same function in float; tests compare them with `apply(encoded:)`.
//
// Per channel, on the display-encoded (sRGB) value e in 0…1 of the finished frame (after the flash envelope):
//   e' = clamp(trim × e^(1/gamma), 0, 1). Alpha is unchanged. The identity (gamma 1, trims 1) is a bypass.
// Gamma follows FX-003's convention: above 1 brightens mid-tones.
import Foundation

/// The calibration of the external output (OUT-009-R1). Values are clamped to their ranges on every init.
public struct DisplayCalibration: Sendable, Equatable, Hashable {
    public private(set) var gamma: Double
    public private(set) var red: Double
    public private(set) var green: Double
    public private(set) var blue: Double

    public static let gammaRange: ClosedRange<Double> = 0.5...2.5
    public static let trimRange: ClosedRange<Double> = 0.5...1.5
    /// The slider step of every value.
    public static let step: Double = 0.01
    public static let identity = DisplayCalibration(gamma: 1, red: 1, green: 1, blue: 1)

    public init(gamma: Double, red: Double, green: Double, blue: Double) {
        self.gamma = Self.clamp(gamma, Self.gammaRange, fallback: 1)
        self.red = Self.clamp(red, Self.trimRange, fallback: 1)
        self.green = Self.clamp(green, Self.trimRange, fallback: 1)
        self.blue = Self.clamp(blue, Self.trimRange, fallback: 1)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    public var isIdentity: Bool { self == .identity }

    /// The exponent applied to the encoded value (1 / gamma).
    public var exponent: Double { 1 / gamma }

    /// The three trims (red, green, blue).
    public var trims: SIMD3<Double> { SIMD3<Double>(red, green, blue) }

    /// Copies with one value changed (clamped).
    public func with(gamma value: Double) -> DisplayCalibration { DisplayCalibration(gamma: value, red: red, green: green, blue: blue) }
    public func with(red value: Double) -> DisplayCalibration { DisplayCalibration(gamma: gamma, red: value, green: green, blue: blue) }
    public func with(green value: Double) -> DisplayCalibration { DisplayCalibration(gamma: gamma, red: red, green: value, blue: blue) }
    public func with(blue value: Double) -> DisplayCalibration { DisplayCalibration(gamma: gamma, red: red, green: green, blue: value) }

    /// The transfer function for one channel (0 red, 1 green, 2 blue) on an encoded value; the identity returns
    /// `e` unchanged (also outside 0…1); otherwise the input is clamped to 0…1 first.
    public func apply(encoded e: Double, channel: Int) -> Double {
        if isIdentity { return e }
        let x: Double = e.isFinite ? min(max(e, 0), 1) : 0
        let trim: Double = channel == 0 ? red : (channel == 1 ? green : blue)
        let curved: Double = x > 0 ? pow(x, exponent) : 0
        let scaled: Double = trim * curved
        return min(max(scaled, 0), 1)
    }

    public func apply(encoded c: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(apply(encoded: c.x, channel: 0), apply(encoded: c.y, channel: 1), apply(encoded: c.z, channel: 2))
    }

    // MARK: - Stored form (OUT-009-R9)

    /// "gamma,red,green,blue" with up to 4 decimals (the slider step is 0.01).
    public var stored: String {
        [gamma, red, green, blue].map { (v: Double) -> String in Self.format(v) }.joined(separator: ",")
    }

    /// Four finite comma-separated numbers (clamped); anything else is nil.
    public init?(stored: String) {
        let parts: [Substring] = stored.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var values: [Double] = []
        for part in parts {
            let text = String(part).trimmingCharacters(in: .whitespaces)
            guard let value = Double(text), value.isFinite else { return nil }
            values.append(value)
        }
        self.init(gamma: values[0], red: values[1], green: values[2], blue: values[3])
    }

    private static func format(_ value: Double) -> String {
        let rounded: Double = (value * 10_000).rounded() / 10_000
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }
}

/// OUT-009 (contract C1): a visual's view whose renderer can apply a display calibration in its final pass.
/// `VisualSlotView` sets the calibration on external slots and the identity on the device slot.
@MainActor
public protocol DisplayCalibrationReceiver: AnyObject {
    var displayCalibration: DisplayCalibration { get set }
    /// False when the visual shown by this view has no pass that applies it (OUT-009-R3: not covered).
    var acceptsDisplayCalibration: Bool { get }
}
