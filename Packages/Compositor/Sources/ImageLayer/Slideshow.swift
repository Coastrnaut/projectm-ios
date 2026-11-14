// Slideshow.swift — the image slideshow's settings and schedule (MED-006-R1, R3 to R7, R14;
// specs/127-med-006-image-slideshow, contracts/slideshow.md C1, C2; research MED-006-D2 to D4).
//
// * `SlideshowSettings`: on/off, up to 20 slide identifiers in the user's order, the mode (Time or
//   Beats), seconds per slide (2…60) and beats per slide (1, 2, 4, 8, 16). Every initializer and the
//   decoder sanitize: duplicates and extras dropped, seconds clamped, unknown beats read as 4.
// * `SlideshowSchedule`: ticked once per shown frame with a monotonic time in nanoseconds and, in
//   Beats mode, a reliable beat grid (nil while the tempo is uncertain or searching: Time rules
//   apply). Steps over 1 s or ≤ 0 add nothing (MED-002-R9's rule), so a pause holds the slideshow.
//   No change is ever closer than the safety floor (4 − f) s, f = the profile's flashes per second.
// Plain Swift (Foundation for UUID and JSON); builds and is tested on Linux.
import Foundation

/// How slides advance.
public enum SlideshowMode: String, Sendable, Codable, CaseIterable {
    case time
    case beats
}

/// The saved slideshow (`settings.photo.slideshow`; data-model "SlideshowSettings").
public struct SlideshowSettings: Sendable, Equatable, Codable {
    public static let maximumSlides = 20
    public static let secondsRange: ClosedRange<Int> = 2...60
    public static let defaultSeconds = 5
    public static let beatChoices: [Int] = [1, 2, 4, 8, 16]
    public static let defaultBeats = 4
    public static let off = SlideshowSettings()

    public private(set) var enabled: Bool
    public private(set) var slides: [UUID]
    public private(set) var mode: SlideshowMode
    public private(set) var seconds: Int
    public private(set) var beats: Int

    public init(enabled: Bool = false, slides: [UUID] = [], mode: SlideshowMode = .time,
                seconds: Int = SlideshowSettings.defaultSeconds, beats: Int = SlideshowSettings.defaultBeats) {
        self.enabled = enabled
        self.slides = Self.unique(slides)
        self.mode = mode
        self.seconds = Self.clampSeconds(seconds)
        self.beats = Self.validBeats(beats)
    }

    /// On and holding at least one slide.
    public var isActive: Bool { enabled && !slides.isEmpty }

    /// Room for more slides.
    public var remainingCapacity: Int { max(0, Self.maximumSlides - slides.count) }

    public static func clampSeconds(_ value: Int) -> Int {
        min(max(value, secondsRange.lowerBound), secondsRange.upperBound)
    }

    public static func validBeats(_ value: Int) -> Int {
        beatChoices.contains(value) ? value : defaultBeats
    }

    /// Order kept, duplicates after the first dropped, at most `maximumSlides`.
    static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in ids where !seen.contains(id) && result.count < maximumSlides {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    // MARK: Edits (each keeps the rules)

    public func with(enabled: Bool) -> SlideshowSettings {
        SlideshowSettings(enabled: enabled, slides: slides, mode: mode, seconds: seconds, beats: beats)
    }

    public func with(slides: [UUID]) -> SlideshowSettings {
        SlideshowSettings(enabled: enabled, slides: slides, mode: mode, seconds: seconds, beats: beats)
    }

    public func with(mode: SlideshowMode) -> SlideshowSettings {
        SlideshowSettings(enabled: enabled, slides: slides, mode: mode, seconds: seconds, beats: beats)
    }

    public func with(seconds: Int) -> SlideshowSettings {
        SlideshowSettings(enabled: enabled, slides: slides, mode: mode, seconds: seconds, beats: beats)
    }

    public func with(beats: Int) -> SlideshowSettings {
        SlideshowSettings(enabled: enabled, slides: slides, mode: mode, seconds: seconds, beats: beats)
    }

    // MARK: JSON

    private enum CodingKeys: String, CodingKey { case enabled, slides, mode, seconds, beats }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let enabled: Bool = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        let raw: [String] = (try? c.decode([String].self, forKey: .slides)) ?? []
        let ids: [UUID] = raw.compactMap { (text: String) -> UUID? in
            guard let id = UUID(uuidString: text), id.uuidString == text else { return nil }   // canonical only
            return id
        }
        let mode: SlideshowMode = (try? c.decode(SlideshowMode.self, forKey: .mode)) ?? .time
        let seconds: Int = (try? c.decode(Int.self, forKey: .seconds)) ?? Self.defaultSeconds
        let beats: Int = (try? c.decode(Int.self, forKey: .beats)) ?? Self.defaultBeats
        self.init(enabled: enabled, slides: ids, mode: mode, seconds: seconds, beats: beats)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(slides.map(\.uuidString), forKey: .slides)
        try c.encode(mode, forKey: .mode)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(beats, forKey: .beats)
    }

    /// The stored value read back; nil or unreadable data reads as `.off`.
    public static func decode(_ data: Data?) -> SlideshowSettings {
        guard let data, let value = try? JSONDecoder().decode(SlideshowSettings.self, from: data) else { return .off }
        return value
    }

    /// Sorted-key JSON.
    public var encoded: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// A reliable tempo grid: beats at anchor + k × period (k any integer).
public struct SlideshowBeatGrid: Sendable, Equatable {
    public let periodNanoseconds: UInt64
    public let anchorNanoseconds: UInt64

    /// nil when the period is 0.
    public init?(periodNanoseconds: UInt64, anchorNanoseconds: UInt64) {
        guard periodNanoseconds > 0 else { return nil }
        self.periodNanoseconds = periodNanoseconds
        self.anchorNanoseconds = anchorNanoseconds
    }

    /// The first beat at or after `time` (same arithmetic as SHOW-011's `TempoSnapshot.nextBeat`).
    public func nextBeat(atOrAfter time: UInt64) -> UInt64 {
        let anchor: UInt64 = anchorNanoseconds, period: UInt64 = periodNanoseconds
        if time <= anchor { return anchor - (anchor - time) / period * period }
        let beats: UInt64 = (time - anchor + period - 1) / period
        return anchor + beats * period
    }

    /// Beats in (after, upTo].
    public func beats(after: UInt64, upTo: UInt64) -> Int {
        guard upTo > after else { return 0 }
        var count = 0
        var beat: UInt64 = nextBeat(atOrAfter: after &+ 1)
        while beat <= upTo, count < 1_000 {
            count += 1
            beat += periodNanoseconds
        }
        return count
    }
}

/// MED-006-R7 (research D4): the shortest time between two slide changes.
public enum SlideshowSafetyFloor {
    /// (4 − f) s for f = flashes per second (clamped to 1…3): 1 s Standard, 2 s Reduced, 3 s Strict.
    public static func nanoseconds(flashesPerSecond: Int) -> UInt64 {
        let f: Int = min(max(flashesPerSecond, 1), 3)
        return UInt64(4 - f) * 1_000_000_000
    }
}

/// The running slideshow (data-model "SlideshowSchedule"; contract C2).
public struct SlideshowSchedule: Sendable, Equatable {
    /// Steps longer than this add nothing (a pause, the background, a stall).
    public static let maximumStepNanoseconds: UInt64 = 1_000_000_000

    public private(set) var count: Int
    public private(set) var index: Int
    public private(set) var slideNanoseconds: UInt64 = 0
    public private(set) var sinceChangeNanoseconds: UInt64 = 0
    public private(set) var beatsSinceChange = 0
    public private(set) var lastTick: UInt64?
    public private(set) var changes = 0
    private var hadGrid = false

    public init(count: Int, index: Int = 0) {
        self.count = max(0, count)
        self.index = count > 0 ? min(max(index, 0), count - 1) : 0
    }

    /// The slide after the shown one (the shown one with fewer than two slides).
    public var nextIndex: Int { count > 1 ? (index + 1) % count : index }

    /// A new list (or a new start): shows `index`, timers from zero; the next tick only records its time.
    public mutating func restart(count: Int, index: Int = 0) {
        self = SlideshowSchedule(count: count, index: index)
    }

    /// The list changed but the shown picture stays at `index` (timers keep running).
    public mutating func relist(count: Int, index: Int) {
        self.count = max(0, count)
        self.index = count > 0 ? min(max(index, 0), count - 1) : 0
    }

    /// Mode, seconds or beats changed: the shown slide's time and beat count restart; no change now.
    public mutating func timingChanged() {
        slideNanoseconds = 0
        beatsSinceChange = 0
    }

    /// One frame at `now`. Returns the new index when the slide changes.
    public mutating func tick(now: UInt64, mode: SlideshowMode, seconds: Int, beats: Int,
                              grid: SlideshowBeatGrid?, floorNanoseconds: UInt64) -> Int? {
        guard let last = lastTick else {
            lastTick = now
            hadGrid = grid != nil
            return nil
        }
        lastTick = now
        guard now > last, now - last <= Self.maximumStepNanoseconds else { return nil }
        let step: UInt64 = now - last
        slideNanoseconds += step
        sinceChangeNanoseconds += step
        guard count > 1 else { return nil }
        let floorMet: Bool = sinceChangeNanoseconds >= floorNanoseconds
        if mode == .beats, let grid {
            if !hadGrid {   // the tempo became reliable: count from here
                hadGrid = true
                beatsSinceChange = 0
            }
            let crossed: Int = grid.beats(after: last, upTo: now)
            guard crossed > 0 else { return nil }
            beatsSinceChange += crossed
            guard beatsSinceChange >= SlideshowSettings.validBeats(beats), floorMet else { return nil }
            return advance()
        }
        hadGrid = false
        let due: UInt64 = UInt64(SlideshowSettings.clampSeconds(seconds)) * 1_000_000_000
        guard slideNanoseconds >= due, floorMet else { return nil }
        return advance()
    }

    private mutating func advance() -> Int {
        index = nextIndex
        slideNanoseconds = 0
        sinceChangeNanoseconds = 0
        beatsSinceChange = 0
        changes += 1
        return index
    }
}
