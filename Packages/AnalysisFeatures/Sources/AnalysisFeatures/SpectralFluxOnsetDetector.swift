// SpectralFluxOnsetDetector.swift — positive changes in spectral energy as discrete onset events
// (ANL-004-R1 to R6, R9 to R12, R14, R15; research ANL-004-D1, D2, D5, D6; contracts/onset-detector.md).
//
// Per frame: ANL-002 bands of the ANL-001 magnitudes → each band mapped to 0…1 by ANL-002's decibel
// normalization with the silence floor (at or below the floor reads exactly 0) → detection value =
// mean over bands of max(0, c_b(t) − c_b(t−1)) → threshold = δ + κ · mean of the preceding window's
// detection values → an event on the first frame above the threshold while armed, at least the
// minimum interval after the previous event. Any frame above its threshold disarms; a frame at or
// below re-arms. The event's sample index is the first sample of the frame's newest hop
// (`index + size − hop`); with the stream's `.silence` lead-in that is within one hop of the onset.
//
// The first frame after creation or `reset()` is compared with silence. A frame that does not follow
// its predecessor (index ≠ previous index + previous hop) or changes the FFT size only re-establishes
// the reference; frames at another sample rate or with a wrong magnitude count are ignored and
// counted, and the next accepted frame re-establishes the reference.
//
// Real-time safety (Constitution VII): the band reducer and every buffer are created in `init`;
// `process` only reads and writes preallocated memory and returns an optional value. Not Sendable:
// confined to the worker that owns it (ANL-001-R14). Normalization uses scalar `log10f` on both paths
// so they can differ only by summation order (research ANL-004-D6).
//
// Boundary (Constitution VIII, ADR-0008 decision 5): nothing computed here is passed to projectM.
#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
import Accelerate
#endif

public final class SpectralFluxOnsetDetector {
    public let configuration: OnsetDetectorConfiguration
    public let resolvedBackend: SpectrumBackend

    /// This frame's detection value (0…1); 0 for baseline frames and after `reset()`.
    public private(set) var lastFlux: Float = 0
    /// This frame's threshold; 0 for baseline frames and after `reset()`.
    public private(set) var lastThreshold: Float = 0
    /// Frames accepted (including baseline frames).
    public private(set) var processedFrames = 0
    /// Frames ignored for a sample-rate, magnitude-count or hop mismatch.
    public private(set) var ignoredFrames = 0
    /// The last sequence number issued (0 before the first event).
    public private(set) var eventCount: UInt64 = 0

    private let reducer: BandReducer
    private let bandCount: Int
    private let bands: UnsafeMutablePointer<Float>
    private var previous: UnsafeMutablePointer<Float>
    private var current: UnsafeMutablePointer<Float>
    private let difference: UnsafeMutablePointer<Float>
    private let history: UnsafeMutablePointer<Float>
    private let historyCapacity = OnsetDetectorConfiguration.maximumHistoryFrames
    private var historyCount = 0
    private var historyNext = 0
    private var hasPrevious = false
    private var previousIndex: Int64 = 0
    private var previousHop = 0
    private var previousSize = FFTSize.n512
    private var needsBaseline = false
    private var armed = true
    private var hasEvent = false
    private var lastEventSample: Int64 = 0
    private let minimumInterOnsetSamples: Int64

    /// The stream lead-in this detector's timing rule assumes (ANL-004-R7).
    public static func recommendedLeadIn() -> SpectrumLeadIn { .silence }

    public init(configuration: OnsetDetectorConfiguration = .standard, backend: SpectrumBackend = .automatic) {
        self.configuration = configuration
        resolvedBackend = backend != .portable && SpectrumBackend.isAcceleratedAvailable ? .accelerated : .portable
        do {
            reducer = try BandReducer(sampleRate: configuration.sampleRate, backend: resolvedBackend)
        } catch {
            // The configuration enforces BandLayout's minimum rate, so this cannot happen.
            preconditionFailure("band tables for \(configuration.sampleRate) Hz: \(error)")
        }
        bandCount = configuration.bandCount.rawValue
        minimumInterOnsetSamples = configuration.minimumInterOnsetSamples
        let largest = BandCount.b128.rawValue
        bands = .allocate(capacity: largest)
        bands.initialize(repeating: 0, count: largest)
        previous = .allocate(capacity: largest)
        previous.initialize(repeating: 0, count: largest)
        current = .allocate(capacity: largest)
        current.initialize(repeating: 0, count: largest)
        difference = .allocate(capacity: largest)
        difference.initialize(repeating: 0, count: largest)
        history = .allocate(capacity: historyCapacity)
        history.initialize(repeating: 0, count: historyCapacity)
    }

    deinit {
        let largest = BandCount.b128.rawValue
        bands.deinitialize(count: largest); bands.deallocate()
        previous.deinitialize(count: largest); previous.deallocate()
        current.deinitialize(count: largest); current.deallocate()
        difference.deinitialize(count: largest); difference.deallocate()
        history.deinitialize(count: historyCapacity); history.deallocate()
    }

    /// Restores the initial state (reference = silence, empty history, armed, no previous event);
    /// keeps the sequence counter and the frame counters (ANL-004-R11).
    public func reset() {
        previous.update(repeating: 0, count: bandCount)
        historyCount = 0
        historyNext = 0
        hasPrevious = false
        needsBaseline = false
        armed = true
        hasEvent = false
        lastFlux = 0
        lastThreshold = 0
    }

    /// Processes one spectrum frame (ANL-001 linear magnitudes, `size.binCount` values) and returns
    /// the onset it starts, if any. Allocation-, lock-, log- and I/O-free.
    public func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> OnsetEvent? {
        let size = frame.size
        guard frame.sampleRate == configuration.sampleRate, magnitudes.count == size.binCount,
              frame.hop >= 1, frame.hop <= size.rawValue, let base = magnitudes.baseAddress else {
            ignoredFrames += 1
            needsBaseline = true
            return nil
        }
        processedFrames += 1

        reducer.reduce(magnitudes: base, size: size, bandCount: configuration.bandCount, into: bands)
        let floor = configuration.floorDecibels
        for b in 0..<bandCount { current[b] = BandMath.normalizedDecibels(bands[b], floorDecibels: floor) }

        let contiguous = !hasPrevious || (frame.index == previousIndex &+ Int64(previousHop) && size == previousSize)
        hasPrevious = true
        previousIndex = frame.index
        previousHop = frame.hop
        previousSize = size
        if needsBaseline || !contiguous {
            needsBaseline = false
            swap(&previous, &current)
            lastFlux = 0
            lastThreshold = 0
            return nil
        }

        let flux = rectifiedMeanIncrease()
        swap(&previous, &current)

        // Threshold from the preceding window (oldest to newest, the same order on both paths).
        let window = min(configuration.historyFrames(hop: frame.hop), historyCount)
        var sum: Float = 0
        var slot = (historyNext - window + historyCapacity) % historyCapacity
        for _ in 0..<window {
            sum += history[slot]
            slot = slot + 1 == historyCapacity ? 0 : slot + 1
        }
        let mean = window > 0 ? sum / Float(window) : 0
        let threshold = configuration.thresholdOffset + configuration.thresholdMultiplier * mean
        history[historyNext] = flux
        historyNext = historyNext + 1 == historyCapacity ? 0 : historyNext + 1
        historyCount = min(historyCount + 1, historyCapacity)
        lastFlux = flux
        lastThreshold = threshold

        guard flux > threshold else {
            armed = true
            return nil
        }
        let wasArmed = armed
        armed = false
        let sample = frame.index + Int64(size.rawValue - frame.hop)
        guard wasArmed, !hasEvent || sample - lastEventSample >= minimumInterOnsetSamples else { return nil }
        hasEvent = true
        lastEventSample = sample
        eventCount += 1
        return OnsetEvent(sequence: eventCount, sampleIndex: sample, frameIndex: frame.index, strength: flux,
                          threshold: threshold, sampleRate: configuration.sampleRate,
                          timestampNanoseconds: frame.timestampNanoseconds)
    }

    /// Convenience over an array (no allocation: it borrows the array's storage).
    public func process(_ frame: SpectrumFrame, magnitudes: [Float]) -> OnsetEvent? {
        magnitudes.withUnsafeBufferPointer { process(frame, magnitudes: $0) }
    }

    /// mean over bands of max(0, current − previous), finite and clamped to 0…1.
    private func rectifiedMeanIncrease() -> Float {
        let n = bandCount
        var sum: Float = 0
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        if resolvedBackend == .accelerated {
            var zero: Float = 0
            vDSP_vsub(previous, 1, current, 1, difference, 1, vDSP_Length(n))      // current − previous
            vDSP_vthres(difference, 1, &zero, difference, 1, vDSP_Length(n))      // negatives → 0
            vDSP_sve(difference, 1, &sum, vDSP_Length(n))
        } else {
            for b in 0..<n { let d = current[b] - previous[b]; if d > 0 { sum += d } }
        }
        #else
        for b in 0..<n { let d = current[b] - previous[b]; if d > 0 { sum += d } }
        #endif
        let flux = sum / Float(n)
        guard flux.isFinite, flux > 0 else { return 0 }
        return min(flux, 1)
    }
}
