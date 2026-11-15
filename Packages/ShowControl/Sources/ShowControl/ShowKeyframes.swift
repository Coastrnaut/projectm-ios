// ShowKeyframes.swift — SHOW-008 keyframe tracks along the show timeline (specs/246-show-008-keyframe-tracks; R1 to R4;
// data-model.md; contract K1 to K3, K6; research SHOW-008-D1, D2).
//
// * A track names one parameter (a MOD-001 `ParameterID`) and holds keyframes in strictly increasing time order (whole
//   milliseconds on SHOW-007's show timeline). Every keyframe of a track has the same kind: a number or an sRGB colour.
// * `value(at:)` is a pure function of the timeline time. At a keyframe's time it returns the stored sample itself (never
//   recomputed: bit-exact, the roadmap acceptance). Between two keyframes it follows the earlier keyframe's
//   interpolation, with the fraction computed from integer nanoseconds of that segment only, so nothing accumulates
//   along the track (D1). Colours mix in linear light (D2). Before the first keyframe the first value holds; after the
//   last, the last.
// Pure value types, Foundation and ParameterGraph only (Linux).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Foundation
import ParameterGraph

// MARK: - Values

/// An sRGB-encoded colour with straight alpha, every component finite and in 0…1. Stored as `[r, g, b, a]`.
public struct ShowKeyframeColor: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// Nil when a component is not finite or outside 0…1.
    public init?(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        for c in [red, green, blue, alpha] where !(c.isFinite && c >= 0 && c <= 1) { return nil }
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var components: [Double] { [red, green, blue, alpha] }

    public static let white = ShowKeyframeColor(red: 1, green: 1, blue: 1)!

    /// sRGB-encoded 0…1 → linear light (IEC 61966-2-1).
    public static func decode(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// Linear light 0…1 → sRGB-encoded (IEC 61966-2-1), clamped to 0…1.
    public static func encode(_ v: Double) -> Double {
        let c: Double = min(max(v, 0), 1)
        let e: Double = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return min(max(e, 0), 1)
    }

    /// The colour `f` of the way from `self` to `other`, mixed in linear light (alpha mixed linearly).
    func mixed(with other: ShowKeyframeColor, fraction f: Double) -> ShowKeyframeColor {
        func channel(_ a: Double, _ b: Double) -> Double {
            let la: Double = Self.decode(a)
            let lb: Double = Self.decode(b)
            return Self.encode(la + (lb - la) * f)
        }
        let alphaMix: Double = min(max(alpha + (other.alpha - alpha) * f, 0), 1)
        return ShowKeyframeColor(red: channel(red, other.red), green: channel(green, other.green),
                                 blue: channel(blue, other.blue), alpha: alphaMix) ?? self
    }
}

public enum ShowKeyframeValue: Sendable, Hashable {
    case number(Double)
    case color(ShowKeyframeColor)

    public var isColor: Bool { if case .color = self { true } else { false } }
    public var number: Double? { if case let .number(v) = self { v } else { nil } }
    public var color: ShowKeyframeColor? { if case let .color(c) = self { c } else { nil } }

    /// Same kind (number or colour).
    public func hasSameKind(as other: ShowKeyframeValue) -> Bool { isColor == other.isColor }

    /// A finite number or a valid colour.
    public var isValid: Bool {
        switch self {
        case let .number(v): v.isFinite
        case .color: true
        }
    }
}

/// How the value moves from a keyframe to the next one (SHOW-008; SHOW-009 adds Stepped, Hold and Cubic, specs/
/// 283-show-009-keyframe-easing research D1, D2). The earlier keyframe's mode shapes the segment, except that a Hold
/// keyframe also holds the segment arriving at it. Declared in picker order.
public enum ShowKeyframeInterpolation: String, Sendable, Hashable, CaseIterable {
    case linear
    /// The value stays until the next keyframe, then jumps (SHOW-008's former "Hold"; stored as `hold`).
    case stepped
    /// A cut: the value does not move towards this keyframe (the arriving segment keeps the previous value) and stays
    /// at it until the next keyframe.
    case hold
    /// Smoothstep at every keyframe: slow at both ends, halfway at the middle.
    case ease
    /// A monotone cubic through consecutive Cubic keyframes (no overshoot); with two keys, 3u² − 2u³.
    case cubic

    public var displayName: String {
        switch self {
        case .linear: "Linear"
        case .stepped: "Stepped"
        case .hold: "Hold"
        case .ease: "Ease"
        case .cubic: "Cubic"
        }
    }

    /// One line for the editor (SHOW-009 clarify).
    public var summary: String {
        switch self {
        case .linear: "Moves evenly to the next keyframe."
        case .stepped: "Stays at this value, then jumps at the next keyframe."
        case .hold: "Cuts to this value at its time and stays until the next keyframe."
        case .ease: "Starts and ends slowly at every keyframe."
        case .cubic: "Flows smoothly through Cubic keyframes without overshooting."
        }
    }

    /// The shaped fraction for `u` in 0…1 (flat modes return 0; Cubic's two-key shape).
    func shaped(_ u: Double) -> Double {
        switch self {
        case .stepped, .hold: 0
        case .linear: u
        case .ease, .cubic: u * u * (3 - 2 * u)
        }
    }
}

public struct ShowKeyframe: Sendable, Hashable {
    /// Whole milliseconds on the show timeline, 0…`ShowKeyframeTrack.maximumTimeMilliseconds`.
    public let time: Int
    public let value: ShowKeyframeValue
    /// To the next keyframe.
    public let interpolation: ShowKeyframeInterpolation

    public init(time: Int, value: ShowKeyframeValue, interpolation: ShowKeyframeInterpolation = .linear) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }

    func with(value: ShowKeyframeValue? = nil, interpolation: ShowKeyframeInterpolation? = nil) -> ShowKeyframe {
        ShowKeyframe(time: time, value: value ?? self.value, interpolation: interpolation ?? self.interpolation)
    }
}

public enum ShowKeyframeError: Error, Sendable, Hashable, CustomStringConvertible {
    case tooManyTracks(limit: Int)
    case tooManyKeyframes(limit: Int)
    case timeOutOfRange
    /// Two stored keyframes at the same time.
    case duplicateTime
    case invalidValue
    /// A number on a colour track or a colour on a numeric track.
    case kindMismatch
    case parameterTaken(ParameterID)
    case invalidParameter(ParameterID)
    case unknownTrack
    case unknownKeyframe

    public var description: String {
        switch self {
        case let .tooManyTracks(limit): "A show can have at most \(limit) keyframe tracks."
        case let .tooManyKeyframes(limit): "A track can have at most \(limit) keyframes."
        case .timeOutOfRange: "The keyframe's time is outside the show timeline."
        case .duplicateTime: "Two keyframes of a track share a time."
        case .invalidValue: "The keyframe's value is not valid."
        case .kindMismatch: "A track's keyframes must all be numbers or all be colours."
        case let .parameterTaken(id): "The show already has a track for \(id)."
        case let .invalidParameter(id): "\"\(id)\" is not a valid parameter."
        case .unknownTrack: "The track no longer exists."
        case .unknownKeyframe: "The keyframe no longer exists."
        }
    }
}

// MARK: - Track

public struct ShowKeyframeTrack: Sendable, Hashable, Identifiable {
    public static let maximumKeyframes = 256
    /// 256 cues × 3600 s (the longest SHOW-007 timeline), in milliseconds.
    public static let maximumTimeMilliseconds = 921_600_000

    public let id: UUID
    public let parameter: ParameterID
    /// Strictly increasing times; one kind.
    public private(set) var keyframes: [ShowKeyframe]

    public init(id: UUID = UUID(), parameter: ParameterID) {
        self.id = id
        self.parameter = parameter
        keyframes = []
    }

    /// A track from stored keyframes (sorted here); throws on a rule the editor enforces.
    public init(id: UUID, parameter: ParameterID, keyframes: [ShowKeyframe]) throws(ShowKeyframeError) {
        self.init(id: id, parameter: parameter)
        for keyframe in keyframes {
            if self.keyframes.contains(where: { (k: ShowKeyframe) -> Bool in k.time == keyframe.time }) { throw .duplicateTime }
            try setKeyframe(keyframe)
        }
    }

    public var isEmpty: Bool { keyframes.isEmpty }
    /// Nil while empty.
    public var isColor: Bool? { keyframes.first?.value.isColor }

    // MARK: Evaluation (K1 to K3)

    /// The value at `time` on the show timeline (nil for a track without keyframes).
    public func value(at time: Duration) -> ShowKeyframeValue? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        let t: Int64 = Self.nanoseconds(time)
        if t <= Self.nanoseconds(ms: first.time) { return first.value }   // before (or at) the first keyframe
        if t >= Self.nanoseconds(ms: last.time) { return last.value }     // after (or at) the last keyframe
        // The last keyframe at or before t (binary search; times strictly increase).
        var low = 0
        var high: Int = keyframes.count - 1
        while low < high {
            let mid: Int = (low + high + 1) / 2
            if Self.nanoseconds(ms: keyframes[mid].time) <= t { low = mid } else { high = mid - 1 }
        }
        let a: ShowKeyframe = keyframes[low]
        let t0: Int64 = Self.nanoseconds(ms: a.time)
        if t == t0 { return a.value }   // exactly at a keyframe: the stored sample itself
        let b: ShowKeyframe = keyframes[low + 1]
        let t1: Int64 = Self.nanoseconds(ms: b.time)
        let u: Double = Double(t - t0) / Double(t1 - t0)   // segment-relative, 0 < u < 1
        return segmentValue(low, fraction: u)
    }

    /// The value inside segment `i` (keyframe i to i + 1) at fraction `u`, 0 < u < 1 (SHOW-009 research D1, D2, D4).
    func segmentValue(_ i: Int, fraction u: Double) -> ShowKeyframeValue {
        let a: ShowKeyframe = keyframes[i]
        let b: ShowKeyframe = keyframes[i + 1]
        let mode: ShowKeyframeInterpolation = b.interpolation == .hold ? .hold : a.interpolation   // Hold wins on arrival
        switch (mode, a.value, b.value) {
        case (.stepped, _, _), (.hold, _, _):
            return a.value
        case let (.cubic, .number(y0), .number(y1)):
            let h = Double(b.time - a.time)
            return .number(MonotoneCubic.value(y0: y0, y1: y1, m0: cubicTangent(at: i) * h, m1: cubicTangent(at: i + 1) * h, u: u))
        default:
            return Self.interpolate(a.value, b.value, fraction: mode.shaped(u))
        }
    }

    /// Whether segment `i` is drawn as a cubic (its left key is Cubic and its right key is not Hold).
    private func isCubicSegment(_ i: Int) -> Bool {
        i >= 0 && i + 1 < keyframes.count && keyframes[i].interpolation == .cubic && keyframes[i + 1].interpolation != .hold
    }

    /// The slope (value per millisecond) at keyframe `j`: non-zero only inside a Cubic run (both neighbouring segments
    /// cubic), from the two numeric secants (research D2).
    private func cubicTangent(at j: Int) -> Double {
        guard isCubicSegment(j - 1), isCubicSegment(j),
              let y0 = keyframes[j - 1].value.number, let y1 = keyframes[j].value.number,
              let y2 = keyframes[j + 1].value.number else { return 0 }
        return MonotoneCubic.tangent(h0: Double(keyframes[j].time - keyframes[j - 1].time), d0: y1 - y0,
                                     h1: Double(keyframes[j + 1].time - keyframes[j].time), d1: y2 - y1)
    }

    static func interpolate(_ a: ShowKeyframeValue, _ b: ShowKeyframeValue, fraction f: Double) -> ShowKeyframeValue {
        switch (a, b) {
        case let (.number(x), .number(y)):
            return .number(x + (y - x) * f)
        case let (.color(x), .color(y)):
            return .color(x.mixed(with: y, fraction: f))
        default:
            return a   // a track never mixes kinds; hold the earlier value
        }
    }

    static func nanoseconds(ms: Int) -> Int64 { Int64(ms) * 1_000_000 }

    static func nanoseconds(_ d: Duration) -> Int64 {
        let parts = d.components
        return parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
    }

    /// Whole milliseconds of a timeline time (rounded to nearest; negative counts as 0).
    public static func milliseconds(of time: Duration) -> Int {
        let ns: Int64 = max(0, nanoseconds(time))
        return Int((ns + 500_000) / 1_000_000)
    }

    // MARK: Edits (K6)

    /// Adds `keyframe`, or replaces the keyframe at the same time.
    public mutating func setKeyframe(_ keyframe: ShowKeyframe) throws(ShowKeyframeError) {
        guard keyframe.time >= 0, keyframe.time <= Self.maximumTimeMilliseconds else { throw .timeOutOfRange }
        guard keyframe.value.isValid else { throw .invalidValue }
        if let other = keyframes.first(where: { (k: ShowKeyframe) -> Bool in k.time != keyframe.time }),
           !other.value.hasSameKind(as: keyframe.value) {
            throw .kindMismatch
        }
        if let index = keyframes.firstIndex(where: { (k: ShowKeyframe) -> Bool in k.time == keyframe.time }) {
            keyframes[index] = keyframe
            return
        }
        guard keyframes.count < Self.maximumKeyframes else { throw .tooManyKeyframes(limit: Self.maximumKeyframes) }
        let insertAt: Int = keyframes.firstIndex(where: { (k: ShowKeyframe) -> Bool in k.time > keyframe.time }) ?? keyframes.count
        keyframes.insert(keyframe, at: insertAt)
    }

    public mutating func removeKeyframe(at time: Int) throws(ShowKeyframeError) {
        guard let index = keyframes.firstIndex(where: { (k: ShowKeyframe) -> Bool in k.time == time }) else { throw .unknownKeyframe }
        keyframes.remove(at: index)
    }

    public mutating func setValue(_ value: ShowKeyframeValue, at time: Int) throws(ShowKeyframeError) {
        guard let keyframe = keyframes.first(where: { (k: ShowKeyframe) -> Bool in k.time == time }) else { throw .unknownKeyframe }
        try setKeyframe(keyframe.with(value: value))
    }

    public mutating func setInterpolation(_ interpolation: ShowKeyframeInterpolation, at time: Int) throws(ShowKeyframeError) {
        guard let index = keyframes.firstIndex(where: { (k: ShowKeyframe) -> Bool in k.time == time }) else { throw .unknownKeyframe }
        keyframes[index] = keyframes[index].with(interpolation: interpolation)
    }
}

// MARK: - The show's tracks

public struct ShowKeyframeTracks: Sendable, Hashable {
    public static let maximumTracks = 16

    /// In the order they were added.
    public private(set) var tracks: [ShowKeyframeTrack]

    public init() { tracks = [] }

    /// Tracks from stored parts; throws on a duplicate ID or parameter, or too many.
    public init(tracks: [ShowKeyframeTrack]) throws(ShowKeyframeError) {
        self.init()
        for track in tracks { try add(track) }
    }

    public var isEmpty: Bool { tracks.isEmpty }

    public func track(_ id: UUID) -> ShowKeyframeTrack? { tracks.first { (t: ShowKeyframeTrack) -> Bool in t.id == id } }

    public func track(for parameter: ParameterID) -> ShowKeyframeTrack? {
        tracks.first { (t: ShowKeyframeTrack) -> Bool in t.parameter == parameter }
    }

    /// Every track's value at `time` (tracks without keyframes are left out).
    public func values(at time: Duration) -> [ParameterID: ShowKeyframeValue] {
        var result: [ParameterID: ShowKeyframeValue] = [:]
        for track in tracks { if let value = track.value(at: time) { result[track.parameter] = value } }
        return result
    }

    public mutating func add(_ track: ShowKeyframeTrack) throws(ShowKeyframeError) {
        guard track.parameter.isWellFormed else { throw .invalidParameter(track.parameter) }
        guard tracks.count < Self.maximumTracks else { throw .tooManyTracks(limit: Self.maximumTracks) }
        if tracks.contains(where: { (t: ShowKeyframeTrack) -> Bool in t.parameter == track.parameter || t.id == track.id }) {
            throw .parameterTaken(track.parameter)
        }
        tracks.append(track)
    }

    /// Adds an empty track for `parameter`.
    @discardableResult
    public mutating func addTrack(parameter: ParameterID, id: UUID = UUID()) throws(ShowKeyframeError) -> ShowKeyframeTrack {
        let track = ShowKeyframeTrack(id: id, parameter: parameter)
        try add(track)
        return track
    }

    public mutating func removeTrack(_ id: UUID) throws(ShowKeyframeError) {
        guard let index = tracks.firstIndex(where: { (t: ShowKeyframeTrack) -> Bool in t.id == id }) else { throw .unknownTrack }
        tracks.remove(at: index)
    }

    /// Runs `edit` on track `id` (unchanged when it throws).
    public mutating func edit(_ id: UUID, _ edit: (inout ShowKeyframeTrack) throws(ShowKeyframeError) -> Void) throws(ShowKeyframeError) {
        guard let index = tracks.firstIndex(where: { (t: ShowKeyframeTrack) -> Bool in t.id == id }) else { throw .unknownTrack }
        var track: ShowKeyframeTrack = tracks[index]
        try edit(&track)
        tracks[index] = track
    }
}
