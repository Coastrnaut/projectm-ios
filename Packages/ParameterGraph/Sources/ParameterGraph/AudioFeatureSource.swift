// AudioFeatureSource.swift — which normalized audio feature drives a binding, and one frame of
// features (MOD-002-R1, R6; research MOD-002-D2, D3; contract C1).
//
// The frame borrows the caller's band buffer for one `advance` call, so nothing is copied or
// allocated and this module stays independent of the analysis types (Constitution VI): the native
// spectra pass their band scratch; a consumer of the analysis event bus (ANL-016) passes its copied
// bands plus `AnalysisFrame.onsetFlux`, `beatConfidence`, `kickEnvelope` (ANL-007-R11) and the
// normalized `centroid` (ANL-010-R8), the `loudness` envelope (ANL-014-R8), the mid transient
// value `AnalysisFrame.midTransient` (ANL-008-R8), the high transient value
// `AnalysisFrame.highTransient` (ANL-009-R8), the normalized `rolloff` (ANL-011-R8) and the
// `flatness` (ANL-012-R7) and the stereo `correlation` mapped to 0…1 (ANL-013-R6).

/// A normalized (0…1) audio feature a binding can follow.
public enum AudioFeatureSource: Sendable, Hashable, CustomStringConvertible {
    /// One band's level (ANL-002), by 0-based index.
    case band(Int)
    /// The mean level of all bands in the frame.
    case bandMean
    /// The onset detection value (ANL-004).
    case onset
    /// The beat tracker's confidence (ANL-005).
    case beatConfidence
    /// The kick envelope (ANL-007): 1 on a kick, decaying to 0.
    case kick
    /// The spectral centroid (ANL-010), normalized 0…1 on a log-frequency scale (50 Hz → 0,
    /// 10 kHz → 1): the sound's brightness.
    case centroid
    /// The loudness envelope (ANL-014): K-weighted level normalized −60…0 dB, smoothed (attack
    /// 100 ms, release 400 ms); 0 at silence.
    case loudness
    /// "Mid transient" (ANL-008): a mid-band (1–4 kHz) percussive transient's envelope × its
    /// confidence, 0…1. Not a snare detector: it never implies which instrument played.
    case midTransient
    /// "High transient" (ANL-009): a high-band (6–16 kHz) percussive transient's envelope × its
    /// confidence, 0…1, at most 12 events per second. Not a hi-hat detector: it never implies
    /// which instrument played.
    case highTransient
    /// "Rolloff" (ANL-011): the frequency below which 85 % of the power lies, normalized 0…1 on a
    /// log-frequency scale (50 Hz → 0, 20 kHz → 1); 0 at silence.
    case rolloff
    /// "Flatness" (ANL-012): spectral flatness (Wiener entropy), 0 tonal … 1 flat; white noise reads
    /// ≈ 0.56; 0 at silence.
    case flatness
    /// "Correlation" (ANL-013): stereo correlation r (−1 inverted … 1 identical) mapped to (r + 1)/2:
    /// identical channels (and mono) read 1, unrelated or silent 0.5, inverted 0.
    case correlation
    /// MOD-007: the scene's oscillator at this 0-based position (0…7), read from `AudioFeatureFrame.lfos`.
    /// Its ID keeps the `audio.` binding-source prefix so every stored-binding path (MOD-013 restore,
    /// migrations) reads it, and an older version orphans it instead of dropping it (research MOD-007-D4).
    case lfo(Int)

    /// The highest band index (the largest band count is 128).
    public static let maximumBandIndex = 127

    /// The stable identifier (MOD-013 stores it): `audio.band.<index>`, `audio.bandMean`,
    /// `audio.onset`, `audio.beatConfidence`, `audio.kick`, `audio.centroid`, `audio.loudness`,
    /// `audio.midTransient`, `audio.highTransient`, `audio.rolloff`, `audio.flatness`, `audio.correlation`, `audio.lfo.<index>` (MOD-007).
    public var id: String {
        switch self {
        case let .band(index): "audio.band.\(index)"
        case .bandMean: "audio.bandMean"
        case .onset: "audio.onset"
        case .beatConfidence: "audio.beatConfidence"
        case .kick: "audio.kick"
        case .centroid: "audio.centroid"
        case .loudness: "audio.loudness"
        case .midTransient: "audio.midTransient"
        case .highTransient: "audio.highTransient"
        case .rolloff: "audio.rolloff"
        case .flatness: "audio.flatness"
        case .correlation: "audio.correlation"
        case let .lfo(index): "audio.lfo.\(index)"
        }
    }

    public var description: String { id }

    /// Parses exactly the identifiers `id` produces (decimal band index 0…127, no sign, no
    /// leading zeros); anything else is nil.
    public init?(id: String) {
        switch id {
        case "audio.bandMean": self = .bandMean
        case "audio.onset": self = .onset
        case "audio.beatConfidence": self = .beatConfidence
        case "audio.kick": self = .kick
        case "audio.centroid": self = .centroid
        case "audio.loudness": self = .loudness
        case "audio.midTransient": self = .midTransient
        case "audio.highTransient": self = .highTransient
        case "audio.rolloff": self = .rolloff
        case "audio.flatness": self = .flatness
        case "audio.correlation": self = .correlation
        default:
            if let index = Self.index(in: id, prefix: "audio.band.", maximum: Self.maximumBandIndex) {
                self = .band(index)
            } else if let index = Self.index(in: id, prefix: "audio.lfo.", maximum: Self.maximumLFOIndex) {
                self = .lfo(index)
            } else {
                return nil
            }
        }
    }

    /// MOD-007: the highest oscillator index (`LFOBank.maximumOscillators` − 1).
    public static let maximumLFOIndex = LFOBank.maximumOscillators - 1

    /// The decimal index after `prefix` (no sign, no leading zeros, at most `maximum`), or nil.
    private static func index(in id: String, prefix: String, maximum: Int) -> Int? {
        guard id.hasPrefix(prefix) else { return nil }
        let digits = id.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
              digits.count == 1 || digits.first != "0",
              let index = Int(digits), index <= maximum else { return nil }
        return index
    }

    /// The feature's value in `frame`; a missing or non-finite reading is 0 (MOD-002-R6).
    public func value(in frame: AudioFeatureFrame) -> Double {
        switch self {
        case let .band(index):
            guard index >= 0, index < frame.bands.count else { return 0 }
            return Self.finite(Double(frame.bands[index]))
        case .bandMean:
            guard !frame.bands.isEmpty else { return 0 }
            var sum = 0.0
            for level in frame.bands { sum += Self.finite(Double(level)) }
            return sum / Double(frame.bands.count)
        case .onset:
            return frame.onset.map { Self.finite(Double($0)) } ?? 0
        case .beatConfidence:
            return frame.beatConfidence.map(Self.finite) ?? 0
        case .kick:
            return frame.kick.map { (value: Float) -> Double in Self.finite(Double(value)) } ?? 0
        case .centroid:
            return frame.centroid.map { (value: Float) -> Double in Self.finite(Double(value)) } ?? 0
        case .loudness:
            return frame.loudness.map { (value: Float) -> Double in Self.finite(Double(value)) } ?? 0
        case .midTransient:
            return frame.midTransient.map { (value: Float) -> Double in Self.finite(Double(value)) } ?? 0
        case .highTransient:
            return frame.highTransient.map { (value: Float) -> Double in Self.finite(Double(value)) } ?? 0
        case .rolloff:
            return frame.rolloff.map { (value: Float) -> Double in Self.finite(Double(value)) } ?? 0
        case .flatness:
            return frame.flatness.map { (value: Float) -> Double in Self.finite(Double(value)) } ?? 0
        case .correlation:
            guard let r = frame.correlation, r.isFinite else { return 0 }
            let mapped: Double = (Double(r) + 1) / 2
            return min(max(mapped, 0), 1)
        case let .lfo(index):
            guard index >= 0, index < frame.lfos.count else { return 0 }
            return min(max(Self.finite(frame.lfos[index]), 0), 1)
        }
    }

    private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
}

/// One frame of normalized audio features. `bands` is borrowed: valid only during the call it is
/// passed to.
public struct AudioFeatureFrame {
    public var bands: UnsafeBufferPointer<Float>
    public var onset: Float?
    public var beatConfidence: Double?
    /// ANL-007's kick envelope (0…1); nil when the producer does not feed it.
    public var kick: Float?
    /// ANL-010's normalized spectral centroid (0…1); nil when the producer does not feed it.
    public var centroid: Float?
    /// ANL-014's loudness envelope (0…1); nil when the producer does not feed it.
    public var loudness: Float?
    /// ANL-008's mid transient value (envelope × confidence, 0…1); nil when the producer does not feed it.
    public var midTransient: Float?
    /// ANL-009's high transient value (envelope × confidence, 0…1); nil when the producer does not feed it.
    public var highTransient: Float?
    /// ANL-011's normalized spectral rolloff (0…1); nil when the producer does not feed it.
    public var rolloff: Float?
    /// ANL-012's spectral flatness (0…1); nil when the producer does not feed it.
    public var flatness: Float?
    /// ANL-013's raw stereo correlation (−1…1); the source maps it to 0…1. nil when not fed.
    public var correlation: Float?
    /// MOD-007: the scene's oscillator values (0…1) by position, borrowed like `bands`; empty when the producer
    /// has no oscillators (every `.lfo` source then reads 0).
    public var lfos: UnsafeBufferPointer<Double>

    public init(bands: UnsafeBufferPointer<Float>, onset: Float? = nil, beatConfidence: Double? = nil, kick: Float? = nil,
                centroid: Float? = nil, loudness: Float? = nil, midTransient: Float? = nil,
                highTransient: Float? = nil, rolloff: Float? = nil, flatness: Float? = nil, correlation: Float? = nil,
                lfos: UnsafeBufferPointer<Double> = UnsafeBufferPointer(start: nil, count: 0)) {
        self.bands = bands
        self.onset = onset
        self.beatConfidence = beatConfidence
        self.kick = kick
        self.centroid = centroid
        self.loudness = loudness
        self.midTransient = midTransient
        self.highTransient = highTransient
        self.rolloff = rolloff
        self.flatness = flatness
        self.correlation = correlation
        self.lfos = lfos
    }

    /// No audio: every feature reads 0.
    public static var silent: AudioFeatureFrame { AudioFeatureFrame(bands: UnsafeBufferPointer(start: nil, count: 0)) }
}
