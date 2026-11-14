// AnalysisPipelineConfiguration.swift — what the analysis event bus computes (ANL-016-R1, R2;
// data-model.md).

public struct AnalysisPipelineConfiguration: Sendable, Hashable {
    /// 2,048-point Hann spectra, hop 512 (11.6 ms), mid channel, 44.1 kHz: VIS-001's analysis.
    public static let defaultSpectrum = try! SpectrumConfiguration(size: .n2048, hop: 512, sampleRate: 44_100, channelMode: .mid)
    public static let standard = try! AnalysisPipelineConfiguration()

    public let spectrum: SpectrumConfiguration
    /// Bands in each feature frame (can be changed later with `AnalysisPipeline.setBandCount`).
    public let bandCount: BandCount
    /// Silence floor of the frames' decibel normalization (ANL-002), dBFS.
    public let bandFloorDecibels: Float
    public let onset: OnsetDetectorConfiguration
    public let beat: BeatTrackerConfiguration
    /// ANL-007's kick detector.
    public let kick: TransientDetectorConfiguration
    /// ANL-008's mid transient detector (1–4 kHz; not a snare classifier).
    public let midTransient: TransientDetectorConfiguration
    /// ANL-009's high transient detector (6–16 kHz, rate-capped; not a hi-hat classifier).
    public let highTransient: TransientDetectorConfiguration
    /// ANL-010's spectral centroid.
    public let centroid: SpectralCentroidConfiguration
    /// ANL-014's loudness envelope (built for the spectrum's FFT size).
    public let loudness: LoudnessConfiguration
    /// ANL-011's spectral rolloff (fraction 0.85 by default).
    public let rolloff: SpectralRolloffConfiguration
    /// ANL-012's spectral flatness (20 Hz to Nyquist, −70 dB floor).
    public let flatness: SpectralFlatnessConfiguration
    /// ANL-013's stereo correlation (1,024-frame blocks, τ 0.1 s, −70 dB floor, warning hysteresis).
    public let correlation: StereoCorrelationConfiguration

    public init(spectrum: SpectrumConfiguration = AnalysisPipelineConfiguration.defaultSpectrum,
                bandCount: BandCount = .b64,
                bandFloorDecibels: Float = BandMath.defaultFloorDecibels,
                onset: OnsetDetectorConfiguration = .standard,
                beat: BeatTrackerConfiguration = .standard,
                kick: TransientDetectorConfiguration = .kick,
                midTransient: TransientDetectorConfiguration = .midTransient,
                highTransient: TransientDetectorConfiguration = .highTransient,
                centroid: SpectralCentroidConfiguration = .standard,
                loudness: LoudnessConfiguration = .standard,
                rolloff: SpectralRolloffConfiguration = .standard,
                flatness: SpectralFlatnessConfiguration = .standard,
                correlation: StereoCorrelationConfiguration = .standard) throws(AnalysisBusError) {
        guard spectrum.sampleRate == onset.sampleRate, spectrum.sampleRate == beat.sampleRate,
              spectrum.sampleRate == kick.sampleRate, spectrum.sampleRate == midTransient.sampleRate,
              spectrum.sampleRate == highTransient.sampleRate,
              spectrum.sampleRate == centroid.sampleRate, spectrum.sampleRate == rolloff.sampleRate,
              spectrum.sampleRate == flatness.sampleRate, spectrum.sampleRate == correlation.sampleRate,
              spectrum.sampleRate == loudness.sampleRate else {
            throw .sampleRateMismatch
        }
        guard bandFloorDecibels.isFinite, bandFloorDecibels < 0 else { throw .invalidBandFloor(bandFloorDecibels) }
        self.spectrum = spectrum
        self.bandCount = bandCount
        self.bandFloorDecibels = bandFloorDecibels
        self.onset = onset
        self.beat = beat
        self.kick = kick
        self.midTransient = midTransient
        self.highTransient = highTransient
        self.centroid = centroid
        self.loudness = loudness
        self.rolloff = rolloff
        self.flatness = flatness
        self.correlation = correlation
    }
}
