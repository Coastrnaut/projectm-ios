// PresetOverrideParameter.swift — PRE-016: the preset values a user may override (spec PRE-016-R2, R3;
// data-model "PresetOverrideParameter"; specs/185-pre-016-preset-overrides).
//
// Eight Milkdrop initial values, each with a safe range, a slider step and the engine's own default
// (projectM `PresetState.hpp`, used when a preset file does not set the value). The key is written
// as projectM's parser reads it (keys are case-insensitive; this spelling is the canonical one).
// No whole-frame toggle (bInvert, bBrighten, …) is on the list (R17). Foundation only (Linux).
import Foundation

public enum PresetOverrideParameter: String, CaseIterable, Sendable, Hashable, Codable {
    case zoom = "zoom"
    case rotation = "rot"
    case warp = "warp"
    case decay = "fDecay"
    case waveRed = "wave_r"
    case waveGreen = "wave_g"
    case waveBlue = "wave_b"
    case brightness = "fGammaAdj"

    /// The key in a preset file (canonical spelling).
    public var key: String { rawValue }

    public var label: String {
        switch self {
        case .zoom: "Zoom"
        case .rotation: "Rotation"
        case .warp: "Warp"
        case .decay: "Decay"
        case .waveRed: "Wave red"
        case .waveGreen: "Wave green"
        case .waveBlue: "Wave blue"
        case .brightness: "Brightness"
        }
    }

    /// The safe range (R2).
    public var range: ClosedRange<Double> {
        switch self {
        case .zoom: 0.8...1.2
        case .rotation: -0.2...0.2
        case .warp: 0...2
        case .decay: 0.9...1
        case .waveRed, .waveGreen, .waveBlue: 0...1
        case .brightness: 1...3
        }
    }

    public var step: Double {
        switch self {
        case .zoom, .rotation, .waveRed, .waveGreen, .waveBlue: 0.01
        case .warp, .brightness: 0.05
        case .decay: 0.005
        }
    }

    /// The engine's value when the preset file does not set one (projectM `PresetState.hpp`).
    public var engineDefault: Double {
        switch self {
        case .zoom: 1
        case .rotation: 0
        case .warp: 1
        case .decay: 0.98
        case .waveRed, .waveGreen, .waveBlue: 1
        case .brightness: 2
        }
    }

    /// The parameter a preset-file key names, compared without regard to case; nil when not allowed.
    public init?(key: String) {
        let folded: String = key.lowercased()
        guard let match = Self.allCases.first(where: { (parameter: PresetOverrideParameter) -> Bool in
            parameter.rawValue.lowercased() == folded
        }) else { return nil }
        self = match
    }

    /// R3: clamped to the range, then rounded to 4 decimals; nil when not finite.
    public func clamped(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        let inRange: Double = min(max(value, range.lowerBound), range.upperBound)
        return Self.rounded(inRange)
    }

    /// Rounded to 4 decimals (spec Clarifications: stored, shown and loaded values agree).
    public static func rounded(_ value: Double) -> Double {
        let scaled: Double = (value * 10_000).rounded()
        let result: Double = scaled / 10_000
        return result == 0 ? 0 : result   // no "-0"
    }
}
