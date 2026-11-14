// SceneTransition.swift — the scene transition model (CMP-014-R1, R3, R10, R12; ADR-0042;
// specs/116-cmp-014-compositor-transition-bus/contracts/transition-bus.md).
//
// Plain Swift (builds on Linux): the transition spec (style, duration, easing; validated, Codable so
// SCN-007 can store it), Reduce Motion resolution (a scene transition is decorative → a cut), the one
// transition clock and the blend weights. The clock follows the frame timeline: it sums the durations
// between the presentation times of the frames shown, each clamped like the compositor's frame clock
// (`LayerFrameClock.maxFrameDuration`), in integer nanoseconds, so a transition is deterministic from
// the frame times, never reads a wall clock, survives a pause of any length and ends exactly.

/// How the outgoing scene gives way to the incoming one.
public enum SceneTransitionStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// The incoming scene from the next frame.
    case cut
    /// Outgoing × (1 − e) + incoming × e.
    case crossfade
    /// The outgoing scene fades to black over the first half, the incoming fades in over the second.
    case dipToBlack
}

/// The curve from clock progress t to eased progress e (exact at 0 and 1, monotonic).
public enum SceneTransitionEasing: String, Sendable, Equatable, Codable, CaseIterable {
    case linear
    /// Smoothstep, t²(3 − 2t).
    case easeInOut

    public func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear: return x
        case .easeInOut: return x * x * (3 - 2 * x)
        }
    }
}

public enum SceneTransitionError: Error, Sendable, Equatable {
    case nonFiniteDuration
    case durationOutOfRange(Double)
}

/// A validated transition: style, duration (finite, 0…`maximumSeconds`) and easing.
public struct SceneTransitionSpec: Sendable, Equatable, Codable {
    public static let maximumSeconds = 10.0
    /// The incoming scene from the next frame.
    public static let cut = SceneTransitionSpec(uncheckedStyle: .cut, durationSeconds: 0, easing: .linear)
    /// The default crossfade: 1 s, ease in-out (CMP-014 Clarifications).
    public static let defaultCrossfade = SceneTransitionSpec(uncheckedStyle: .crossfade, durationSeconds: 1, easing: .easeInOut)

    public let style: SceneTransitionStyle
    public let durationSeconds: Double
    public let easing: SceneTransitionEasing

    public init(style: SceneTransitionStyle, durationSeconds: Double, easing: SceneTransitionEasing = .easeInOut) throws(SceneTransitionError) {
        guard durationSeconds.isFinite else { throw .nonFiniteDuration }
        guard durationSeconds >= 0, durationSeconds <= Self.maximumSeconds else { throw .durationOutOfRange(durationSeconds) }
        self.init(uncheckedStyle: style, durationSeconds: durationSeconds, easing: easing)
    }

    private init(uncheckedStyle style: SceneTransitionStyle, durationSeconds: Double, easing: SceneTransitionEasing) {
        self.style = style
        self.durationSeconds = durationSeconds
        self.easing = easing
    }

    /// A cut, or a transition of no duration: the incoming scene from the next frame.
    public var isInstant: Bool { style == .cut || durationSeconds == 0 }

    /// CMP-014-R10: a scene transition is decorative, so Reduce Motion makes it a cut (ACC-001).
    public func resolved(reduceMotion: Bool) -> SceneTransitionSpec { reduceMotion ? .cut : self }

    /// The duration in whole nanoseconds (rounded).
    public var durationNanoseconds: UInt64 { UInt64((durationSeconds * 1e9).rounded()) }

    private enum CodingKeys: String, CodingKey { case style, durationSeconds, easing }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let style = try container.decode(SceneTransitionStyle.self, forKey: .style)
        let seconds = try container.decode(Double.self, forKey: .durationSeconds)
        let easing = try container.decodeIfPresent(SceneTransitionEasing.self, forKey: .easing) ?? .easeInOut
        do {
            try self.init(style: style, durationSeconds: seconds, easing: easing)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .durationSeconds, in: container,
                                                   debugDescription: "duration must be finite and within 0…\(Self.maximumSeconds) s")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(easing, forKey: .easing)
    }
}

/// CMP-014-R1: the one transition clock. Progress is elapsed frame time / duration, exactly 1 on the
/// first frame at or after the duration; the first frame after the start or after `pause()` adds no time.
public struct SceneTransitionClock: Sendable, Equatable {
    public let durationNanoseconds: UInt64
    public let easing: SceneTransitionEasing
    public private(set) var elapsedNanoseconds: UInt64 = 0
    private var previous: UInt64?
    private static let maxStepNanoseconds = UInt64((LayerFrameClock.maxFrameDuration * 1e9).rounded())

    public init(durationNanoseconds: UInt64, easing: SceneTransitionEasing = .easeInOut) {
        self.durationNanoseconds = durationNanoseconds
        self.easing = easing
    }

    public init(spec: SceneTransitionSpec) {
        self.init(durationNanoseconds: spec.isInstant ? 0 : spec.durationNanoseconds, easing: spec.easing)
    }

    /// Advances to the frame shown at `presentationTimeNanoseconds` and returns the progress (0…1).
    @discardableResult
    public mutating func advance(presentationTimeNanoseconds time: UInt64) -> Double {
        guard let last = previous else {
            previous = time   // the first frame after the start or a pause adds nothing
            return progress
        }
        guard time > last else { return progress }   // a repeated or earlier time adds nothing
        let step = min(time - last, Self.maxStepNanoseconds)
        elapsedNanoseconds += min(step, UInt64.max - elapsedNanoseconds)
        previous = time
        return progress
    }

    /// The next frame adds no time (the visualizer paused); progress stays where it is.
    public mutating func pause() { previous = nil }

    /// Raw progress, 0…1 (exactly 1 once the duration is reached; 1 for a zero duration).
    public var progress: Double {
        guard durationNanoseconds > 0 else { return 1 }
        if elapsedNanoseconds >= durationNanoseconds { return 1 }
        return Double(elapsedNanoseconds) / Double(durationNanoseconds)
    }

    /// Progress through the easing curve (exact at 0 and 1).
    public var easedProgress: Double { easing.ease(progress) }

    public var isFinished: Bool { progress >= 1 }
}

/// The weights of the two scenes in a blended frame.
public struct SceneTransitionWeights: Sendable, Equatable {
    public var outgoing: Float
    public var incoming: Float

    public init(outgoing: Float, incoming: Float) {
        self.outgoing = outgoing
        self.incoming = incoming
    }
}

public enum SceneTransitionMix {
    /// CMP-014-R3: weights at eased progress `e` (clamped to 0…1).
    public static func weights(style: SceneTransitionStyle, eased e: Double) -> SceneTransitionWeights {
        let x = min(max(e, 0), 1)
        switch style {
        case .cut:
            return SceneTransitionWeights(outgoing: 0, incoming: 1)
        case .crossfade:
            return SceneTransitionWeights(outgoing: Float(1 - x), incoming: Float(x))
        case .dipToBlack:
            if x < 0.5 { return SceneTransitionWeights(outgoing: Float(1 - 2 * x), incoming: 0) }
            return SceneTransitionWeights(outgoing: 0, incoming: Float(2 * x - 1))
        }
    }
}
