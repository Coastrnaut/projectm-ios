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

    public init(spectrum: SpectrumConfiguration = AnalysisPipelineConfiguration.defaultSpectrum,
                bandCount: BandCount = .b64,
                bandFloorDecibels: Float = BandMath.defaultFloorDecibels,
                onset: OnsetDetectorConfiguration = .standard,
                beat: BeatTrackerConfiguration = .standard) throws(AnalysisBusError) {
        guard spectrum.sampleRate == onset.sampleRate, spectrum.sampleRate == beat.sampleRate else {
            throw .sampleRateMismatch
        }
        guard bandFloorDecibels.isFinite, bandFloorDecibels < 0 else { throw .invalidBandFloor(bandFloorDecibels) }
        self.spectrum = spectrum
        self.bandCount = bandCount
        self.bandFloorDecibels = bandFloorDecibels
        self.onset = onset
        self.beat = beat
    }
}
