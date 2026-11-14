// MIDIMappingOptions.swift — a MIDI binding's curve and inversion, their stored `;` segments and the 0…1
// position a control value gives (MIDI-004-R1 to R5; specs/140-midi-004-cc-scaling, research MIDI-004-D1 to
// D4, contract C1, C2).
//
// Pure Swift, Linux-testable, allocation-free on the value path.
// * Position: value / 127 clamped to 0…1 (non-finite → 0), then 1 − position when inverted, then the MOD-004
//   curve. Inverting before the curve makes inverted(v) equal normal(127 − v): the knob runs the other way and
//   the curve keeps its shape relative to the parameter (research D1). Both ends are exact for every curve.
// * Stored segments after the parameter ID: `curve=<MOD-004 text form>` (only when not linear, or unreadable
//   text that is kept), `invert=1` (only when inverted), then unknown segments verbatim in their original
//   order. A default binding writes no segment, so its line is exactly MIDI-003's (research D2).
// * Unreadable curve text (does not parse, or fails MOD-004 validation) acts as linear, is kept verbatim and
//   flagged for the MIDI Mappings screen (research D3).
import ParameterGraph

/// The four curves the options screen offers (research MIDI-004-D4).
public enum MIDICurvePreset: String, Sendable, Hashable, CaseIterable {
    case linear, easeIn, easeOut, logarithmic

    public var curve: MappingCurve {
        switch self {
        case .linear: .linear
        case .easeIn: .easeIn(exponent: 2)
        case .easeOut: .easeOut(exponent: 2)
        case .logarithmic: .logarithmic(strength: 9)
        }
    }

    /// "Ease in"
    public var title: String {
        switch self {
        case .linear: "Linear"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .logarithmic: "Logarithmic"
        }
    }

    /// The preset whose curve equals `curve`; nil for any other curve ("Custom").
    public static func preset(for curve: MappingCurve) -> MIDICurvePreset? {
        if curve.isLinear { return .linear }
        return allCases.first { (preset: MIDICurvePreset) -> Bool in preset.curve == curve }
    }
}

public struct MIDIMappingOptions: Sendable, Hashable {
    public static let curveKey: String = "curve"
    public static let invertKey: String = "invert"

    /// Always valid (an unreadable stored curve reads `.linear`).
    public private(set) var curve: MappingCurve
    public var inverted: Bool
    /// The stored text after `curve=` when it could not be used; written back unchanged.
    public private(set) var unreadableCurveText: String?
    /// Unknown `;` segments, verbatim, in order.
    public private(set) var extraSegments: [String]

    public static let `default` = MIDIMappingOptions()

    public init(curve: MappingCurve = .linear, inverted: Bool = false) {
        self.curve = curve.isValid ? curve : .linear
        self.inverted = inverted
        self.unreadableCurveText = nil
        self.extraSegments = []
    }

    /// Reads the segments after the parameter ID (research D2): empty segments are skipped, the first
    /// `curve=` and the first `invert=` are used and later repeats dropped, anything else is kept.
    public init<S: Sequence>(segments: S) where S.Element: StringProtocol {
        self.init()
        var sawCurve: Bool = false
        var sawInvert: Bool = false
        for raw in segments {
            let segment: String = String(raw)
            if segment.isEmpty { continue }
            let parts: [Substring] = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key: String = String(parts[0])
            let value: String = parts.count > 1 ? String(parts[1]) : ""
            if parts.count == 2, key == Self.curveKey {
                if !sawCurve { readCurve(value) }
                sawCurve = true
            } else if parts.count == 2, key == Self.invertKey {
                if !sawInvert { inverted = value == "1" }
                sawInvert = true
            } else {
                extraSegments.append(segment)
            }
        }
    }

    private mutating func readCurve(_ text: String) {
        if let parsed = MappingCurve(textForm: text), parsed.isValid {
            curve = parsed
        } else {
            curve = .linear
            unreadableCurveText = text
        }
    }

    /// The segments to store after the parameter ID, in order: curve, invert, unknown.
    public var segments: [String] {
        var result: [String] = []
        if let unreadableCurveText {
            result.append(Self.curveKey + "=" + unreadableCurveText)
        } else if !curve.isLinear {
            result.append(Self.curveKey + "=" + curve.textForm)
        }
        if inverted { result.append(Self.invertKey + "=1") }
        result.append(contentsOf: extraSegments)
        return result
    }

    /// Replaces the curve (an invalid curve reads linear) and forgets any unreadable text.
    public mutating func setCurve(_ newCurve: MappingCurve) {
        curve = newCurve.isValid ? newCurve : .linear
        unreadableCurveText = nil
    }

    public var hasUnreadableCurve: Bool { unreadableCurveText != nil }

    /// Linear, not inverted, nothing kept.
    public var isDefault: Bool { segments.isEmpty }

    /// The curve's preset; nil for another curve (Custom). An unreadable curve is `.linear`.
    public var preset: MIDICurvePreset? { MIDICurvePreset.preset(for: curve) }

    /// "Linear", "Ease in, inverted", "Custom", "Linear (curve not readable)".
    public var summary: String {
        let name: String
        if hasUnreadableCurve {
            name = "Linear (curve not readable)"
        } else {
            name = preset?.title ?? "Custom"
        }
        return inverted ? name + ", inverted" : name
    }

    /// The shaped 0…1 position for a normalized control value (contract C1): clamp, invert, curve.
    public func position(normalized: Double) -> Double {
        let clamped: Double = LinearMapping.clampedPosition(normalized)
        let directed: Double = inverted ? 1 - clamped : clamped
        return curve.apply(directed)
    }
}
