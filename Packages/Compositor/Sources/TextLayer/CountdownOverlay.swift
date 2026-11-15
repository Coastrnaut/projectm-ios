// CountdownOverlay.swift — the countdown overlay's timer, format and settings (MED-012-R2 to R5, R10; research
// MED-012-D1 to D4; contracts/countdown-overlay.md C1, C2). Plain Swift, every platform.
//
// * `MonotonicClock` gives seconds on a clock that never jumps. The app's `ContinuousMonotonicClock` reads Swift's
//   `ContinuousClock` (it keeps counting while the device sleeps); never the wall clock, so a time or time-zone change
//   never moves a countdown. Tests use `ManualMonotonicClock`; the DEBUG fixture `FixedMonotonicClock`.
// * `CountdownTimer` is a pure value: `remaining(at:) = max(0, duration − elapsed)`, never negative. `advance(at:)`
//   returns true exactly once per run, on the update that reaches zero, however far past zero it lands; the timer
//   then holds at zero. Reset and a Start after the finish re-arm it.
// * `CountdownFormat` shows the remaining whole seconds rounded up: "mm:ss" below an hour, "h:mm:ss" from it.
// * The coordinator feeds the MED-009 text layer through MED-011's `ChangedText`, so the layer redraws at most once
//   per shown second and never after zero.
import Foundation

/// Seconds on a monotonic clock (MED-012-R2). Only differences are meaningful.
public protocol MonotonicClock: Sendable {
    var seconds: Double { get }
}

/// Swift's `ContinuousClock` (counts through sleep), measured from the moment this value was made.
public struct ContinuousMonotonicClock: MonotonicClock {
    private let origin: ContinuousClock.Instant

    public init() { origin = ContinuousClock.now }

    public var seconds: Double {
        let c = origin.duration(to: ContinuousClock.now).components
        return Double(c.seconds) + Double(c.attoseconds) * 1e-18
    }
}

/// A clock that never moves (the DEBUG UI-test fixture).
public struct FixedMonotonicClock: MonotonicClock {
    public let seconds: Double
    public init(seconds: Double) { self.seconds = seconds }
}

/// A clock moved by hand (tests). One owner at a time.
public final class ManualMonotonicClock: MonotonicClock, @unchecked Sendable {
    public var seconds: Double
    public init(seconds: Double = 0) { self.seconds = seconds }
    public func advance(by delta: Double) { seconds += delta }
}

public enum CountdownState: String, Sendable, Equatable {
    case idle, running, paused, finished
}

/// One countdown run (data-model "CountdownTimer"; contract C2).
public struct CountdownTimer: Equatable, Sendable {
    /// 1 s to 99 min.
    public static let durationRange: ClosedRange<Int> = 1...5940

    public private(set) var durationSeconds: Int
    /// Running seconds before the current segment.
    public private(set) var accumulated: Double = 0
    /// Monotonic seconds at which the current segment started; nil when not running.
    public private(set) var startedAt: Double?
    /// Set once when the countdown reaches zero; cleared by Reset and a new Start.
    public private(set) var hasFinished = false

    public init(durationSeconds: Int) {
        self.durationSeconds = Self.clamp(durationSeconds)
    }

    public static func clamp(_ seconds: Int) -> Int {
        min(max(seconds, durationRange.lowerBound), durationRange.upperBound)
    }

    public var isRunning: Bool { startedAt != nil }

    public var state: CountdownState {
        if hasFinished { return .finished }
        if isRunning { return .running }
        return accumulated > 0 ? .paused : .idle
    }

    public func elapsed(at now: Double) -> Double {
        guard let start = startedAt else { return accumulated }
        return accumulated + max(0, now - start)
    }

    /// Never negative.
    public func remaining(at now: Double) -> Double {
        max(0, Double(durationSeconds) - elapsed(at: now))
    }

    /// The remaining whole seconds rounded up (0 only at or after zero).
    public func displayedSeconds(at now: Double) -> Int {
        let r = remaining(at: now)
        guard r > 0 else { return 0 }
        return Int((r - 1e-9).rounded(.up))
    }

    /// Starts or resumes; a finished countdown starts again from its full duration.
    public mutating func start(at now: Double) {
        if hasFinished { reset() }
        guard startedAt == nil else { return }
        startedAt = now
    }

    /// Keeps the remaining time.
    public mutating func pause(at now: Double) {
        guard let start = startedAt else { return }
        accumulated += max(0, now - start)
        startedAt = nil
    }

    /// Stopped at the full duration (or `durationSeconds`, clamped), re-armed.
    public mutating func reset(durationSeconds: Int? = nil) {
        if let seconds = durationSeconds { self.durationSeconds = Self.clamp(seconds) }
        accumulated = 0
        startedAt = nil
        hasFinished = false
    }

    /// True exactly once per run: on the update at which the countdown has reached zero. The timer then stops at zero.
    public mutating func advance(at now: Double) -> Bool {
        guard !hasFinished, elapsed(at: now) >= Double(durationSeconds) else { return false }
        accumulated = Double(durationSeconds)
        startedAt = nil
        hasFinished = true
        return true
    }
}

/// The countdown's face (contract C1).
public enum CountdownFormat {
    /// "mm:ss" below an hour, "h:mm:ss" from it; negative input reads as 0.
    public static func string(seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let rest = s % 60
        let tail: String = pad(minutes) + ":" + pad(rest)
        return hours > 0 ? String(hours) + ":" + tail : tail
    }

    public static func string(_ timer: CountdownTimer, at now: Double) -> String {
        string(seconds: timer.displayedSeconds(at: now))
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0" + String(n) : String(n) }
}

public enum CountdownSchedule {
    /// Seconds from `now` to the next change of the shown second (0 < delay ≤ 1); nil when nothing will change
    /// (stopped, paused or finished).
    public static func delay(_ timer: CountdownTimer, at now: Double) -> Double? {
        guard timer.isRunning, !timer.hasFinished else { return nil }
        let shown = timer.displayedSeconds(at: now)
        guard shown > 0 else { return 0.001 }
        let delay = timer.remaining(at: now) - Double(shown - 1)
        return min(max(delay, 0.001), 1)
    }
}

/// The countdown's settings (data-model "CountdownOverlaySettings").
public struct CountdownOverlaySettings: Equatable, Sendable {
    public static let currentVersion = 1
    public static let defaultDurationSeconds = 300
    /// Top centre, 8 % of the picture height, white bold Menlo (fixed-width digits) with the default outline.
    public static let defaultStyle = TextOverlaySpec(font: .menlo, weight: .bold, size: 0.08, alignment: .center,
                                                     verticalPosition: .top)
    public static let `default` = CountdownOverlaySettings()

    public var isShown: Bool
    /// 1…5,940, clamped.
    public var durationSeconds: Int {
        didSet { if !CountdownTimer.durationRange.contains(durationSeconds) { durationSeconds = CountdownTimer.clamp(durationSeconds) } }
    }
    /// Scenes added to the show as cues record the duration, so their cue starts the countdown (MED-012-R8).
    public var startsFromCues: Bool
    /// Placement and look; the message is always empty here.
    public var style: TextOverlaySpec {
        didSet { if !style.message.isEmpty { style.setMessage("") } }
    }

    public init(isShown: Bool = false, durationSeconds: Int = CountdownOverlaySettings.defaultDurationSeconds,
                startsFromCues: Bool = false, style: TextOverlaySpec = CountdownOverlaySettings.defaultStyle) {
        self.isShown = isShown
        self.durationSeconds = CountdownTimer.clamp(durationSeconds)
        self.startsFromCues = startsFromCues
        var clean = style
        clean.setMessage("")
        self.style = clean
    }

    /// The whole minutes of the duration, 0…99 (the Minutes stepper).
    public var minutes: Int {
        get { durationSeconds / 60 }
        set { durationSeconds = min(max(newValue, 0), 99) * 60 + seconds }
    }

    /// The seconds past the minutes, 0…59 (the Seconds stepper).
    public var seconds: Int {
        get { durationSeconds % 60 }
        set { durationSeconds = minutes * 60 + min(max(newValue, 0), 59) }
    }

    /// What the text layer draws for `text`: the style with the time as its message (empty when hidden).
    public func spec(for text: String?) -> TextOverlaySpec {
        var spec = style
        spec.setMessage(isShown ? (text ?? "") : "")
        return spec
    }
}

public typealias CountdownOverlayDecodeResult = StoredOverlayDecodeResult<CountdownOverlaySettings>

extension CountdownOverlaySettings: Codable {
    enum CodingKeys: String, CodingKey {
        case version, isShown, durationSeconds, startsFromCues, style
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(isShown, forKey: .isShown)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(startsFromCues, forKey: .startsFromCues)
        try c.encode(style, forKey: .style)
    }

    /// Version 1; missing fields read as their defaults, a duration out of range is clamped. Callers go through
    /// `decodeStored`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CountdownOverlaySettings.default
        self.init(isShown: try c.decodeIfPresent(Bool.self, forKey: .isShown) ?? d.isShown,
                  durationSeconds: try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? d.durationSeconds,
                  startsFromCues: try c.decodeIfPresent(Bool.self, forKey: .startsFromCues) ?? d.startsFromCues,
                  style: try c.decodeIfPresent(TextOverlaySpec.self, forKey: .style) ?? d.style)
    }

    /// JSON with sorted keys and `"version": 1`.
    public func encodedForStorage() -> Data { StoredOverlayCodec.encode(self) }

    public static func decodeStored(_ data: Data) -> CountdownOverlayDecodeResult {
        StoredOverlayCodec.decode(CountdownOverlaySettings.self, from: data, currentVersion: currentVersion)
    }
}
