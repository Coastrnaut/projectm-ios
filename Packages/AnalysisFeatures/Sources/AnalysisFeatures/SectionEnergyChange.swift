// SectionEnergyChange.swift — sustained quiet/loud section changes (ANL-015-R1 to R8, R11; research
// ANL-015-D1 to D4; contracts/section-energy-change.md C1-C3).
//
// Input: ANL-014's per-frame K-weighted level (LKFS-like dB) and the frame's window end on the
// session's sample clock. Levels below the floor (−70 dB) or non-finite count as the floor.
//
// Slow level S: 10·log10 of the mean power of the last `windowFrames` frames (35 × 512 samples ≈
// 0.41 s, BS.1770's momentary span), recomputed from the stored powers every frame (no running-sum
// drift, so results are bit-deterministic). Rectangular, so a rise shows within a frame or two and a
// burst is forgotten one window after it ends.
//
// Reference R: during the first `settleSamples` of a session R = S and nothing can happen (the
// opening level is not a change). Afterwards R follows S with a one-pole time constant (8 s) while no
// change is pending, is frozen while one is pending, and is set to S when one fires.
//
// Changes: idle and |S − R| ≥ enter (6 dB) → pending in that direction, started at this frame's window
// end; pending and (S − R)·sign ≤ hold (3 dB) → cancelled; pending and window end − start ≥ dwell
// (2.0 s in samples) → fired. After a fire, nothing becomes pending for `refractorySamples` (4.0 s).
// Envelope: 1 on a fired frame, × exp(−hop/(τ·rate)) per frame otherwise (τ = 1 s), 0 below 0.001.
//
// Everything is counted on the frames' sample clock: no wall clock, and frames depend only on the
// sample sequence, so results do not depend on chunking or on the FFT backend's speed.
//
// Real-time safety (Constitution VII): the power history is allocated once in `init` (at most 64
// Doubles); `process` writes it in place (the detector is owned by one worker, so the buffer is never
// shared and never copied) and allocates, locks, logs and reads no clock. Portable Swift: it builds
// unchanged in the Linux shape (`-DANALYSIS_NO_ACCELERATE`). Nothing here reaches projectM
// (Constitution VIII).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum SectionChangeConfigurationError: Error, Equatable, Sendable {
    /// The sample rate must be finite and positive.
    case invalidSampleRate(Double)
    /// The hop must be 1…65,536 samples.
    case invalidHop(Int)
    /// The slow window must hold 1…`SectionChangeDetector.maximumWindowFrames` frames.
    case invalidWindow(Int)
    /// The floor must be finite and below 0 dB.
    case invalidFloor(Float)
    /// Times must be finite; settle and refractory ≥ 0, the others > 0.
    case invalidTime(Double)
    /// Thresholds must be finite with 0 ≤ hold < enter.
    case invalidThresholds(enter: Float, hold: Float)
}

public struct SectionChangeConfiguration: Sendable, Hashable {
    /// 44.1 kHz, hop 512, 35-frame slow window, −70 dB floor, 2 s settle, 8 s reference, enter 6 dB,
    /// hold 3 dB, 2 s dwell, 4 s refractory, 1 s envelope.
    public static let standard = try! SectionChangeConfiguration()

    public let sampleRate: Double
    public let hop: Int
    public let windowFrames: Int
    public let floorDecibels: Float
    public let settleSeconds: Double
    public let referenceSeconds: Double
    public let enterDecibels: Float
    public let holdDecibels: Float
    public let dwellSeconds: Double
    public let refractorySeconds: Double
    public let envelopeSeconds: Double

    /// Derived sample counts (rounded to the nearest sample).
    public let settleSamples: Int64
    public let dwellSamples: Int64
    public let refractorySamples: Int64
    /// Per-frame reference follower coefficient: 1 − exp(−hop / (τ·rate)).
    public let referenceCoefficient: Double
    /// Per-frame envelope decay: exp(−hop / (τ·rate)).
    public let envelopeDecay: Float

    public init(sampleRate: Double = 44_100, hop: Int = 512, windowFrames: Int = 35, floorDecibels: Float = -70,
                settleSeconds: Double = 2.0, referenceSeconds: Double = 8.0,
                enterDecibels: Float = 6, holdDecibels: Float = 3,
                dwellSeconds: Double = 2.0, refractorySeconds: Double = 4.0,
                envelopeSeconds: Double = 1.0) throws(SectionChangeConfigurationError) {
        guard sampleRate.isFinite, sampleRate > 0 else { throw .invalidSampleRate(sampleRate) }
        guard hop >= 1, hop <= 65_536 else { throw .invalidHop(hop) }
        guard windowFrames >= 1, windowFrames <= SectionChangeDetector.maximumWindowFrames else {
            throw .invalidWindow(windowFrames)
        }
        guard floorDecibels.isFinite, floorDecibels < 0 else { throw .invalidFloor(floorDecibels) }
        for value in [settleSeconds, refractorySeconds] where !(value.isFinite && value >= 0 && value <= 3_600) {
            throw .invalidTime(value)
        }
        for value in [referenceSeconds, dwellSeconds, envelopeSeconds] where !(value.isFinite && value > 0 && value <= 3_600) {
            throw .invalidTime(value)
        }
        guard enterDecibels.isFinite, holdDecibels.isFinite, holdDecibels >= 0, holdDecibels < enterDecibels else {
            throw .invalidThresholds(enter: enterDecibels, hold: holdDecibels)
        }
        self.sampleRate = sampleRate
        self.hop = hop
        self.windowFrames = windowFrames
        self.floorDecibels = floorDecibels
        self.settleSeconds = settleSeconds
        self.referenceSeconds = referenceSeconds
        self.enterDecibels = enterDecibels
        self.holdDecibels = holdDecibels
        self.dwellSeconds = dwellSeconds
        self.refractorySeconds = refractorySeconds
        self.envelopeSeconds = envelopeSeconds
        settleSamples = Self.samples(settleSeconds, rate: sampleRate)
        dwellSamples = Self.samples(dwellSeconds, rate: sampleRate)
        refractorySamples = Self.samples(refractorySeconds, rate: sampleRate)
        let frameSeconds: Double = Double(hop) / sampleRate
        referenceCoefficient = 1 - exp(-frameSeconds / referenceSeconds)
        envelopeDecay = Float(exp(-frameSeconds / envelopeSeconds))
    }

    private static func samples(_ seconds: Double, rate: Double) -> Int64 {
        Int64((seconds * rate).rounded())
    }
}

/// Which way the level moved.
public enum SectionChangeDirection: Sendable, Hashable {
    /// Quiet → loud.
    case rising
    /// Loud → quiet.
    case falling
}

/// One fired section change.
public struct SectionChange: Sendable, Hashable {
    public let direction: SectionChangeDirection
    /// The slow level when the change was confirmed, dB.
    public let levelDecibels: Float
    /// The reference it moved away from, dB.
    public let referenceDecibels: Float
    /// Window end of the frame that started the change (where the new level was first seen).
    public let startSample: Int64
    /// Window end of the frame that confirmed it (start + dwell or later).
    public let confirmSample: Int64

    public init(direction: SectionChangeDirection, levelDecibels: Float, referenceDecibels: Float,
                startSample: Int64, confirmSample: Int64) {
        self.direction = direction
        self.levelDecibels = levelDecibels
        self.referenceDecibels = referenceDecibels
        self.startSample = startSample
        self.confirmSample = confirmSample
    }
}

/// The section change detector of one analysis stream. One owner (not shared across threads).
public struct SectionChangeDetector: Sendable {
    /// The largest slow window, in frames.
    public static let maximumWindowFrames = 64
    /// The envelope is set to 0 below this.
    public static let snapToZero: Float = 0.001

    private enum Phase: Sendable, Hashable {
        case idle
        case pending(direction: SectionChangeDirection, start: Int64)
        case refractory(until: Int64)
    }

    public let configuration: SectionChangeConfiguration
    /// The slow level S, dB (the floor before any frame).
    public private(set) var levelDecibels: Float
    /// The reference R, dB (the floor before any frame).
    public private(set) var referenceDecibels: Float
    /// 1 on the frame of a change, decaying to exactly 0.
    public private(set) var envelope: Float = 0

    private var powers: [Double]
    private var next = 0
    private var filled = 0
    private var reference: Double
    private var phase: Phase = .idle

    /// Allocates the power history (the only allocation).
    public init(configuration: SectionChangeConfiguration = .standard) {
        self.configuration = configuration
        powers = [Double](repeating: 0, count: configuration.windowFrames)
        levelDecibels = configuration.floorDecibels
        referenceDecibels = configuration.floorDecibels
        reference = Double(configuration.floorDecibels)
    }

    /// True while a change waits for its dwell.
    public var isPending: Bool {
        if case .pending = phase { return true }
        return false
    }

    /// Back to the state at creation (a session start); keeps the history's storage.
    public mutating func reset() {
        for index in powers.indices { powers[index] = 0 }
        next = 0
        filled = 0
        levelDecibels = configuration.floorDecibels
        referenceDecibels = configuration.floorDecibels
        reference = Double(configuration.floorDecibels)
        envelope = 0
        phase = .idle
    }

    /// Feeds one frame: ANL-014's unsmoothed level (dB) and the frame's window end on the session's
    /// sample clock. Returns the change this frame confirmed, if any.
    @discardableResult
    public mutating func process(levelDecibels level: Float, frameEnd: Int64) -> SectionChange? {
        let slow: Double = pushLevel(level)
        levelDecibels = Float(slow)
        decayEnvelope()
        guard frameEnd >= configuration.settleSamples else {
            // Settling: the session's opening level becomes the reference.
            reference = slow
            phase = .idle
            referenceDecibels = Float(reference)
            return nil
        }
        if case let .refractory(until) = phase, frameEnd >= until { phase = .idle }
        var fired: SectionChange?
        switch phase {
        case .refractory:
            follow(slow)
        case .idle:
            startOrFollow(slow, frameEnd: frameEnd)
        case let .pending(direction, start):
            fired = continuePending(slow, direction: direction, start: start, frameEnd: frameEnd)
        }
        referenceDecibels = Float(reference)
        return fired
    }

    // MARK: Steps

    /// Stores the frame's power and returns the slow level in dB (finite, at least the floor).
    private mutating func pushLevel(_ level: Float) -> Double {
        let floor = Double(configuration.floorDecibels)
        var decibels = Double(level)
        if !decibels.isFinite || decibels < floor { decibels = floor }
        powers[next] = pow(10, decibels / 10)
        next = next + 1 == powers.count ? 0 : next + 1
        filled = min(filled + 1, powers.count)
        var sum: Double = 0
        for index in 0..<filled { sum += powers[index] }
        let mean: Double = sum / Double(filled)
        let slow: Double = 10 * log10(mean)
        return slow.isFinite ? max(slow, floor) : floor
    }

    private mutating func decayEnvelope() {
        let decayed: Float = envelope * configuration.envelopeDecay
        envelope = decayed < Self.snapToZero ? 0 : decayed
    }

    private mutating func follow(_ slow: Double) {
        reference += configuration.referenceCoefficient * (slow - reference)
    }

    private mutating func startOrFollow(_ slow: Double, frameEnd: Int64) {
        let delta: Double = slow - reference
        let enter = Double(configuration.enterDecibels)
        if delta >= enter {
            phase = .pending(direction: .rising, start: frameEnd)
        } else if delta <= -enter {
            phase = .pending(direction: .falling, start: frameEnd)
        } else {
            follow(slow)
        }
    }

    private mutating func continuePending(_ slow: Double, direction: SectionChangeDirection, start: Int64,
                                          frameEnd: Int64) -> SectionChange? {
        let sign: Double = direction == .rising ? 1 : -1
        let beyond: Double = (slow - reference) * sign
        guard beyond > Double(configuration.holdDecibels) else {
            phase = .idle
            follow(slow)
            return nil
        }
        guard frameEnd - start >= configuration.dwellSamples else { return nil }
        let change = SectionChange(direction: direction, levelDecibels: Float(slow), referenceDecibels: Float(reference),
                                   startSample: start, confirmSample: frameEnd)
        reference = slow
        phase = .refractory(until: frameEnd + configuration.refractorySamples)
        envelope = 1
        return change
    }
}
