// LoudnessEnvelope.swift — the normalized short-term perceived level for automation (ANL-014-R1 to
// R6, R10, R11; research ANL-014-D1 to D4; contracts/loudness-envelope.md C2).
//
// Per ANL-001 spectrum frame:
// 1. Level: z = Σ_{k=1}^{N/2} w_k·m_k² / 3, w_k the K-weighting power response at bin k
//    (`KWeighting.table`), m_k the Hann magnitudes (a full-scale sine's Σ m² is 1.5 = 3 × its mean
//    square 0.5; the same factor holds for noise). L = −0.691 + 10·log10 z (BS.1770's LKFS offset:
//    a full-scale 997 Hz sine reads −3.01), or −120 when z is not finite or ≤ 1e-12. Non-finite
//    magnitudes count as 0.
// 2. Target: x = clamp((L − floor)/(ceiling − floor), 0, 1); standard −60…0 dB.
// 3. Envelope: ANL-003's one-pole follower e ← e + a·(x − e), a = `SmoothingTimes.coefficient`
//    with the attack time when x > e and the release time otherwise, Δt = hop / rate (the sample
//    clock). The first frame after `init` or `reset()` takes x directly. Then clamp to 0…1, and set
//    exactly 0 when x is 0 and e < 0.001.
// The documented whole-chain step lag (window plus smoother) is in the spec's Implementation results.
//
// Real-time safety (Constitution VII): the weight table is allocated in `init`; `process`
// allocates, locks, logs and reads no clock. Pure Swift (Linux, -DANALYSIS_NO_ACCELERATE).
// Nothing here reaches projectM (Constitution VIII, ADR-0008 decision 5).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum LoudnessConfigurationError: Error, Equatable, Sendable {
    /// The sample rate must be finite and above `KWeighting.minimumSampleRate`.
    case invalidSampleRate(Double)
    /// Floor and ceiling must be finite with floor < ceiling.
    case invalidRange(floor: Double, ceiling: Double)
}

public struct LoudnessConfiguration: Sendable, Hashable {
    /// 44.1 kHz, −60…0 dB, attack 100 ms, release 400 ms (spec Clarifications).
    public static let standard = try! LoudnessConfiguration()
    /// The reported level of silence (the existing level meter's floor), dB.
    public static let silenceDecibels: Double = -120
    /// Mean-squares at or below this read as silence.
    public static let silenceMeanSquare: Double = 1e-12
    /// BS.1770's offset between 10·log10(mean-square) and LKFS.
    public static let lkfsOffset: Double = -0.691
    /// Below this the released envelope is set to exactly 0.
    public static let snapToZero: Float = 0.001

    public let sampleRate: Double
    public let floorDecibels: Double
    public let ceilingDecibels: Double
    /// Attack and release as ANL-003 90 % times (clamped to 0…2 s), stored as seconds so the
    /// configuration stays Hashable.
    public let attackSeconds: Double
    public let releaseSeconds: Double
    public var times: SmoothingTimes { SmoothingTimes(attackSeconds: attackSeconds, releaseSeconds: releaseSeconds) }

    public init(sampleRate: Double = 44_100, floorDecibels: Double = -60, ceilingDecibels: Double = 0,
                times: SmoothingTimes = SmoothingTimes(attackSeconds: 0.1, releaseSeconds: 0.4)) throws(LoudnessConfigurationError) {
        guard sampleRate.isFinite, sampleRate > KWeighting.minimumSampleRate else { throw .invalidSampleRate(sampleRate) }
        guard floorDecibels.isFinite, ceilingDecibels.isFinite, floorDecibels < ceilingDecibels else {
            throw .invalidRange(floor: floorDecibels, ceiling: ceilingDecibels)
        }
        self.sampleRate = sampleRate
        self.floorDecibels = floorDecibels
        self.ceilingDecibels = ceilingDecibels
        attackSeconds = times.attackSeconds
        releaseSeconds = times.releaseSeconds
    }

    /// clamp((decibels − floor)/(ceiling − floor), 0, 1); 0 for non-finite input.
    public func normalized(decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        let span: Double = ceilingDecibels - floorDecibels
        let position: Double = (decibels - floorDecibels) / span
        return min(max(position, 0), 1)
    }
}

/// One frame's loudness.
public struct LoudnessReading: Sendable, Hashable {
    /// Silence: −120 dB, envelope 0.
    public static let silent = LoudnessReading(decibels: Float(LoudnessConfiguration.silenceDecibels), envelope: 0)

    /// The frame's unsmoothed K-weighted level, LKFS-like dB; −120 at silence; always finite.
    public let decibels: Float
    /// The smoothed normalized envelope, 0…1.
    public let envelope: Float

    public init(decibels: Float, envelope: Float) {
        self.decibels = decibels
        self.envelope = envelope
    }
}

/// The K-weighted loudness envelope of one spectrum stream. One owner (not shared across threads).
public struct LoudnessEnvelope: Sendable {
    public let configuration: LoudnessConfiguration
    public let size: FFTSize
    public private(set) var reading: LoudnessReading = .silent
    private let weights: [Float]
    private var primed = false

    /// Builds the K-weighting table for `size` (the only allocation).
    public init(configuration: LoudnessConfiguration = .standard, size: FFTSize = .n2048) {
        self.configuration = configuration
        self.size = size
        weights = KWeighting.table(size: size, sampleRate: configuration.sampleRate)
    }

    /// Back to `.silent`; the next frame takes its value directly (a session start).
    public mutating func reset() {
        reading = .silent
        primed = false
    }

    /// Updates and returns the reading for one ANL-001 spectrum (`magnitudes` = `size.binCount`
    /// linear magnitudes). Frames at another rate or size, or with a wrong count, leave it unchanged.
    @discardableResult
    public mutating func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> LoudnessReading {
        guard frame.sampleRate == configuration.sampleRate, frame.size == size,
              magnitudes.count == size.binCount else { return reading }
        let decibels: Double = weights.withUnsafeBufferPointer { (table: UnsafeBufferPointer<Float>) -> Double in
            Self.level(magnitudes: magnitudes, weights: table)
        }
        let target = Float(configuration.normalized(decibels: decibels))
        var envelope: Float
        if primed {
            let previous: Float = reading.envelope
            let rising: Bool = target > previous
            let timeConstant: Double = rising ? configuration.attackSeconds : configuration.releaseSeconds
            let interval: Double = Double(frame.hop) / frame.sampleRate
            let coefficient = Float(SmoothingTimes.coefficient(timeConstant: timeConstant, frameInterval: interval))
            envelope = previous + coefficient * (target - previous)
        } else {
            envelope = target
            primed = true
        }
        if !envelope.isFinite { envelope = target }
        envelope = min(max(envelope, 0), 1)
        if target == 0, envelope < LoudnessConfiguration.snapToZero { envelope = 0 }
        reading = LoudnessReading(decibels: Float(decibels), envelope: envelope)
        return reading
    }

    /// −0.691 + 10·log10(Σ_{k≥1} w_k·m_k² / 3) over the shorter of the two buffers, accumulated in
    /// Double; non-finite magnitudes count as 0; −120 at silence; never below −120, always finite.
    public static func level(magnitudes: UnsafeBufferPointer<Float>, weights: UnsafeBufferPointer<Float>) -> Double {
        let count: Int = min(magnitudes.count, weights.count)
        var sum: Double = 0
        if count > 1 {
            for k in 1..<count {
                let magnitude = Double(magnitudes[k])
                guard magnitude.isFinite else { continue }
                let weight = Double(weights[k])
                sum += weight * magnitude * magnitude
            }
        }
        let meanSquare: Double = sum / 3
        guard meanSquare.isFinite, meanSquare > LoudnessConfiguration.silenceMeanSquare else {
            return LoudnessConfiguration.silenceDecibels
        }
        let decibels: Double = LoudnessConfiguration.lkfsOffset + 10 * log10(meanSquare)
        return max(decibels, LoudnessConfiguration.silenceDecibels)
    }
}
