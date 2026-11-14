// ThresholdTrigger.swift — turns a continuous 0…1 input into debounced discrete trigger events (MOD-006-R1 to
// R8, R12; specs/148-mod-006-threshold-trigger, research MOD-006-D1 to D5, contract T1 to T3).
//
// * Schmitt hysteresis: fire when armed and the input rises above `high`, then disarm; re-arm only after it falls
//   below `low` (strict comparisons; `low < high`). Noise smaller than `high − low` cannot both re-arm and refire,
//   so it gives at most one event ("Noise around threshold produces no trigger storm").
// * Minimum interval (default 100 ms): a crossing within the interval after the last fire is consumed: it disarms
//   without firing and is never delivered later.
// * Optional hold: the input must stay above `high` continuously for `holdSeconds` before firing.
// * Injected clock only (the frame's display time in nanoseconds, as MOD-002/MOD-005): an earlier time counts as the
//   latest time seen. A non-finite input neither fires nor re-arms and restarts a pending hold.
// * Pure value type, deterministic, allocation-free per step; the bank evaluates up to 8 bindings per frame on
//   one owner (not `Sendable`, never from an audio callback; Constitution VII). Foundation-free: builds on Linux.
//
// The actions mirror MIDI-006's trigger-mode `MIDINoteAction` identifiers; ParameterGraph has no dependencies, so
// the app maps them by raw value (Constitution VI).

/// The levels and timing of one threshold trigger (contract T1).
public struct ThresholdTriggerSettings: Sendable, Hashable {
    /// Fire when the input rises above this level (0…1, above `low`).
    public var high: Double
    /// Re-arm when the input falls below this level (0…1, below `high`).
    public var low: Double
    /// The shortest time between two fires, in seconds (0…60).
    public var minimumIntervalSeconds: Double
    /// How long the input must stay above `high` before firing, in seconds (0…60).
    public var holdSeconds: Double

    public static let defaultMinimumIntervalSeconds = 0.1
    /// The longest allowed interval or hold.
    public static let maximumSeconds = 60.0

    public init(high: Double, low: Double, minimumIntervalSeconds: Double = Self.defaultMinimumIntervalSeconds,
                holdSeconds: Double = 0) {
        self.high = high
        self.low = low
        self.minimumIntervalSeconds = minimumIntervalSeconds
        self.holdSeconds = holdSeconds
    }

    /// Why the settings are invalid (MOD-006-R7), or nil when they are valid.
    public var validationProblem: String? {
        for (name, level) in [("high", high), ("low", low)] where !(level.isFinite && level >= 0 && level <= 1) {
            return "\(name) must be a finite level in 0…1"
        }
        guard low < high else { return "low must be below high" }
        for (name, seconds) in [("minimum interval", minimumIntervalSeconds), ("hold", holdSeconds)]
            where !(seconds.isFinite && seconds >= 0 && seconds <= Self.maximumSeconds) {
            return "the \(name) must be finite seconds in 0…\(Int(Self.maximumSeconds))"
        }
        return nil
    }
}

/// Why a trigger or a trigger set was refused. Nothing changes after any of these.
public enum ThresholdTriggerError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidSettings(String)
    case tooManyTriggers(limit: Int)
    case bandIndexOutOfRange(Int)

    public var description: String {
        switch self {
        case let .invalidSettings(reason): "invalid threshold trigger: \(reason)"
        case let .tooManyTriggers(limit): "at most \(limit) threshold triggers"
        case let .bandIndexOutOfRange(index): "band \(index) is outside 0…\(AudioFeatureSource.maximumBandIndex)"
        }
    }
}

/// One threshold trigger with its state (contract T2).
public struct ThresholdTrigger: Sendable, Hashable {
    public let settings: ThresholdTriggerSettings
    /// True at creation; false after a fire or a consumed crossing until the input falls below `low`.
    public private(set) var isArmed = true
    private var aboveSince: UInt64?
    private var lastFire: UInt64?
    private var latestTime: UInt64?

    public init(settings: ThresholdTriggerSettings) throws(ThresholdTriggerError) {
        if let problem = settings.validationProblem { throw .invalidSettings(problem) }
        self.settings = settings
    }

    /// Advances with one input value at `timeNanoseconds`; true on the frame the trigger fires.
    public mutating func step(value: Double, timeNanoseconds: UInt64) -> Bool {
        let now: UInt64 = max(timeNanoseconds, latestTime ?? timeNanoseconds)
        latestTime = now
        guard value.isFinite else {
            aboveSince = nil   // no information: neither fire nor re-arm; a hold must be continuous
            return false
        }
        guard isArmed else {
            if value < settings.low { isArmed = true }
            return false
        }
        guard value > settings.high else {
            aboveSince = nil
            return false
        }
        let since: UInt64 = aboveSince ?? now
        aboveSince = since
        guard Self.seconds(now - since) >= settings.holdSeconds else { return false }
        isArmed = false
        aboveSince = nil
        if let last = lastFire, Self.seconds(now - last) < settings.minimumIntervalSeconds { return false }   // consumed
        lastFire = now
        return true
    }

    private static func seconds(_ nanoseconds: UInt64) -> Double { Double(nanoseconds) / 1e9 }
}

/// What a threshold trigger performs: MIDI-006's trigger-mode actions, by the same identifiers (research MOD-006-D5).
public enum ThresholdTriggerAction: String, Sendable, Hashable, CaseIterable {
    case cueNext = "cue.next"
    case cuePrevious = "cue.previous"
    /// Black out (toggle).
    case blackout = "blackout"
}

/// An audio feature, the action it triggers and the trigger's settings.
public struct ThresholdTriggerBinding: Sendable, Hashable {
    public var source: AudioFeatureSource
    public var action: ThresholdTriggerAction
    public var settings: ThresholdTriggerSettings

    public init(source: AudioFeatureSource, action: ThresholdTriggerAction, settings: ThresholdTriggerSettings) {
        self.source = source
        self.action = action
        self.settings = settings
    }
}

/// The live triggers of a scene, evaluated once per frame (contract T3).
public final class ThresholdTriggerBank {
    /// At most this many triggers are live (MOD-006-R10).
    public static let maximumTriggers = 8

    private struct Slot {
        let binding: ThresholdTriggerBinding
        var trigger: ThresholdTrigger
    }

    private var slots: ContiguousArray<Slot> = []

    public init() {
        slots.reserveCapacity(Self.maximumTriggers)
    }

    /// Replaces every trigger with `bindings`, each starting armed; validates all first and changes nothing when one
    /// is refused.
    public func set(_ bindings: [ThresholdTriggerBinding]) throws(ThresholdTriggerError) {
        guard bindings.count <= Self.maximumTriggers else { throw .tooManyTriggers(limit: Self.maximumTriggers) }
        var next: ContiguousArray<Slot> = []
        next.reserveCapacity(Self.maximumTriggers)
        for binding in bindings {
            if case let .band(index) = binding.source, !(0...AudioFeatureSource.maximumBandIndex).contains(index) {
                throw .bandIndexOutOfRange(index)
            }
            next.append(Slot(binding: binding, trigger: try ThresholdTrigger(settings: binding.settings)))
        }
        slots = next
    }

    public var bindings: [ThresholdTriggerBinding] { slots.map(\.binding) }

    public var hasTriggers: Bool { !slots.isEmpty }

    /// Steps every trigger with its feature in `frame` at `timeNanoseconds` and calls `fire` for each that fires, in
    /// binding order. Allocates nothing.
    public func advance(frame: AudioFeatureFrame, timeNanoseconds: UInt64, fire: (ThresholdTriggerAction) -> Void) {
        for i in slots.indices {
            let value: Double = slots[i].binding.source.value(in: frame)
            if slots[i].trigger.step(value: value, timeNanoseconds: timeNanoseconds) { fire(slots[i].binding.action) }
        }
    }
}
