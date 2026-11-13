// ToneSignal.swift — the parameters of a reference tone and their bounds (AUD-016-R1, R4 to R7;
// specs/011-aud-016-reference-tone-suite/data-model.md). Values only; ToneGenerator validates them
// against a format and produces the samples.

/// Why a tone cannot be generated. Each case names the parameter and carries the rejected value.
public enum ToneError: Error, Sendable, Equatable {
    /// Sample rate outside 8,000…192,000 Hz.
    case sampleRate(Int)
    /// Channel count other than 1 or 2.
    case channelCount(Int)
    /// A frequency below 1 Hz, at or above half the sample rate, or not finite.
    case frequency(Double)
    /// An amplitude outside 0…1 or not finite.
    case amplitude(Double)
    /// A sweep length outside 0.01…600 s.
    case duration(Double)
    /// A tempo outside 1…600 BPM.
    case tempo(Double)
    /// A pulse shorter than one frame or not shorter than the shortest beat.
    case pulseWidth(Double)
    /// An accent pattern that is empty, longer than 32, or has a factor outside 0…1.
    case accents
    /// A mono format needs the same frequency (or silence) on both channels of a sine.
    case monoNeedsEqualChannels
    /// A sine with no frequency on either channel.
    case noFrequency
}

/// Sample rate and channel count of generated audio.
public struct ToneFormat: Sendable, Hashable {
    public static let sampleRates: ClosedRange<Int> = 8_000...192_000

    public let sampleRate: Int
    public let channels: Int

    public init(sampleRate: Int, channels: Int) throws(ToneError) {
        guard ToneFormat.sampleRates.contains(sampleRate) else { throw .sampleRate(sampleRate) }
        guard channels == 1 || channels == 2 else { throw .channelCount(channels) }
        self.sampleRate = sampleRate
        self.channels = channels
    }

    private init(validSampleRate: Int, channels: Int) {
        sampleRate = validSampleRate
        self.channels = channels
    }

    /// 48 kHz stereo: the format In-App Playback plays test signals in (AUD-016-R23).
    public static let canonical = ToneFormat(validSampleRate: 48_000, channels: 2)
}

/// A steady sine on one or both channels. A nil frequency is a silent channel.
public struct SineTone: Sendable, Hashable {
    public let left: Double?
    public let right: Double?
    public let amplitude: Double

    public init(left: Double?, right: Double?, amplitude: Double) {
        self.left = left
        self.right = right
        self.amplitude = amplitude
    }

    /// The same frequency on both channels.
    public init(frequency: Double, amplitude: Double) {
        self.init(left: frequency, right: frequency, amplitude: amplitude)
    }
}

/// A sweep from `start` to `end` over `seconds`, then again from `start`. Phase is continuous within
/// a sweep and 0 at its start.
public struct SweepTone: Sendable, Hashable {
    public enum Curve: String, Sendable, Hashable {
        /// Frequency rises by the same factor per second: f(t) = start · (end/start)^(t/seconds).
        case logarithmic
        /// Frequency rises by the same amount per second: f(t) = start + (end − start) · t/seconds.
        case linear
    }

    public let start: Double
    public let end: Double
    public let seconds: Double
    public let amplitude: Double
    public let curve: Curve

    public init(start: Double, end: Double, seconds: Double, amplitude: Double, curve: Curve) {
        self.start = start
        self.end = end
        self.seconds = seconds
        self.amplitude = amplitude
        self.curve = curve
    }

    public static let secondsRange: ClosedRange<Double> = 0.01...600
}

/// Rectangular pulses at a tempo. Onset k starts at the frame nearest to k · 60 / BPM seconds and
/// lasts `widthSeconds` (rounded to whole frames); its level is `amplitude × accents[k mod count]`.
public struct PulseTrain: Sendable, Hashable {
    public let beatsPerMinute: Double
    public let widthSeconds: Double
    public let amplitude: Double
    public let accents: [Double]

    public init(beatsPerMinute: Double, widthSeconds: Double, amplitude: Double, accents: [Double] = [1]) {
        self.beatsPerMinute = beatsPerMinute
        self.widthSeconds = widthSeconds
        self.amplitude = amplitude
        self.accents = accents
    }

    public static let tempoRange: ClosedRange<Double> = 1...600
    public static let maximumAccents = 32
}

/// What a reference tone plays.
public enum ToneSignal: Sendable, Hashable {
    case sine(SineTone)
    case sweep(SweepTone)
    case pulses(PulseTrain)
    /// Digital silence: every sample +0.0.
    case silence
}
