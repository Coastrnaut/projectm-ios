// NoiseGate.swift — AUD-011: a downward noise gate on the analysis copy of the audio only
// (specs/091-aud-011-input-noise-gate, contracts/noise-gate.md C1-C4; research AUD-011-D1 to D6).
//
// Where it sits: tap → `ChannelSelectionReader` (AUD-009) → `InputTrimReader` (AUD-008) →
// `NoiseGateReader` → `WaveformTap` (VIS-003) → analysis pipeline. Each read forwards to the wrapped
// reader, which fills the consumer's buffer; only then are those frames gated, in that buffer. The
// tap's ring, projectM's ring, the PCM sink, the audio-state classifier and playback never see it.
// The app makes it active only while the source is the microphone (AUD-011-R3).
//
// Law (R4, R5): per frame the detector e = max(max(|L|, |R|), e · r), r = exp(−1/(10 ms · 44.1 kHz)),
// NaN counts as 0. Closed (gain 0) → e ≥ open threshold: attack, the gain rises by 1/attackFrames per
// frame to 1 (open). Open: e ≥ close threshold (open − hysteresis) re-arms the hold; after holdFrames
// below it, release: the gain falls by 1/releaseFrames per frame to 0 (closed). During release
// e ≥ open threshold starts the attack again from the current gain. Gain 0 writes exact zeros; gain 1
// leaves the samples bit-identical; inactive returns at once (bit-exact).
//
// Real-time safety (Constitution VII): scalar state only; a read does three relaxed atomic loads and
// arithmetic, never allocates, locks or logs (`powf` runs only when the threshold changed). It runs on
// the analysis worker, never on an audio callback. One consumer thread per reader.
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

/// Constants and conversions of the gate (contract C1).
public enum NoiseGate {
    public static let sampleRate: Float = Float(NormalizedPCMRing.sampleRate)
    /// The detector's release time constant.
    public static let detectorReleaseSeconds: Float = 0.010
    public static let minimumThresholdDecibels: Float = -80
    public static let maximumThresholdDecibels: Float = -20
    public static let defaultThresholdDecibels: Float = -50

    /// NaN → default; otherwise clamped to −80…−20 dBFS.
    public static func clampedThreshold(_ decibels: Float) -> Float {
        clamp(decibels, minimumThresholdDecibels, maximumThresholdDecibels, default: defaultThresholdDecibels)
    }

    /// 10^(dB/20).
    public static func linear(decibels: Float) -> Float {
        let exponent: Float = decibels / 20
        return powf(10, exponent)
    }

    /// The per-frame decay factor of the detector envelope.
    public static var detectorDecay: Float {
        let frames: Float = detectorReleaseSeconds * sampleRate
        let exponent: Float = -1 / frames
        return expf(exponent)
    }

    static func clamp(_ value: Float, _ low: Float, _ high: Float, default fallback: Float) -> Float {
        guard !value.isNaN else { return fallback }
        return min(max(value, low), high)
    }

    static func frames(seconds: Float, minimum: Int) -> Int {
        let exact: Float = seconds * sampleRate
        return max(minimum, Int(exact.rounded()))
    }
}

/// The gate's thresholds and times, each bounded (AUD-011-R6).
public struct NoiseGateParameters: Sendable, Equatable {
    public let openDecibels: Float
    public let hysteresisDecibels: Float
    public let attackSeconds: Float
    public let holdSeconds: Float
    public let releaseSeconds: Float

    public static let `default` = NoiseGateParameters()

    public init(openDecibels: Float = NoiseGate.defaultThresholdDecibels,
                hysteresisDecibels: Float = 6,
                attackSeconds: Float = 0.005,
                holdSeconds: Float = 0.100,
                releaseSeconds: Float = 0.150) {
        self.openDecibels = NoiseGate.clampedThreshold(openDecibels)
        self.hysteresisDecibels = NoiseGate.clamp(hysteresisDecibels, 0, 20, default: 6)
        self.attackSeconds = NoiseGate.clamp(attackSeconds, 0.0005, 0.050, default: 0.005)
        self.holdSeconds = NoiseGate.clamp(holdSeconds, 0, 1, default: 0.100)
        self.releaseSeconds = NoiseGate.clamp(releaseSeconds, 0.010, 2, default: 0.150)
    }

    /// The same parameters with another open threshold.
    public func with(openDecibels: Float) -> NoiseGateParameters {
        NoiseGateParameters(openDecibels: openDecibels, hysteresisDecibels: hysteresisDecibels,
                            attackSeconds: attackSeconds, holdSeconds: holdSeconds, releaseSeconds: releaseSeconds)
    }

    public var closeDecibels: Float { openDecibels - hysteresisDecibels }
    public var attackFrames: Int { NoiseGate.frames(seconds: attackSeconds, minimum: 1) }
    public var holdFrames: Int { NoiseGate.frames(seconds: holdSeconds, minimum: 0) }
    public var releaseFrames: Int { NoiseGate.frames(seconds: releaseSeconds, minimum: 1) }
}

/// The shared settings: written by the app (any thread), read by each analysis read (contract C2).
public final class NoiseGateControl: Sendable {
    private let enabled: Atomic<Bool>
    private let microphone: Atomic<Bool>
    private let thresholdBits: Atomic<UInt32>

    public init(isEnabled: Bool = false, isMicrophoneSource: Bool = false,
                openDecibels: Float = NoiseGate.defaultThresholdDecibels) {
        enabled = Atomic(isEnabled)
        microphone = Atomic(isMicrophoneSource)
        thresholdBits = Atomic(NoiseGate.clampedThreshold(openDecibels).bitPattern)
    }

    /// The user's on/off. Lock-free.
    public var isEnabled: Bool {
        get { enabled.load(ordering: .relaxed) }
        set { enabled.store(newValue, ordering: .relaxed) }
    }

    /// Set by the app while the active source is the microphone. Lock-free.
    public var isMicrophoneSource: Bool {
        get { microphone.load(ordering: .relaxed) }
        set { microphone.store(newValue, ordering: .relaxed) }
    }

    /// Always within −80…−20 dBFS; storing NaN stores −50. Lock-free.
    public var openDecibels: Float {
        get { Float(bitPattern: thresholdBits.load(ordering: .relaxed)) }
        set { thresholdBits.store(NoiseGate.clampedThreshold(newValue).bitPattern, ordering: .relaxed) }
    }

    /// Enabled and the source is the microphone.
    public var isActive: Bool { isEnabled && isMicrophoneSource }
}

/// The per-reader detector, state machine and gain (contract C3). Scalar state only.
public struct NoiseGateProcessor: Sendable {
    public enum Phase: Sendable, Equatable {
        case closed, attack, open, release
    }

    public private(set) var parameters: NoiseGateParameters
    public private(set) var gain: Float = 0
    public private(set) var envelope: Float = 0
    public private(set) var phase: Phase = .closed
    private var holdRemaining: Int
    private var openLinear: Float
    private var closeLinear: Float
    private let decay: Float
    private let attackStep: Float
    private let releaseStep: Float
    private let holdFrames: Int

    /// Closed, with an empty envelope.
    public init(parameters: NoiseGateParameters = .default) {
        self.parameters = parameters
        openLinear = NoiseGate.linear(decibels: parameters.openDecibels)
        closeLinear = NoiseGate.linear(decibels: parameters.closeDecibels)
        decay = NoiseGate.detectorDecay
        attackStep = 1 / Float(parameters.attackFrames)
        releaseStep = 1 / Float(parameters.releaseFrames)
        holdFrames = parameters.holdFrames
        holdRemaining = holdFrames
    }

    /// A new open threshold (the close threshold follows); the same value changes nothing.
    public mutating func setOpenThreshold(decibels: Float) {
        let db = NoiseGate.clampedThreshold(decibels)
        guard db != parameters.openDecibels else { return }
        parameters = parameters.with(openDecibels: db)
        openLinear = NoiseGate.linear(decibels: parameters.openDecibels)
        closeLinear = NoiseGate.linear(decibels: parameters.closeDecibels)
    }

    /// Closed, gain 0, empty envelope (activation or a new capture session).
    public mutating func reset() {
        gain = 0
        envelope = 0
        phase = .closed
        holdRemaining = holdFrames
    }

    /// Gates `frames` interleaved frames of `channels` samples in place.
    public mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard frames > 0, channels > 0 else { return }
        for frame in 0..<frames {
            let base = frame * channels
            var peak: Float = 0
            for channel in 0..<channels {
                let magnitude: Float = abs(samples[base + channel])
                if magnitude > peak { peak = magnitude }   // NaN never compares greater: counted as 0
            }
            let decayed: Float = envelope * decay
            envelope = peak > decayed ? peak : decayed
            advance()
            let g = gain
            if g == 0 {
                for channel in 0..<channels { samples[base + channel] = 0 }
            } else if g != 1 {
                for channel in 0..<channels { samples[base + channel] *= g }
            }
        }
    }

    /// One frame of the state machine and the gain ramp.
    @inline(__always)
    private mutating func advance() {
        switch phase {
        case .closed, .release:
            if envelope >= openLinear { phase = .attack }
        case .open:
            if envelope >= closeLinear {
                holdRemaining = holdFrames
            } else if holdRemaining > 0 {
                holdRemaining -= 1
            } else {
                phase = .release
            }
        case .attack:
            break
        }
        switch phase {
        case .attack:
            let next: Float = gain + attackStep
            if next >= 1 {
                gain = 1
                phase = .open
                holdRemaining = holdFrames
            } else {
                gain = next
            }
        case .release:
            let next: Float = gain - releaseStep
            if next <= 0 {
                gain = 0
                phase = .closed
            } else {
                gain = next
            }
        case .closed, .open:
            break
        }
    }
}

/// The analysis tap seen through the gate (contract C4). One consumer thread only.
public final class NoiseGateReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    private let reader: any NormalizedPCMReader
    /// The wrapped reader's session reporting, cast once (no cast per read).
    private let reporting: (any AnalysisSessionReporting)?
    private let control: NoiseGateControl
    private var processor: NoiseGateProcessor   // reader-thread-owned
    private var wasActive = false
    private var generation: UInt64

    public init(_ reader: any NormalizedPCMReader, control: NoiseGateControl,
                parameters: NoiseGateParameters = .default) {
        self.reader = reader
        reporting = reader as? any AnalysisSessionReporting
        self.control = control
        processor = NoiseGateProcessor(parameters: parameters)
        generation = reporting?.analysisSessionGeneration ?? 0
    }

    /// Forwarded; 0 when the wrapped reader reports none.
    public var analysisSessionGeneration: UInt64 { reporting?.analysisSessionGeneration ?? 0 }

    public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let frames = reader.read(into: dst, maxFrames: maxFrames)
        guard frames > 0 else { return frames }
        guard control.isActive else {
            wasActive = false
            return frames
        }
        let current = analysisSessionGeneration
        if !wasActive || current != generation {
            wasActive = true
            generation = current
            processor.reset()
        }
        processor.setOpenThreshold(decibels: control.openDecibels)
        processor.process(dst, frames: frames, channels: NormalizedPCMRing.channelCount)
        return frames
    }
}
