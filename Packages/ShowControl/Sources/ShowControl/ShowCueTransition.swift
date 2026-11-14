// ShowCueTransition.swift — a cue's transition: type, duration and easing (SCN-007-R1, R4; contract
// specs/158-scn-007-transition-presets/contracts/show-cue-transition.md).
//
// A value type kept on each cue (nil = the default: the scene appears at once). The type names are
// CMP-014's styles; a type this version does not know (a newer app's file) is kept verbatim and applied
// as a cut. The duration is CMP-014's bound (finite, 0…10 s) and is stored exactly as given. The easing
// is a MOD-004 `MappingCurve` (validated; linear by default), stored in `show.json` as its text form.
import Foundation
import ParameterGraph

/// How a cue's scene replaces the one before it.
public enum ShowTransitionType: Sendable, Hashable {
    case cut
    case crossfade
    case dipToBlack
    /// A type this version does not know, kept verbatim (1…64 characters).
    case unknown(String)

    public static let known: [ShowTransitionType] = [.cut, .crossfade, .dipToBlack]
    public static let maximumTextLength = 64

    /// The stored text (CMP-014's `SceneTransitionStyle` raw values for the known types).
    public var text: String {
        switch self {
        case .cut: "cut"
        case .crossfade: "crossfade"
        case .dipToBlack: "dipToBlack"
        case let .unknown(text): text
        }
    }

    /// The type for stored text; nil when the text is empty or longer than 64 characters.
    public init?(text: String) {
        switch text {
        case "cut": self = .cut
        case "crossfade": self = .crossfade
        case "dipToBlack": self = .dipToBlack
        default:
            guard !text.isEmpty, text.count <= Self.maximumTextLength else { return nil }
            self = .unknown(text)
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    /// "Cut", "Crossfade", "Dip to Black", "Unknown (<text>)".
    public var displayName: String {
        switch self {
        case .cut: "Cut"
        case .crossfade: "Crossfade"
        case .dipToBlack: "Dip to Black"
        case let .unknown(text): "Unknown (\(text))"
        }
    }
}

public enum ShowTransitionError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidDuration(Double)
    case invalidEasing(String)

    public var description: String {
        switch self {
        case let .invalidDuration(seconds): "A transition lasts 0 to 10 seconds, not \(seconds)."
        case let .invalidEasing(problem): "The transition's easing is not valid: \(problem)."
        }
    }
}

/// A validated cue transition.
public struct ShowCueTransition: Sendable, Hashable {
    /// CMP-014's `SceneTransitionSpec.maximumSeconds`.
    public static let maximumSeconds: Double = 10
    /// Where the editor starts when a cue gets its first transition.
    public static let defaultCrossfade = ShowCueTransition(uncheckedType: .crossfade, durationSeconds: 1, easing: .linear)

    public let type: ShowTransitionType
    /// Finite, 0…10; stored exactly as given.
    public let durationSeconds: Double
    /// A valid MOD-004 curve.
    public let easing: MappingCurve

    public init(type: ShowTransitionType, durationSeconds: Double, easing: MappingCurve = .linear) throws(ShowTransitionError) {
        guard durationSeconds.isFinite, durationSeconds >= 0, durationSeconds <= Self.maximumSeconds else {
            throw .invalidDuration(durationSeconds)
        }
        if let problem = easing.validationProblem { throw .invalidEasing(problem) }
        self.init(uncheckedType: type, durationSeconds: durationSeconds, easing: easing)
    }

    private init(uncheckedType type: ShowTransitionType, durationSeconds: Double, easing: MappingCurve) {
        self.type = type
        self.durationSeconds = durationSeconds
        self.easing = easing
    }

    /// A copy with one part changed (validated).
    public func with(type: ShowTransitionType? = nil, durationSeconds: Double? = nil,
                     easing: MappingCurve? = nil) throws(ShowTransitionError) -> ShowCueTransition {
        try ShowCueTransition(type: type ?? self.type, durationSeconds: durationSeconds ?? self.durationSeconds,
                              easing: easing ?? self.easing)
    }
}
