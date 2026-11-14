// AnalysisBusTypes.swift — the items of the analysis event bus (ANL-016-R2 to R5; data-model.md;
// contracts/analysis-event-bus.md).
//
// Every type here is a value type with no references, so the worker copies items into preallocated
// subscriber storage without ARC traffic or allocation (Constitution VII). Nothing here is passed to
// projectM (Constitution VIII, ADR-0008 decision 5).

/// When an item became known, on the pipeline's one clock (ANL-016-R5, R6; research ANL-016-D2).
public struct AnalysisTimestamp: Sendable, Hashable {
    /// 1, 2, 3… per pipeline; never reused.
    public let session: UInt64
    /// Input samples consumed in the session up to the end of the window that produced the item
    /// (markers: 0 at a session start, the samples consumed at its end).
    public let sessionSample: Int64
    /// Session base + `sessionSample`; never decreases in ID order, across sessions too.
    public let timelineSample: Int64
    /// Monotonic nanoseconds: the session's anchor + `sessionSample` at the sample rate.
    public let hostNanoseconds: UInt64

    public init(session: UInt64, sessionSample: Int64, timelineSample: Int64, hostNanoseconds: UInt64) {
        self.session = session
        self.sessionSample = sessionSample
        self.timelineSample = timelineSample
        self.hostNanoseconds = hostNanoseconds
    }
}

/// Why a session started or ended (ANL-016-R8).
public enum AnalysisSessionChange: Sendable, Hashable {
    /// A reader was attached (or replaced by another attach).
    case attached
    /// The reader was detached (or the pipeline stopped).
    case detached
    /// The analysis tap reported a new capture session (the normalized ring was reset).
    case sourceRestarted
    /// The owner asked for a restart.
    case restarted
}

/// A discrete event's payload (ANL-016-R3).
public enum AnalysisEventKind: Sendable, Hashable {
    /// ANL-004 onset: detection value and the threshold it crossed.
    case onset(strength: Float, threshold: Float)
    /// ANL-005 beat: tempo, period in samples and the estimate's confidence.
    case beat(bpm: Double, periodSamples: Double, confidence: Double)
    /// ANL-007 band transient (`.kick`, ANL-008's `.midTransient` or ANL-009's `.highTransient`): the rise over the band's
    /// recent peak and the threshold it crossed (dB), the band level (dB re a full-scale sine in
    /// band) and the event's confidence 0…1 (ANL-008-R6; never an instrument identity).
    case transient(band: TransientBand, strength: Float, threshold: Float, level: Float, confidence: Float)
    /// ANL-015 section change: a sustained level change (`.rising` quiet → loud, `.falling` loud →
    /// quiet) confirmed after the dwell; the slow level and the reference it left (dB, LKFS-like). The
    /// event's `eventSample` is where the change was first seen; its `time` is the confirming frame.
    case sectionChange(direction: SectionChangeDirection, levelDecibels: Float, referenceDecibels: Float)
    case sessionStarted(AnalysisSessionChange)
    case sessionEnded(AnalysisSessionChange)
}

/// A discrete event (ANL-016-R3, R4, R7).
public struct AnalysisEvent: Sendable, Hashable {
    /// Unique and strictly increasing per pipeline (shared with frames).
    public let id: UInt64
    /// When the event became known (the end of the window that produced it).
    public let time: AnalysisTimestamp
    /// The event's own position on the session's sample clock: the onset's or transient's sample
    /// index, the beat's predicted sample, or `time.sessionSample` for markers. At most `time.sessionSample`.
    public let eventSample: Int64
    public let kind: AnalysisEventKind

    public init(id: UInt64, time: AnalysisTimestamp, eventSample: Int64, kind: AnalysisEventKind) {
        self.id = id
        self.time = time
        self.eventSample = eventSample
        self.kind = kind
    }
}

/// A feature frame's metadata (ANL-016-R2); its bands are copied separately.
public struct AnalysisFrame: Sendable, Hashable {
    public let id: UInt64
    public let time: AnalysisTimestamp
    /// Bands in this frame (16, 32, 64 or 128), each normalized 0…1 (ANL-002 decibel scale).
    public let bandCount: Int
    /// ANL-004's detection value for this frame, 0…1.
    public let onsetFlux: Float
    /// ANL-005's tempo; nil without an estimate.
    public let bpm: Double?
    /// ANL-005's confidence, 0…1 (0 without an estimate).
    public let beatConfidence: Double
    /// ANL-007's kick envelope, 0…1: 1 on the frame of a kick, decaying with a 100 ms time constant.
    public let kickEnvelope: Float
    /// ANL-010's spectral centroid in Hz (held at silence; 0 before any signal in the session).
    public let centroidHz: Float
    /// ANL-010's centroid normalized 0…1 (log frequency, 50 Hz → 0, 10 kHz → 1; held / 0 likewise).
    public let centroid: Float
    /// ANL-014's loudness envelope, 0…1: K-weighted level normalized −60…0 dB, attack 100 ms,
    /// release 400 ms (0 at silence and before any signal in the session).
    public let loudness: Float
    /// ANL-014's unsmoothed K-weighted level of the frame, LKFS-like dB (−120 at silence).
    public let loudnessDecibels: Float
    /// ANL-008's mid transient envelope, 0…1: 1 on the frame of a mid-band (1–4 kHz) transient,
    /// decaying with an 80 ms time constant. Not a snare detector: no instrument is implied.
    public let midTransientEnvelope: Float
    /// ANL-008: the last mid transient's confidence, 0…1, held until the next one (0 at a session start).
    public let midTransientConfidence: Float

    /// ANL-008: envelope × confidence, 0…1, what MOD-002's "Mid transient" source reads.
    public var midTransient: Float { midTransientEnvelope * midTransientConfidence }
    /// ANL-009's high transient envelope, 0…1: 1 on the frame of a high-band (6–16 kHz) transient,
    /// decaying with a 50 ms time constant. Not a hi-hat detector: no instrument is implied.
    public let highTransientEnvelope: Float
    /// ANL-009: the last high transient's confidence, 0…1, held until the next one (0 at a session start).
    public let highTransientConfidence: Float

    /// ANL-009: envelope × confidence, 0…1, what MOD-002's "High transient" source reads.
    public var highTransient: Float { highTransientEnvelope * highTransientConfidence }
    /// ANL-011's spectral rolloff in Hz: the frequency below which 85 % (the configured fraction) of
    /// the power lies, interpolated within the bin (0 at silence and before any signal in the session).
    public let rolloffHz: Float
    /// ANL-011's rolloff normalized 0…1 (log frequency, 50 Hz → 0, 20 kHz → 1; 0 at silence).
    public let rolloff: Float
    /// ANL-012's spectral flatness (Wiener entropy of the bin power), 0 tonal … 1 flat; ≈ 0.56 for
    /// white noise; 0 at silence and before any signal in the session.
    public let flatness: Float
    /// ANL-013's stereo correlation of the analysis tap, −1 (inverted) … 1 (identical); 0 at silence,
    /// with one silent channel and before any signal in the session; 1 for mono and AUD-009's non-Mix modes.
    public let correlation: Float
    /// ANL-013's phase-inversion warning (r < −0.5 for 1 s raises it, r > −0.3 for 1 s clears it).
    public let phaseInverted: Bool
    /// ANL-015's section-change envelope, 0…1: 1 on the frame that confirmed a section change,
    /// decaying with a 1 s time constant (0 at a session start).
    public let sectionChangeEnvelope: Float
    /// ANL-015's slow level: the K-weighted mean power of the last 35 frames (≈ 0.41 s), dB, at least
    /// the detector's −70 dB floor.
    public let sectionLevelDecibels: Float

    public init(id: UInt64, time: AnalysisTimestamp, bandCount: Int, onsetFlux: Float, bpm: Double?, beatConfidence: Double,
                kickEnvelope: Float = 0, centroidHz: Float = 0, centroid: Float = 0,
                loudness: Float = 0, loudnessDecibels: Float = LoudnessReading.silent.decibels,
                midTransientEnvelope: Float = 0, midTransientConfidence: Float = 0,
                highTransientEnvelope: Float = 0, highTransientConfidence: Float = 0,
                rolloffHz: Float = 0, rolloff: Float = 0, flatness: Float = 0,
                correlation: Float = 0, phaseInverted: Bool = false,
                sectionChangeEnvelope: Float = 0, sectionLevelDecibels: Float = SectionChangeConfiguration.standard.floorDecibels) {
        self.id = id
        self.time = time
        self.bandCount = bandCount
        self.onsetFlux = onsetFlux
        self.bpm = bpm
        self.beatConfidence = beatConfidence
        self.kickEnvelope = kickEnvelope
        self.centroidHz = centroidHz
        self.centroid = centroid
        self.loudness = loudness
        self.loudnessDecibels = loudnessDecibels
        self.midTransientEnvelope = midTransientEnvelope
        self.midTransientConfidence = midTransientConfidence
        self.highTransientEnvelope = highTransientEnvelope
        self.highTransientConfidence = highTransientConfidence
        self.rolloffHz = rolloffHz
        self.rolloff = rolloff
        self.flatness = flatness
        self.correlation = correlation
        self.phaseInverted = phaseInverted
        self.sectionChangeEnvelope = sectionChangeEnvelope
        self.sectionLevelDecibels = sectionLevelDecibels
    }
}

public enum AnalysisBusError: Error, Equatable, Sendable {
    /// Event queue capacity outside 1…1,024.
    case invalidEventCapacity(Int)
    /// Already `AnalysisPipeline.maximumSubscribers` subscribers.
    case tooManySubscribers
    /// The spectrum, onset, beat, kick, mid and high transient, centroid, rolloff, flatness, loudness, correlation and section-change configurations disagree on the sample rate (or the section-change hop differs from the spectrum's).
    case sampleRateMismatch
    /// The band floor must be finite and below 0 dB.
    case invalidBandFloor(Float)
}
