// ShowCueDwell.swift — a cue's dwell: how long the cue stays before the show advances by itself
// (SHOW-002-R1; data-model.md; contract specs/208-show-002-timed-cue-advance/contracts/show-cue-dwell.md).
//
// Whole seconds, 1…3600 (1 s to 60 min). A value type kept on each cue (nil = Off: manual only). Stored in
// `show.json` as the cue's optional `advanceAfter` integer.
import Foundation

public enum ShowDwellError: Error, Sendable, Hashable, CustomStringConvertible {
    case outOfRange(Int)

    public var description: String {
        switch self {
        case let .outOfRange(seconds):
            "A cue advances after \(ShowCueDwell.minimumSeconds) s to \(ShowCueDwell.maximumSeconds / 60) min, not \(seconds) s."
        }
    }
}

/// A validated cue dwell in whole seconds.
public struct ShowCueDwell: Sendable, Hashable, Comparable {
    public static let minimumSeconds = 1
    public static let maximumSeconds = 3600
    /// The editor's choices (SHOW-002 Clarifications): 1 s … 45 s, then 1 min … 60 min.
    public static let presets: [ShowCueDwell] = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1200,
                                                 1800, 2700, 3600].map { (s: Int) -> ShowCueDwell in ShowCueDwell(unchecked: s) }

    public let seconds: Int

    public init(seconds: Int) throws(ShowDwellError) {
        guard seconds >= Self.minimumSeconds, seconds <= Self.maximumSeconds else { throw .outOfRange(seconds) }
        self.seconds = seconds
    }

    private init(unchecked seconds: Int) { self.seconds = seconds }

    public var duration: Duration { .seconds(seconds) }

    /// "0:05", "1:30", "60:00".
    public var clockText: String { Self.clockText(seconds: seconds) }

    /// "5 seconds", "1 minute", "1 minute 30 seconds".
    public var spokenText: String { Self.spokenText(seconds: seconds) }

    public static func < (lhs: ShowCueDwell, rhs: ShowCueDwell) -> Bool { lhs.seconds < rhs.seconds }

    /// m:ss for a whole number of seconds (negative counts as 0).
    public static func clockText(seconds: Int) -> String {
        let total: Int = max(0, seconds)
        let minutes: Int = total / 60
        let rest: Int = total % 60
        let padded: String = rest < 10 ? "0\(rest)" : "\(rest)"
        return "\(minutes):\(padded)"
    }

    /// Spoken form for VoiceOver.
    public static func spokenText(seconds: Int) -> String {
        let total: Int = max(0, seconds)
        let minutes: Int = total / 60
        let rest: Int = total % 60
        var parts: [String] = []
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if rest > 0 || minutes == 0 { parts.append(rest == 1 ? "1 second" : "\(rest) seconds") }
        return parts.joined(separator: " ")
    }
}
