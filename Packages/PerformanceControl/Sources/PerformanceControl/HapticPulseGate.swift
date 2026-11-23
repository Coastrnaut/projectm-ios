// HapticPulseGate.swift — ACC-007: which beat events become haptic pulses, and how many
// (specs/238-acc-007-haptic-beat-feedback; R3, R4; contract C1; research ACC-007-D3, D4).
//
// * Choice: Beats (ANL-005 beats with confidence ≥ 0.5, VIS-006's rule, held while ≥ 0.4 once reached),
//   Downbeats (every 4th such beat counted from a session marker; 4/4, no downbeat detection, as MOD-017's Bar)
//   or Kicks (ANL-007).
// * Hysteresis (QA-011 D1 2026-11-23, spec Clarifications): music with eighth-note hi-hats puts half its onsets
//   off the beat grid, so ANL-005's precision is about 0.5 and a steady 120 BPM groove's confidence wavers
//   between 0.46 and 0.52; a single 0.5 cut pulsed 9 of 24 beats. A beat at ≥ 0.5 engages the tracker's beats,
//   which then stay selected while their confidence is ≥ 0.4; a weaker beat or a session marker disengages.
// * Limits on the events' own bus times: ≥ 150 ms apart, ≤ 4 in any 1 s, ≤ 180 in any 60 s; an event
//   delivered more than 200 ms after its bus time is stale and dropped (never played late).
// * Beats that are throttled, stale or not playable still count, so the bar position never shifts.
// No clock is read here: every time is an argument (monotonic nanoseconds on the analysis bus's clock), so a
// stream gives the same decisions on every run. A value type; the pulse ring is allocated once in `init`.
// Plain Swift; builds and is tested on Linux.

/// What pulses (stored `settings.haptics.beatEvent`).
public enum HapticBeatChoice: String, Sendable, Hashable, CaseIterable, Codable {
    case beats
    case downbeats
    case kicks

    public var title: String {
        switch self {
        case .beats: "Beats"
        case .downbeats: "Downbeats"
        case .kicks: "Kicks"
        }
    }
}

/// How strong a pulse is (stored `settings.haptics.strength`).
public enum HapticPulseStrength: String, Sendable, Hashable, CaseIterable, Codable {
    case light
    case medium
    case strong

    public var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }
}

/// An analysis event as the gate sees it.
public enum HapticCue: Sendable, Hashable {
    /// ANL-005 beat with its confidence 0…1.
    case beat(confidence: Double)
    /// ANL-007 kick transient.
    case kick
    /// A session started or ended: the downbeat count restarts.
    case sessionBoundary
}

/// The gate's limits.
public struct HapticPulseRules: Sendable, Hashable {
    /// 150 ms, 4 per 1 s, 180 per 60 s, stale after 200 ms, 4 beats per bar, beat confidence ≥ 0.5 to engage and
    /// ≥ 0.4 to stay engaged.
    public static let standard = HapticPulseRules()

    public var minimumIntervalNanoseconds: UInt64
    public var burstWindowNanoseconds: UInt64
    public var burstLimit: Int
    public var dutyWindowNanoseconds: UInt64
    public var dutyLimit: Int
    public var staleAfterNanoseconds: UInt64
    public var beatsPerBar: Int
    public var minimumBeatConfidence: Double
    /// Once a beat reached `minimumBeatConfidence`, later beats stay selected down to this confidence.
    public var sustainBeatConfidence: Double

    public init(minimumIntervalNanoseconds: UInt64 = 150_000_000, burstWindowNanoseconds: UInt64 = 1_000_000_000,
                burstLimit: Int = 4, dutyWindowNanoseconds: UInt64 = 60_000_000_000, dutyLimit: Int = 180,
                staleAfterNanoseconds: UInt64 = 200_000_000, beatsPerBar: Int = 4, minimumBeatConfidence: Double = 0.5,
                sustainBeatConfidence: Double = 0.4) {
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
        self.burstWindowNanoseconds = burstWindowNanoseconds
        self.burstLimit = max(burstLimit, 1)
        self.dutyWindowNanoseconds = dutyWindowNanoseconds
        self.dutyLimit = max(dutyLimit, self.burstLimit)
        self.staleAfterNanoseconds = staleAfterNanoseconds
        self.beatsPerBar = max(beatsPerBar, 1)
        self.minimumBeatConfidence = minimumBeatConfidence
        self.sustainBeatConfidence = min(sustainBeatConfidence, minimumBeatConfidence)
    }
}

/// What the gate decided for one cue.
public enum HapticPulseDecision: Sendable, Hashable {
    /// Play a pulse now.
    case pulse
    /// Not a selected event (or a marker).
    case filtered
    /// Selected, but a condition blocks playing (background, Low Power Mode, no hardware, Strict).
    case suppressed
    /// Selected, but delivered too late.
    case stale
    /// Selected, but over a rate limit.
    case throttled
}

public struct HapticPulseGate: Sendable {
    public let rules: HapticPulseRules
    public var choice: HapticBeatChoice

    /// Confident beats since the last session marker.
    public private(set) var beatCount = 0
    public private(set) var pulses = 0
    public private(set) var throttledCount = 0
    public private(set) var staleCount = 0
    /// A beat reached `minimumBeatConfidence` and no weaker beat than `sustainBeatConfidence` or marker followed.
    public private(set) var beatsEngaged = false

    /// The last `dutyLimit` pulse times, oldest first from `ringStart`.
    private var ring: [UInt64]
    private var ringStart = 0
    private var ringCount = 0

    public init(choice: HapticBeatChoice = .beats, rules: HapticPulseRules = .standard) {
        self.rules = rules
        self.choice = choice
        ring = [UInt64](repeating: 0, count: rules.dutyLimit)
    }

    /// Forgets the beat count, the pulse history and the counters.
    public mutating func reset() {
        beatCount = 0
        pulses = 0
        throttledCount = 0
        staleCount = 0
        beatsEngaged = false
        ringStart = 0
        ringCount = 0
    }

    /// Decides one cue (contract C1). `playable` is false while a condition blocks pulses.
    public mutating func consider(_ cue: HapticCue, eventNanoseconds: UInt64, now: UInt64, playable: Bool) -> HapticPulseDecision {
        guard isSelected(cue) else { return .filtered }
        guard playable else { return .suppressed }
        if now > eventNanoseconds, now - eventNanoseconds > rules.staleAfterNanoseconds {
            staleCount += 1
            return .stale
        }
        guard allows(eventNanoseconds) else {
            throttledCount += 1
            return .throttled
        }
        record(eventNanoseconds)
        pulses += 1
        return .pulse
    }

    /// Counts beats (C1 steps 1–3) and says whether the cue is the chosen kind.
    private mutating func isSelected(_ cue: HapticCue) -> Bool {
        switch cue {
        case .sessionBoundary:
            beatCount = 0
            beatsEngaged = false
            return false
        case let .beat(confidence):
            let threshold = beatsEngaged ? rules.sustainBeatConfidence : rules.minimumBeatConfidence
            guard confidence >= threshold else {
                beatsEngaged = false
                return false
            }
            beatsEngaged = true
            beatCount += 1
            switch choice {
            case .beats: return true
            case .downbeats: return (beatCount - 1) % rules.beatsPerBar == 0
            case .kicks: return false
            }
        case .kick:
            return choice == .kicks
        }
    }

    /// The pulse `back` places before the newest (1 = the newest); nil when fewer pulses are recorded.
    private func recent(_ back: Int) -> UInt64? {
        guard back >= 1, back <= ringCount else { return nil }
        return ring[(ringStart + ringCount - back) % ring.count]
    }

    private func allows(_ time: UInt64) -> Bool {
        if let last = recent(1) {
            guard time >= last, time - last >= rules.minimumIntervalNanoseconds else { return false }
        }
        if let burst = recent(rules.burstLimit), time - burst < rules.burstWindowNanoseconds { return false }
        if let duty = recent(rules.dutyLimit), time - duty < rules.dutyWindowNanoseconds { return false }
        return true
    }

    private mutating func record(_ time: UInt64) {
        if ringCount == ring.count {
            ring[ringStart] = time
            ringStart = (ringStart + 1) % ring.count
        } else {
            ring[(ringStart + ringCount) % ring.count] = time
            ringCount += 1
        }
    }
}
