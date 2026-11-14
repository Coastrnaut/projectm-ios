// InputTrim.swift — AUD-008: a bounded gain on the analysis copy of the audio only
// (specs/086-aud-008-input-trim, contracts/input-trim.md C1-C4; research AUD-008-D1 to D5).
//
// Where it sits: `InputTrimReader` wraps the normalized ring's analysis tap (ANL-001-R9). Each read
// forwards to the tap, which copies frames out of its own ring into the consumer's buffer; only then
// are those frames scaled, in that buffer. The tap's ring, the main ring projectM reads, the PCM sink,
// the audio-state classifier's levels and playback never see the gain.
//
// Law: g = 10^(dB/20), dB clamped to −12…+24 (NaN → 0). At unity gain with no ramp the read returns
// the tap's samples bit-identical. Otherwise y = softClip(x · g): linear up to the knee at 0.5
// (−6 dBFS), then a cubic that reaches ±1 with zero slope at |v| = 1.25 and stays there; NaN → 0, so
// the output is always finite and in [−1, 1]. Gain changes ramp linearly in linear gain over 2,048
// frames (one 2,048-point FFT window), carried across reads; a new reader and a new capture session
// (ANL-016-R9) start at the target.
//
// Real-time safety (Constitution VII): the processor is scalar state only; a read does one relaxed
// atomic load and arithmetic, never allocates, locks or logs. It runs on the analysis worker, never on
// an audio callback. One consumer thread per reader (like the tap itself).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(ucrt)
import ucrt
#endif
import Synchronization

/// The trim's range, gain law and saturation (contract C1).
public enum InputTrim {
    public static let minimumDecibels: Float = -12
    public static let maximumDecibels: Float = 24
    public static let defaultDecibels: Float = 0
    /// Frames over which one gain change is spread (≈ 46 ms at 44.1 kHz).
    public static let rampFrames = 2_048
    /// Below this magnitude the soft clip is the identity (−6 dBFS).
    public static let kneeLevel: Float = 0.5
    /// From this magnitude on the soft clip returns ±1.
    public static let clipStart: Float = 1.25

    /// NaN → 0 dB; otherwise clamped to the range.
    public static func clamped(_ decibels: Float) -> Float {
        guard !decibels.isNaN else { return defaultDecibels }
        return min(max(decibels, minimumDecibels), maximumDecibels)
    }

    /// 10^(dB/20) of the clamped value; exactly 1 at 0 dB.
    public static func linearGain(decibels: Float) -> Float {
        let db = clamped(decibels)
        if db == 0 { return 1 }
        let exponent: Float = db / 20
        return powf(10, exponent)
    }

    /// Odd, monotonic, bounded in [−1, 1]; identity up to the knee, smooth into ±1 at `clipStart`.
    @inline(__always)
    public static func softClip(_ value: Float) -> Float {
        if value.isNaN { return 0 }
        let magnitude: Float = abs(value)
        if magnitude <= kneeLevel { return value }
        if magnitude >= clipStart { return value > 0 ? 1 : -1 }
        let width: Float = 1 - kneeLevel                       // 0.5
        let u: Float = (magnitude - kneeLevel) / width          // 0 … 1.5
        let cubic: Float = u * u * u * (4.0 / 27.0)
        let shaped: Float = kneeLevel + width * (u - cubic)     // f(1.5) = 1, f'(1.5) = 0
        return value > 0 ? shaped : -shaped
    }

    /// The largest per-frame gain change any ramp can make.
    public static var maximumRampStep: Float {
        let span: Float = linearGain(decibels: maximumDecibels) - linearGain(decibels: minimumDecibels)
        return span / Float(rampFrames)
    }
}

/// The shared target in dB: written by the app (any thread), read by each analysis read (contract C2).
public final class InputTrimControl: Sendable {
    private let bits: Atomic<UInt32>

    public init(decibels: Float = InputTrim.defaultDecibels) {
        bits = Atomic(InputTrim.clamped(decibels).bitPattern)
    }

    /// Always within the range; storing NaN stores 0 dB. Lock-free.
    public var decibels: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        set { bits.store(InputTrim.clamped(newValue).bitPattern, ordering: .relaxed) }
    }
}

/// The per-reader gain state and processing (contract C3). Scalar state only.
public struct InputTrimProcessor: Sendable {
    public private(set) var gain: Float
    private var targetGain: Float
    private var targetDecibels: Float
    /// Gain where the active ramp began, and its per-frame increment.
    private var rampStart: Float = 1
    private var step: Float = 0
    private var remaining: Int = 0

    /// Settled at the target.
    public init(decibels: Float) {
        let db = InputTrim.clamped(decibels)
        targetDecibels = db
        targetGain = InputTrim.linearGain(decibels: db)
        gain = targetGain
    }

    /// Unity gain and no ramp: processing would change nothing.
    public var isUnity: Bool { remaining == 0 && gain == 1 }

    /// A new target starts a ramp from the current gain; the same target changes nothing.
    public mutating func setTarget(decibels: Float) {
        let db = InputTrim.clamped(decibels)
        guard db != targetDecibels else { return }
        targetDecibels = db
        targetGain = InputTrim.linearGain(decibels: db)
        let distance: Float = targetGain - gain
        rampStart = gain
        step = distance / Float(InputTrim.rampFrames)
        remaining = InputTrim.rampFrames
    }

    /// Settles at the target at once (a new capture session).
    public mutating func snap(decibels: Float) {
        let db = InputTrim.clamped(decibels)
        targetDecibels = db
        targetGain = InputTrim.linearGain(decibels: db)
        gain = targetGain
        step = 0
        remaining = 0
    }

    /// Scales and soft-clips `frames` interleaved frames of `channels` samples in place. Bit-exact
    /// (returns at once) at unity.
    public mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard frames > 0, channels > 0, !isUnity else { return }
        var index = 0
        for _ in 0..<frames {
            if remaining > 0 {
                // Computed from the ramp's start (not accumulated), so rounding never builds up
                // into a step at the end; the last frame lands exactly on the target.
                remaining -= 1
                let done = Float(InputTrim.rampFrames - remaining)
                gain = remaining == 0 ? targetGain : rampStart + step * done
            }
            let g = gain
            for _ in 0..<channels {
                samples[index] = InputTrim.softClip(samples[index] * g)
                index += 1
            }
        }
    }
}

/// The analysis tap seen through the trim (contract C4). One consumer thread only.
public final class InputTrimReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    private let reader: any NormalizedPCMReader
    /// The wrapped reader's session reporting, cast once (no cast per read).
    private let reporting: (any AnalysisSessionReporting)?
    private let control: InputTrimControl
    private var processor: InputTrimProcessor   // reader-thread-owned
    private var generation: UInt64

    public init(_ reader: any NormalizedPCMReader, control: InputTrimControl) {
        self.reader = reader
        reporting = reader as? any AnalysisSessionReporting
        self.control = control
        processor = InputTrimProcessor(decibels: control.decibels)
        generation = reporting?.analysisSessionGeneration ?? 0
    }

    /// Forwarded; 0 when the wrapped reader reports none.
    public var analysisSessionGeneration: UInt64 { reporting?.analysisSessionGeneration ?? 0 }

    public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let frames = reader.read(into: dst, maxFrames: maxFrames)
        guard frames > 0 else { return frames }
        let target = control.decibels
        let current = analysisSessionGeneration
        if current != generation {
            generation = current
            processor.snap(decibels: target)
        } else {
            processor.setTarget(decibels: target)
        }
        processor.process(dst, frames: frames, channels: NormalizedPCMRing.channelCount)
        return frames
    }
}
