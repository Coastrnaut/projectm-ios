// ReferenceToneCatalog.swift — the versioned catalog of reference-tone fixtures and the analysis
// values each one is expected to produce (AUD-016-R9 to R11, R22, R23;
// specs/011-aud-016-reference-tone-suite/contracts/fixture-catalog.md).
//
// The catalog is the shared input of the analysis rows (ANL-001 FFT, ANL-002 bands, ANL-004 onsets,
// ANL-005 beat tracking, ANL-016 events, QA-001 fixtures). Its expected values are computed from
// the parameters alone, never by analysing samples; the tests check them against independent
// reference computations. The golden hashes of the samples are in the AudioCore test target.
//
// Versioning: a fixture's ID always names the same samples. Changing any sample of any fixture
// raises `version` and replaces its golden hashes; new fixtures may be added in a new version.

/// One named reference tone: a signal, a loop length and the layouts it is published in.
public struct ReferenceToneFixture: Sendable, Hashable, Identifiable {
    /// Stable identifier, for example `sine-1k`.
    public let id: String
    /// Display name. Every name begins with "Test" (AUD-016-R16).
    public let name: String
    /// One line for the Test Signals list.
    public let summary: String
    public let signal: ToneSignal
    /// Length of one loop. The loop repeats without a gap.
    public let loopSeconds: Int
    /// Channel counts with golden hashes.
    public let layouts: [Int]

    public init(id: String, name: String, summary: String, signal: ToneSignal, loopSeconds: Int = 10, layouts: [Int] = [1, 2]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.signal = signal
        self.loopSeconds = loopSeconds
        self.layouts = layouts
    }

    public func loopFrames(sampleRate: Int) -> Int { loopSeconds * sampleRate }

    public func generator(sampleRate: Int, channels: Int) throws(ToneError) -> ToneGenerator {
        try ToneGenerator(signal: signal, format: ToneFormat(sampleRate: sampleRate, channels: channels))
    }

    /// One loop, interleaved, from frame 0 (the golden hashes' input).
    public func loop(sampleRate: Int, channels: Int) throws(ToneError) -> [Float] {
        try generator(sampleRate: sampleRate, channels: channels).interleaved(frames: loopFrames(sampleRate: sampleRate))
    }

    // MARK: Expected values (AUD-016-R11)

    /// The distinct sine frequencies, left channel first; empty for other signals.
    public var sineFrequencies: [Double] {
        guard case .sine(let tone) = signal else { return [] }
        var frequencies: [Double] = []
        for frequency in [tone.left, tone.right].compactMap({ $0 }) where !frequencies.contains(frequency) {
            frequencies.append(frequency)
        }
        return frequencies
    }

    /// The tempo of a pulse train; nil for other signals.
    public var beatsPerMinute: Double? {
        guard case .pulses(let pulses) = signal else { return nil }
        return pulses.beatsPerMinute
    }

    /// Frames between onsets, not rounded: 60·R/BPM.
    public func framesPerBeat(sampleRate: Int) -> Double? {
        beatsPerMinute.map { 60 * Double(sampleRate) / $0 }
    }

    /// The frames at which pulses start within one loop (empty for other signals).
    public func onsetFrames(sampleRate: Int) -> [Int64] {
        guard let framesPerBeat = framesPerBeat(sampleRate: sampleRate) else { return [] }
        let loop = Int64(loopFrames(sampleRate: sampleRate))
        var frames: [Int64] = []
        var beat = 0.0
        while true {
            let frame = ToneGenerator.onset(beat, framesPerBeat)
            guard frame < loop else { break }
            frames.append(frame)
            beat += 1
        }
        return frames
    }

    /// The sample value of each onset in `onsetFrames` (amplitude × accent).
    public func onsetLevels(sampleRate: Int) -> [Double] {
        guard case .pulses(let pulses) = signal else { return [] }
        return onsetFrames(sampleRate: sampleRate).indices.map { pulses.amplitude * pulses.accents[$0 % pulses.accents.count] }
    }

    /// The frequency at `seconds` within a loop: a sweep's instantaneous frequency, a sine's left
    /// (or only) frequency; nil for pulses and silence.
    public func instantaneousFrequency(atSeconds seconds: Double) -> Double? {
        switch signal {
        case .sine(let tone):
            return tone.left ?? tone.right
        case .sweep(let sweep):
            let t = seconds.truncatingRemainder(dividingBy: sweep.seconds) / sweep.seconds
            switch sweep.curve {
            case .linear: return sweep.start + (sweep.end - sweep.start) * t
            case .logarithmic: return sweep.start * ToneMath.exp(t * ToneMath.log(sweep.end / sweep.start))
            }
        case .pulses, .silence:
            return nil
        }
    }
}

public enum ReferenceToneCatalog {
    /// Raised whenever any fixture's samples change.
    public static let version = 1
    /// The sample rates with golden hashes.
    public static let variantRates = [44_100, 48_000]
    /// The FFT sizes the expected bins are documented for.
    public static let fftSizes = [512, 1_024, 2_048, 4_096, 8_192]
    /// The times (in a loop) at which sweep frequencies are documented.
    public static let sweepCheckSeconds: [Double] = [0, 1.25, 2.5, 5, 7.5]
    /// What In-App Playback plays a fixture in (AUD-016-R23).
    public static let playbackFormat = ToneFormat.canonical

    private static let level = 0.25            // −12.04 dBFS
    private static let pulseLevel = 0.5        // −6.02 dBFS, the catalog's maximum
    private static let pulseWidth = 0.002

    /// Version 1, in display order.
    public static let fixtures: [ReferenceToneFixture] = [
        ReferenceToneFixture(id: "sine-1k", name: "Test tone 1 kHz", summary: "Steady 1 kHz sine on both channels.",
                             signal: .sine(SineTone(frequency: 1_000, amplitude: level))),
        ReferenceToneFixture(id: "sine-100", name: "Test tone 100 Hz", summary: "Steady low 100 Hz sine on both channels.",
                             signal: .sine(SineTone(frequency: 100, amplitude: level))),
        ReferenceToneFixture(id: "sine-1500", name: "Test tone 1.5 kHz", summary: "Steady 1.5 kHz sine, centered on an FFT bin at 48 kHz.",
                             signal: .sine(SineTone(frequency: 1_500, amplitude: level))),
        ReferenceToneFixture(id: "sine-split", name: "Test tone L 1 kHz, R 440 Hz", summary: "1 kHz on the left channel, 440 Hz on the right.",
                             signal: .sine(SineTone(left: 1_000, right: 440, amplitude: level)), layouts: [2]),
        ReferenceToneFixture(id: "sweep-log", name: "Test sweep 20 Hz–20 kHz, logarithmic",
                             summary: "Rises from 20 Hz to 20 kHz in 10 seconds, the same number of octaves each second.",
                             signal: .sweep(SweepTone(start: 20, end: 20_000, seconds: 10, amplitude: level, curve: .logarithmic))),
        ReferenceToneFixture(id: "sweep-linear", name: "Test sweep 20 Hz–20 kHz, linear",
                             summary: "Rises from 20 Hz to 20 kHz in 10 seconds, the same number of hertz each second.",
                             signal: .sweep(SweepTone(start: 20, end: 20_000, seconds: 10, amplitude: level, curve: .linear))),
        ReferenceToneFixture(id: "pulse-120", name: "Test pulses 120 BPM", summary: "Short clicks twice a second. Mostly silence, so the status reads “Audio received — silent”.",
                             signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: pulseWidth, amplitude: pulseLevel))),
        ReferenceToneFixture(id: "pulse-120-accent", name: "Test pulses 120 BPM, accented",
                             summary: "Clicks twice a second, every fourth one louder. Mostly silence, so the status reads “Audio received — silent”.",
                             signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: pulseWidth, amplitude: pulseLevel,
                                                        accents: [1, 0.5, 0.5, 0.5]))),
        ReferenceToneFixture(id: "pulse-132", name: "Test pulses 132 BPM", summary: "Clicks at 132 beats per minute. Mostly silence, so the status reads “Audio received — silent”.",
                             signal: .pulses(PulseTrain(beatsPerMinute: 132, widthSeconds: pulseWidth, amplitude: pulseLevel))),
        ReferenceToneFixture(id: "silence", name: "Test silence", summary: "Digital silence: every sample is zero.", signal: .silence),
    ]

    public static func fixture(id: String) -> ReferenceToneFixture? {
        fixtures.first { $0.id == id }
    }

    // MARK: FFT bins of a tone (AUD-016-R11)

    /// f·N/R: where a tone of `frequency` falls between the bins of an N-point FFT.
    public static func exactBin(frequency: Double, fftSize: Int, sampleRate: Int) -> Double {
        frequency * Double(fftSize) / Double(sampleRate)
    }

    /// The bin with the largest Hann-windowed magnitude: the exact bin rounded half up.
    public static func nearestBin(frequency: Double, fftSize: Int, sampleRate: Int) -> Int {
        Int((exactBin(frequency: frequency, fftSize: fftSize, sampleRate: sampleRate) + 0.5).rounded(.down))
    }

    /// True when the tone lies exactly on a bin (no leakage between bins with a periodic window).
    public static func isBinCentered(frequency: Double, fftSize: Int, sampleRate: Int) -> Bool {
        let bin = exactBin(frequency: frequency, fftSize: fftSize, sampleRate: sampleRate)
        return bin == bin.rounded(.down)
    }
}
