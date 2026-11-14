// SpectrumBandFeed.swift — normalized audio → normalized bands for native visuals (VIS-001-R14;
// research VIS-001-D5).
//
// SpectrumStream (ANL-001: 2,048-point Hann spectra, hop 512, mid channel, 44.1 kHz) → BandReducer
// (ANL-002: 16/32/64/128 log-frequency bands) → BandMath decibels (floor −80 dB) → 0…1 per band.
// `pull(from:)` reads every buffered frame of an analysis tap and keeps the newest band vector; no
// smoothing here: ANL-003's `BandSmoother` smooths on the display side (VIS-001-R9, ANL-003-R8).
//
// Real-time safety (Constitution VII): the stream, the reducer's tables and the 128-value band
// scratch are allocated in `init`; `pull`, `setBarCount` and `reset` touch only that memory. Not
// Sendable: confined to the queue that owns it. Since ANL-016 the live circular spectrum takes its
// bands from the analysis event bus (`LiveBandAnalyzer`, same analysis settings); this feed stays as
// the synchronous reference path the VIS-001 band tests check. Nothing computed here reaches
// projectM (Constitution VIII, ADR-0008 decision 5).
import AnalysisFeatures
import AudioCore
import VisualGenerators

public final class SpectrumBandFeed {
    public static let fftSize = FFTSize.n2048
    public static let hop = 512
    public static let floorDecibels = BandMath.defaultFloorDecibels

    private let stream: SpectrumStream
    private let reducer: BandReducer
    private let scratch: UnsafeMutablePointer<Float>
    private var count: BandCount
    private var timestamp: UInt64 = 0

    public init(barCount: SpectrumBarCount) throws {
        let configuration = try SpectrumConfiguration(size: Self.fftSize, hop: Self.hop,
                                                      sampleRate: NormalizedPCMRing.sampleRate, channelMode: .mid)
        stream = SpectrumStream(configuration: configuration)
        reducer = try BandReducer(sampleRate: NormalizedPCMRing.sampleRate)
        scratch = .allocate(capacity: SpectrumBarCount.maximum)
        scratch.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        count = BandCount(rawValue: barCount.rawValue)!
    }

    deinit {
        scratch.deinitialize(count: SpectrumBarCount.maximum)
        scratch.deallocate()
    }

    /// Takes effect at the next spectrum; the current values are cleared.
    public func setBarCount(_ barCount: SpectrumBarCount) {
        guard barCount.rawValue != count.rawValue else { return }
        count = BandCount(rawValue: barCount.rawValue)!
        scratch.update(repeating: 0, count: SpectrumBarCount.maximum)
    }

    /// Forgets buffered audio and the current bands.
    public func reset() {
        stream.reset()
        scratch.update(repeating: 0, count: SpectrumBarCount.maximum)
        timestamp = 0
    }

    /// Reads `reader` until it is empty. True when at least one new spectrum was reduced; `bands`
    /// then holds the newest one.
    @discardableResult
    public func pull(from reader: some NormalizedPCMReader) -> Bool {
        var produced = false
        stream.pull(from: reader) { frame, magnitudes in
            guard let base = magnitudes.baseAddress else { return }
            reducer.reduce(magnitudes: base, size: frame.size, bandCount: count, into: scratch)
            BandMath.normalize(scratch, count: count.rawValue, scale: .decibels(floorDecibels: Self.floorDecibels))
            timestamp = frame.timestampNanoseconds
            produced = true
        }
        return produced
    }

    /// The newest normalized bands (`barCount` values, 0…1).
    public var bands: UnsafeBufferPointer<Float> { UnsafeBufferPointer(start: scratch, count: count.rawValue) }

    /// Monotonic nanoseconds of the newest spectrum.
    public var timestampNanoseconds: UInt64 { timestamp }
}
