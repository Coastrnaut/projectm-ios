// StereoCorrelation.swift — stereo correlation and the phase-inversion warning (ANL-013-R1 to R4,
// R9, R10; research ANL-013-D1 to D4; contracts/stereo-correlation.md C1, C2).
//
// The meter reads the analysis tap's interleaved stereo (channels 0 = L and 1 = R) in blocks of
// `blockFrames` frames counted across calls, so the result depends only on the sample sequence, never
// on how it was chunked. Per block it sums Σ L·R, Σ L², Σ R² in Double, then smooths the sums and the
// sample weight W with a = exp(−B / (τ·rate)) (τ = 0.1 s):
//     S ← a·S + block,   r = clamp(S_LR / √(S_LL·S_RR), −1, 1).
// Identical channels give exactly 1, inverted exactly −1, independent noise ≈ 0. Smoothing the sums
// (not r) weights loud passages by their energy, the classic phase-meter definition.
//
// Silence (ANL-013-R2): when either channel's mean square over a block is at or below the floor
// (−70 dB re a full-scale sine, mean square 0.5·10⁻⁷), r = 0 with no signal and the smoothed sums are
// cleared, so silence, dither and a one-sided signal read 0 at once (never ±1 or NaN) and the next
// signal starts fresh. The smoothed mean squares S_xx / W are checked against the same floor. Non-finite
// samples count as 0.
//
// Warning (ANL-013-R3): per block, r < raiseBelow (−0.5) counts toward raising and r > clearAbove
// (−0.3) toward clearing; each counter restarts when its condition fails. `holdBlocks` (44 blocks,
// 1.02 s at 44.1 kHz) in a row raise or clear it. Counted in blocks: no clock.
//
// Mono and AUD-009 (ANL-013-R9): a mono source arrives as L = R, and AUD-009's Left, Right, Mid and
// Side write one signal into both channels, so r is exactly 1 above the floor and 0 below it; the
// warning cannot fire. Only Mix (stereo passed through) can show an inversion.
//
// Real-time safety (Constitution VII): a value type with no buffers; `append` allocates, locks, logs
// and reads no clock. A portable Double loop on every backend (three multiply-adds per frame), so it
// builds unchanged in the Linux shape. Nothing here reaches projectM (Constitution VIII).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum StereoCorrelationConfigurationError: Error, Equatable, Sendable {
    /// The sample rate must be finite and positive.
    case invalidSampleRate(Double)
    /// The block must hold 16…65,536 frames.
    case invalidBlock(Int)
    /// The time constant and the hold must be finite and positive.
    case invalidTime(Double)
    /// The floor must be finite and below 0 dB.
    case invalidFloor(Float)
    /// Thresholds must satisfy −1 < raiseBelow < clearAbove < 1.
    case invalidThresholds(raiseBelow: Float, clearAbove: Float)
}

public struct StereoCorrelationConfiguration: Sendable, Hashable {
    /// 44.1 kHz, 1,024-frame blocks, τ 0.1 s, −70 dB floor, raise < −0.5, clear > −0.3, 1 s holds.
    public static let standard = try! StereoCorrelationConfiguration()

    public let sampleRate: Double
    public let blockFrames: Int
    /// Smoothing time constant of the sums, seconds.
    public let timeConstant: Double
    /// Silence floor per channel, dB re a full-scale sine's mean square.
    public let floorDecibels: Float
    public let raiseBelow: Float
    public let clearAbove: Float
    public let holdSeconds: Double
    /// Per-block decay of the smoothed sums.
    public let decay: Double
    /// Mean square at the floor: 0.5 · 10^(floor/10).
    public let floorMeanSquare: Double
    /// Consecutive blocks that raise or clear the warning: ceil(hold · rate / block).
    public let holdBlocks: Int

    public init(sampleRate: Double = 44_100, blockFrames: Int = 1_024, timeConstant: Double = 0.1,
                floorDecibels: Float = -70, raiseBelow: Float = -0.5, clearAbove: Float = -0.3,
                holdSeconds: Double = 1.0) throws(StereoCorrelationConfigurationError) {
        guard sampleRate.isFinite, sampleRate > 0 else { throw .invalidSampleRate(sampleRate) }
        guard blockFrames >= 16, blockFrames <= 65_536 else { throw .invalidBlock(blockFrames) }
        guard timeConstant.isFinite, timeConstant > 0 else { throw .invalidTime(timeConstant) }
        guard holdSeconds.isFinite, holdSeconds > 0 else { throw .invalidTime(holdSeconds) }
        guard floorDecibels.isFinite, floorDecibels < 0 else { throw .invalidFloor(floorDecibels) }
        guard raiseBelow.isFinite, clearAbove.isFinite, raiseBelow > -1, raiseBelow < clearAbove, clearAbove < 1 else {
            throw .invalidThresholds(raiseBelow: raiseBelow, clearAbove: clearAbove)
        }
        self.sampleRate = sampleRate
        self.blockFrames = blockFrames
        self.timeConstant = timeConstant
        self.floorDecibels = floorDecibels
        self.raiseBelow = raiseBelow
        self.clearAbove = clearAbove
        self.holdSeconds = holdSeconds
        let blockSeconds: Double = Double(blockFrames) / sampleRate
        decay = exp(-blockSeconds / timeConstant)
        let exponent: Double = Double(floorDecibels) / 10
        floorMeanSquare = 0.5 * pow(10, exponent)
        let blocks: Double = (holdSeconds / blockSeconds).rounded(.up)
        holdBlocks = max(1, Int(min(blocks, 1_000_000)))
    }
}

/// The meter's latest reading.
public struct StereoCorrelationReading: Sendable, Hashable {
    /// No signal, no warning.
    public static let none = StereoCorrelationReading(correlation: 0, hasSignal: false, phaseInverted: false)

    /// −1 (inverted) … 1 (identical); 0 without signal.
    public let correlation: Float
    /// Both channels were above the floor at the last block.
    public let hasSignal: Bool
    /// The phase-inversion warning (hysteresis, contract C2).
    public let phaseInverted: Bool

    public init(correlation: Float, hasSignal: Bool, phaseInverted: Bool) {
        self.correlation = correlation
        self.hasSignal = hasSignal
        self.phaseInverted = phaseInverted
    }
}

public struct StereoCorrelationMeter: Sendable {
    public let configuration: StereoCorrelationConfiguration
    public private(set) var reading: StereoCorrelationReading = .none

    private var blockLR: Double = 0
    private var blockLL: Double = 0
    private var blockRR: Double = 0
    private var blockCount: Int = 0
    private var smoothLR: Double = 0
    private var smoothLL: Double = 0
    private var smoothRR: Double = 0
    private var weight: Double = 0
    private var raiseRun: Int = 0
    private var clearRun: Int = 0
    private var warning = false

    public init(configuration: StereoCorrelationConfiguration = .standard) {
        self.configuration = configuration
    }

    /// Back to `.none` with every sum and counter zeroed (a session start).
    public mutating func reset() {
        reading = .none
        blockLR = 0
        blockLL = 0
        blockRR = 0
        blockCount = 0
        smoothLR = 0
        smoothLL = 0
        smoothRR = 0
        weight = 0
        raiseRun = 0
        clearRun = 0
        warning = false
    }

    /// Reads `frames` interleaved frames of `channels` channels (L = 0, R = 1; channels < 2 is ignored).
    public mutating func append(interleaved samples: UnsafePointer<Float>, frames: Int, channels: Int) {
        guard channels >= 2, frames > 0 else { return }
        let block: Int = configuration.blockFrames
        var index = 0
        while index < frames {
            let offset: Int = index * channels
            let left: Double = Self.finite(samples[offset])
            let right: Double = Self.finite(samples[offset + 1])
            blockLR += left * right
            blockLL += left * left
            blockRR += right * right
            blockCount += 1
            if blockCount == block { finishBlock() }
            index += 1
        }
    }

    /// Convenience for tests and callers holding an array.
    public mutating func append(interleaved samples: [Float], channels: Int = 2) {
        guard channels >= 2 else { return }
        samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            guard let base = buffer.baseAddress else { return }
            append(interleaved: base, frames: buffer.count / channels, channels: channels)
        }
    }

    private static func finite(_ value: Float) -> Double {
        value.isFinite ? Double(value) : 0
    }

    private mutating func finishBlock() {
        let frames: Double = Double(configuration.blockFrames)
        let floor: Double = configuration.floorMeanSquare
        // A block at or below the floor on either channel reads 0 at once and forgets the history, so
        // silence (or a one-sided passage) never keeps the last correlation while the sums decay.
        let silent: Bool = !(blockLL / frames > floor) || !(blockRR / frames > floor)
        if silent {
            smoothLR = 0
            smoothLL = 0
            smoothRR = 0
            weight = 0
        } else {
            let a: Double = configuration.decay
            smoothLR = a * smoothLR + blockLR
            smoothLL = a * smoothLL + blockLL
            smoothRR = a * smoothRR + blockRR
            weight = a * weight + frames
        }
        blockLR = 0
        blockLL = 0
        blockRR = 0
        blockCount = 0
        let value: (correlation: Float, hasSignal: Bool) = silent ? (0, false) : currentCorrelation()
        stepWarning(value.correlation)
        reading = StereoCorrelationReading(correlation: value.correlation, hasSignal: value.hasSignal, phaseInverted: warning)
    }

    private func currentCorrelation() -> (correlation: Float, hasSignal: Bool) {
        guard weight > 0 else { return (0, false) }
        let floor: Double = configuration.floorMeanSquare
        let meanLL: Double = smoothLL / weight
        let meanRR: Double = smoothRR / weight
        guard meanLL.isFinite, meanRR.isFinite, meanLL > floor, meanRR > floor else { return (0, false) }
        let denominator: Double = (smoothLL * smoothRR).squareRoot()
        guard denominator > 0, denominator.isFinite else { return (0, false) }
        let ratio: Double = smoothLR / denominator
        guard ratio.isFinite else { return (0, false) }
        return (Float(min(max(ratio, -1), 1)), true)
    }

    private mutating func stepWarning(_ correlation: Float) {
        raiseRun = correlation < configuration.raiseBelow ? raiseRun + 1 : 0
        clearRun = correlation > configuration.clearAbove ? clearRun + 1 : 0
        if !warning, raiseRun >= configuration.holdBlocks {
            warning = true
        } else if warning, clearRun >= configuration.holdBlocks {
            warning = false
        }
    }
}
