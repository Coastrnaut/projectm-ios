// BandTransientDetector.swift — transient events in one frequency band, independent of overall
// level (ANL-007-R1 to R8, R13, R14; research ANL-007-D1 to D5; contracts/transient-detector.md C2).
//
// Per frame: the band's power P = Σ w_k·m_k² / 1.5 over ANL-001 linear magnitudes, with ANL-002's
// fractional bin weights for [lower, upper) and the periodic Hann window's ENBW (1.5 bins), so a
// full-scale sine in band reads 0 dB → level L = 10·log10 P clamped at the floor → detection value
// D = L − the highest level of the preceding frames spanning one FFT window (size / hop) → threshold
// = max(minimum rise, median + k·MAD of the preceding window of D values) → an event on the first
// frame above the threshold while armed, with L above the floor, the band holding at least the
// dominance share of the frame's power increase over that reference frame (so a loud transient
// elsewhere, whose leakage raises the band a little and the total a lot, never fires, while a kick
// under a loud sustained layer does), and at least the refractory period after the previous event. Any frame above its threshold disarms; a frame at or below re-arms. The envelope decays by
// exp(−hop/(τ·rate)) per frame and is set to 1 by an event.
//
// Confidence (ANL-008-R6, research ANL-008-D2), computed only on event frames: margin =
// clamp((D − threshold) / confidenceMargin, 0, 1); breadth = clamp(flatness / 0.5, 0, 1), where the
// flatness is the geometric over the arithmetic mean of the band's bin powers (noise-like attacks
// ≈ 1, a tone ≈ 0); confidence = √(margin · (1 − w + w · breadth)) with the configuration's breadth
// weight w (0 for the kick, so its confidence is the margin alone). It never changes which frames
// fire. The mid transient (ANL-008) is not a snare classifier and the high transient (ANL-009) is
// not a hi-hat classifier: nothing here names an instrument.
//
// Event-rate cap (ANL-009-R4, research ANL-009-D2): with `maximumEventsPerSecond` N > 0, a frame
// that passes every other test fires only if fewer than N events lie in the preceding 1 s
// (sample − rate, sample]; otherwise it is counted in `rateLimitedEvents` and treated like a
// refractory frame (disarmed, no event, no envelope). So no 1 s span ever holds more than N events,
// however dense the input. The event times live in a preallocated ring of N slots.
//
// Decibel differences do not change with gain, so the same material at another level (above the
// floor) gives the same events. The event's sample index is the first sample of the frame's newest
// hop (`index + size − hop`); with the stream's `.silence` lead-in that is within one hop of the hit.
//
// The first frame after creation or `reset()` is compared with silence (the history holds one floor
// level). A frame after an ignored frame, after a gap (index ≠ previous index + previous hop) or at
// another FFT size only restarts the level history with its own level (no event).
//
// Real-time safety (Constitution VII): every table and window is created in `init`; `process` only
// reads and writes preallocated memory, takes no lock, logs nothing, reads no clock. Not Sendable:
// confined to the worker that owns it. Boundary (Constitution VIII, ADR-0008 decision 5): nothing
// computed here is passed to projectM.
#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
import Accelerate
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public final class BandTransientDetector {
    public let configuration: TransientDetectorConfiguration
    public let resolvedBackend: SpectrumBackend

    /// 0…1: 1 on an event, decaying exponentially; 0 after `reset()`.
    public private(set) var envelope: Float = 0
    /// This frame's band level (dB, clamped at the floor); the floor after `reset()`.
    public private(set) var lastLevel: Float
    /// This frame's detection value (dB); 0 for baseline frames and after `reset()`.
    public private(set) var lastRise: Float = 0
    /// This frame's threshold (dB); 0 for baseline frames and after `reset()`.
    public private(set) var lastThreshold: Float = 0
    /// This frame's band share of the power increase over the reference frame (dB; 0 when the total
    /// rose less than the band; −200 when the band or the total did not rise).
    public private(set) var lastShare: Float = BandTransientDetector.silentShare
    /// Frames accepted (including baseline frames).
    public private(set) var processedFrames = 0
    /// Frames ignored for a sample-rate, magnitude-count or hop mismatch.
    public private(set) var ignoredFrames = 0
    /// The last sequence number issued (0 before the first event).
    public private(set) var eventCount: UInt64 = 0
    /// The last event's confidence (0…1), held until the next event; 0 after `reset()`.
    public private(set) var lastConfidence: Float = 0
    /// Frames that would have fired but were suppressed by the event-rate cap (ANL-009-R4).
    public private(set) var rateLimitedEvents = 0

    static let silentShare: Float = -200
    /// Power below this reads as silence (−120 dB).
    static let minimumPower: Float = 1e-12
    /// Bin powers are floored here inside the flatness's logarithm.
    static let minimumBinPower: Float = 1e-20
    /// The flatness that reads as fully broadband (a Hann-windowed white-noise frame: ≈ 0.5–0.6).
    static let broadbandFlatness: Float = 0.5
    /// The periodic Hann window's equivalent noise bandwidth, in bins.
    static let equivalentNoiseBandwidth: Float = 1.5

    // Weight tables, one per FFT size (index = FFTSize.allCases position), built in init.
    private let firstBins: [Int]
    private let binCounts: [Int]
    private let offsets: [Int]
    private let weights: UnsafeMutablePointer<Float>
    private let weightCount: Int
    private let squares: UnsafeMutablePointer<Float>

    // Level history (the flux reference), a ring of the last levels with their band and total powers.
    private let levelCapacity = TransientDetectorConfiguration.maximumReferenceFrames
    private let levelHistory: UnsafeMutablePointer<Float>
    private let bandPowerHistory: UnsafeMutablePointer<Float>
    private let totalPowerHistory: UnsafeMutablePointer<Float>
    private var bandPower: Float = 0
    private var totalPower: Float = 0
    private var levelCount = 1
    private var levelNext = 1

    // Detection-value window: a ring in arrival order plus the same values sorted.
    private let windowCapacity = TransientDetectorConfiguration.maximumBaselineFrames
    private let ring: UnsafeMutablePointer<Float>
    private let sorted: UnsafeMutablePointer<Float>
    private let deviations: UnsafeMutablePointer<Float>
    private var windowCount = 0
    private var ringNext = 0

    private var hasPrevious = false
    private var previousIndex: Int64 = 0
    private var previousHop = 0
    private var previousSize = FFTSize.n512
    private var needsBaseline = false
    private var armed = true
    private var hasEvent = false
    private var lastEventSample: Int64 = 0
    private var decayHop = 0
    private var decay: Float = 1

    // Event-rate cap: the sample indices of the last `maximumEventsPerSecond` events (oldest at `rateNext`).
    private let rateTimes: UnsafeMutablePointer<Int64>
    private let rateCapacity: Int
    private var rateCount = 0
    private var rateNext = 0

    /// The stream lead-in this detector's timing rule assumes (ANL-004-R7).
    public static func recommendedLeadIn() -> SpectrumLeadIn { .silence }

    public init(configuration: TransientDetectorConfiguration = .kick, backend: SpectrumBackend = .automatic) {
        self.configuration = configuration
        resolvedBackend = backend != .portable && SpectrumBackend.isAcceleratedAvailable ? .accelerated : .portable
        lastLevel = configuration.floorDecibels

        // ANL-002's rule: bin k ≥ 1 covers one bin width centred on k·R/N (bin 1 from 0 Hz, the
        // Nyquist bin up to R/2); its weight is the fraction of that interval inside [lower, upper).
        var firstBins: [Int] = [], binCounts: [Int] = [], offsets: [Int] = [], table: [Float] = []
        for size in FFTSize.allCases {
            let n = size.rawValue
            let m = n / 2
            let delta: Double = configuration.sampleRate / Double(n)
            var first = 0
            var bandWeights: [Float] = []
            for k in 1...m {
                let lo: Double = k == 1 ? 0 : (Double(k) - 0.5) * delta
                let hi: Double = k == m ? Double(k) * delta : (Double(k) + 0.5) * delta
                let overlap: Double = min(configuration.upperFrequency, hi) - max(configuration.lowerFrequency, lo)
                let weight: Double = overlap > 0 ? min(overlap / (hi - lo), 1) : 0
                if weight > BandLayout.weightEpsilon {
                    if bandWeights.isEmpty { first = k }
                    bandWeights.append(Float(weight))
                } else if !bandWeights.isEmpty {
                    break
                }
            }
            // A valid range (20 Hz ≤ lower < upper ≤ R/2) always overlaps some bin: intervals tile 0…R/2.
            precondition(!bandWeights.isEmpty, "empty band \(configuration.lowerFrequency)…\(configuration.upperFrequency) Hz at N=\(n)")
            firstBins.append(first)
            binCounts.append(bandWeights.count)
            offsets.append(table.count)
            table.append(contentsOf: bandWeights)
        }
        self.firstBins = firstBins
        self.binCounts = binCounts
        self.offsets = offsets
        weightCount = table.count
        weights = .allocate(capacity: table.count)
        weights.initialize(from: table, count: table.count)
        squares = .allocate(capacity: FFTSize.maximum.binCount)
        squares.initialize(repeating: 0, count: FFTSize.maximum.binCount)
        levelHistory = .allocate(capacity: TransientDetectorConfiguration.maximumReferenceFrames)
        levelHistory.initialize(repeating: 0, count: TransientDetectorConfiguration.maximumReferenceFrames)
        bandPowerHistory = .allocate(capacity: TransientDetectorConfiguration.maximumReferenceFrames)
        bandPowerHistory.initialize(repeating: 0, count: TransientDetectorConfiguration.maximumReferenceFrames)
        totalPowerHistory = .allocate(capacity: TransientDetectorConfiguration.maximumReferenceFrames)
        totalPowerHistory.initialize(repeating: 0, count: TransientDetectorConfiguration.maximumReferenceFrames)
        let capacity = TransientDetectorConfiguration.maximumBaselineFrames
        ring = .allocate(capacity: capacity)
        ring.initialize(repeating: 0, count: capacity)
        sorted = .allocate(capacity: capacity)
        sorted.initialize(repeating: 0, count: capacity)
        deviations = .allocate(capacity: capacity)
        deviations.initialize(repeating: 0, count: capacity)
        rateCapacity = max(configuration.maximumEventsPerSecond, 1)
        rateTimes = .allocate(capacity: rateCapacity)
        rateTimes.initialize(repeating: 0, count: rateCapacity)
        seedSilence()
    }

    deinit {
        weights.deinitialize(count: weightCount); weights.deallocate()
        squares.deinitialize(count: FFTSize.maximum.binCount); squares.deallocate()
        levelHistory.deinitialize(count: levelCapacity); levelHistory.deallocate()
        bandPowerHistory.deinitialize(count: levelCapacity); bandPowerHistory.deallocate()
        totalPowerHistory.deinitialize(count: levelCapacity); totalPowerHistory.deallocate()
        ring.deinitialize(count: windowCapacity); ring.deallocate()
        sorted.deinitialize(count: windowCapacity); sorted.deallocate()
        deviations.deinitialize(count: windowCapacity); deviations.deallocate()
        rateTimes.deinitialize(count: rateCapacity); rateTimes.deallocate()
    }

    /// Restores the initial state (empty histories, armed, no previous event, envelope 0); keeps the
    /// sequence counter and the frame counters.
    public func reset() {
        seedSilence()
        windowCount = 0
        ringNext = 0
        hasPrevious = false
        needsBaseline = false
        armed = true
        hasEvent = false
        envelope = 0
        lastConfidence = 0
        lastLevel = configuration.floorDecibels
        lastRise = 0
        lastThreshold = 0
        lastShare = BandTransientDetector.silentShare
        rateCount = 0
        rateNext = 0
    }

    /// Processes one spectrum frame (ANL-001 linear magnitudes, `size.binCount` values) and returns
    /// the transient it starts, if any. Allocation-, lock-, log-, clock- and I/O-free.
    public func process(_ frame: SpectrumFrame, magnitudes: UnsafeBufferPointer<Float>) -> TransientEvent? {
        let size = frame.size
        guard frame.sampleRate == configuration.sampleRate, magnitudes.count == size.binCount,
              frame.hop >= 1, frame.hop <= size.rawValue, let base = magnitudes.baseAddress else {
            ignoredFrames += 1
            needsBaseline = true
            return nil
        }
        processedFrames += 1

        let level = measure(base, size: size)
        lastLevel = level
        if frame.hop != decayHop {
            decayHop = frame.hop
            decay = configuration.envelopeDecay(hop: frame.hop)
        }
        envelope *= decay

        let contiguous = !hasPrevious || (frame.index == previousIndex &+ Int64(previousHop) && size == previousSize)
        hasPrevious = true
        previousIndex = frame.index
        previousHop = frame.hop
        previousSize = size
        if needsBaseline || !contiguous {
            needsBaseline = false
            levelCount = 0
            levelNext = 0
            pushLevel(level)
            lastRise = 0
            lastThreshold = 0
            lastShare = BandTransientDetector.silentShare
            return nil
        }

        // D = L − the highest of the preceding frames spanning one window (fewer after a restart).
        let span: Int = min(max(size.rawValue / frame.hop, 1), levelCapacity)
        let referenceSlot = peakLevelSlot(span: span)
        let reference: Float = levelHistory[referenceSlot]
        let rise: Float = level - reference
        lastShare = increaseShare(since: referenceSlot)

        // Threshold from the preceding window of D values.
        let target = configuration.baselineFrames(hop: frame.hop)
        let center = median(sorted, count: windowCount)
        let spread = medianAbsoluteDeviation(center: center)
        let adaptive: Float = center + configuration.deviationMultiplier * spread
        let threshold: Float = max(configuration.minimumRiseDecibels, adaptive)
        pushRise(rise, target: target)
        pushLevel(level)
        lastRise = rise
        lastThreshold = threshold

        guard rise > threshold else {
            armed = true
            return nil
        }
        let wasArmed = armed
        armed = false
        let sample: Int64 = frame.index + Int64(size.rawValue - frame.hop)
        let audible = level > configuration.floorDecibels && lastShare >= configuration.dominanceDecibels
        let rested = !hasEvent || sample - lastEventSample >= configuration.refractorySamples
        guard wasArmed, audible, rested else { return nil }
        guard withinRate(sample) else {
            rateLimitedEvents += 1
            return nil
        }
        hasEvent = true
        lastEventSample = sample
        eventCount += 1
        envelope = 1
        let confidence = confidence(rise: rise, threshold: threshold, magnitudes: base, size: size)
        lastConfidence = confidence
        return TransientEvent(band: configuration.band, sequence: eventCount, sampleIndex: sample, frameIndex: frame.index,
                              strength: rise, threshold: threshold, level: level, sampleRate: configuration.sampleRate,
                              timestampNanoseconds: frame.timestampNanoseconds, confidence: confidence)
    }

    /// The event-rate cap (ANL-009-R4): true when `sample` may fire, recording it; false when the
    /// last N events all lie within the preceding 1 s.
    private func withinRate(_ sample: Int64) -> Bool {
        let limit = configuration.maximumEventsPerSecond
        guard limit > 0 else { return true }
        if rateCount == limit {
            // rateNext is the oldest of the last N events.
            guard sample - rateTimes[rateNext] >= configuration.rateWindowSamples else { return false }
        } else {
            rateCount += 1
        }
        rateTimes[rateNext] = sample
        rateNext = rateNext + 1 == limit ? 0 : rateNext + 1
        return true
    }

    /// Convenience over an array (no allocation: it borrows the array's storage).
    public func process(_ frame: SpectrumFrame, magnitudes: [Float]) -> TransientEvent? {
        magnitudes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> TransientEvent? in
            process(frame, magnitudes: buffer)
        }
    }

    // MARK: Confidence

    /// √(margin · breadth′), finite, 0…1 (ANL-008-R6).
    private func confidence(rise: Float, threshold: Float, magnitudes: UnsafePointer<Float>, size: FFTSize) -> Float {
        let excess: Float = rise - threshold
        let rawMargin: Float = excess / configuration.confidenceMarginDecibels
        let margin: Float = rawMargin.isFinite ? min(max(rawMargin, 0), 1) : 0
        let weight: Float = configuration.breadthWeight
        var breadthTerm: Float = 1
        if weight > 0 {
            let breadth: Float = bandBreadth(magnitudes, size: size)
            breadthTerm = 1 - weight + weight * breadth
        }
        let product: Float = margin * breadthTerm
        let value: Float = product > 0 ? product.squareRoot() : 0
        return value.isFinite ? min(max(value, 0), 1) : 0
    }

    /// clamp(flatness / 0.5, 0, 1) over the band's bins (geometric over arithmetic mean of m²).
    private func bandBreadth(_ magnitudes: UnsafePointer<Float>, size: FFTSize) -> Float {
        let slot = size.log2 - FFTSize.n512.log2
        let first = firstBins[slot]
        let count = binCounts[slot]
        guard count > 1 else { return 0 }
        var logSum: Float = 0
        var sum: Float = 0
        for k in first..<(first + count) {
            let m: Float = magnitudes[k]
            let raw: Float = m * m
            let power: Float = raw.isFinite ? max(raw, BandTransientDetector.minimumBinPower) : BandTransientDetector.minimumBinPower
            logSum += logf(power)
            sum += power
        }
        let n = Float(count)
        let arithmetic: Float = sum / n
        guard arithmetic > BandTransientDetector.minimumBinPower, arithmetic.isFinite else { return 0 }
        let geometric: Float = expf(logSum / n)
        let flatness: Float = geometric / arithmetic
        let breadth: Float = flatness / BandTransientDetector.broadbandFlatness
        return breadth.isFinite ? min(max(breadth, 0), 1) : 0
    }

    // MARK: Measurement

    /// The band level in dB (clamped at the floor); sets `bandPower` and `totalPower`.
    private func measure(_ magnitudes: UnsafePointer<Float>, size: FFTSize) -> Float {
        let slot = size.log2 - FFTSize.n512.log2
        let first = firstBins[slot]
        let count = binCounts[slot]
        let offset = offsets[slot]
        let bins = size.binCount
        var band: Float = 0
        var total: Float = 0
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        if resolvedBackend == .accelerated {
            vDSP_vsq(magnitudes, 1, squares, 1, vDSP_Length(bins))
            vDSP_dotpr(squares + first, 1, weights + offset, 1, &band, vDSP_Length(count))
            vDSP_sve(squares + 1, 1, &total, vDSP_Length(bins - 1))
        } else {
            portableSums(magnitudes, bins: bins, first: first, count: count, offset: offset, band: &band, total: &total)
        }
        #else
        portableSums(magnitudes, bins: bins, first: first, count: count, offset: offset, band: &band, total: &total)
        #endif
        let scale: Float = 1 / BandTransientDetector.equivalentNoiseBandwidth
        bandPower = band.isFinite && band > 0 ? band * scale : 0
        totalPower = total.isFinite && total > 0 ? total * scale : 0
        let power: Float = max(bandPower, BandTransientDetector.minimumPower)
        let decibels: Float = 10 * log10f(power)
        return max(decibels, configuration.floorDecibels)
    }

    private func portableSums(_ magnitudes: UnsafePointer<Float>, bins: Int, first: Int, count: Int, offset: Int,
                              band: inout Float, total: inout Float) {
        for k in 0..<count {
            let m: Float = magnitudes[first + k]
            band += weights[offset + k] * (m * m)
        }
        for k in 1..<bins {
            let m: Float = magnitudes[k]
            total += m * m
        }
    }

    // MARK: Histories

    /// The level history holds one silent frame (the floor, zero power).
    private func seedSilence() {
        levelHistory[0] = configuration.floorDecibels
        bandPowerHistory[0] = 0
        totalPowerHistory[0] = 0
        levelCount = 1
        levelNext = 1
    }

    private func pushLevel(_ level: Float) {
        levelHistory[levelNext] = level
        bandPowerHistory[levelNext] = bandPower
        totalPowerHistory[levelNext] = totalPower
        levelNext = levelNext + 1 == levelCapacity ? 0 : levelNext + 1
        levelCount = min(levelCount + 1, levelCapacity)
    }

    /// The slot of the highest of the newest `span` levels (the oldest on a tie). The history is
    /// never empty: `reset()` seeds it with the floor and a baseline frame pushes its own level.
    private func peakLevelSlot(span: Int) -> Int {
        let n = max(min(span, levelCount), 1)
        var slot = (levelNext - n + levelCapacity) % levelCapacity
        var best = slot
        for _ in 0..<n {
            if levelHistory[slot] > levelHistory[best] { best = slot }
            slot = slot + 1 == levelCapacity ? 0 : slot + 1
        }
        return best
    }

    /// 10·log10(Δband / Δtotal) for this frame against the reference slot: 0 dB when the total rose
    /// less than the band, the silent share when the band or the total did not rise.
    private func increaseShare(since slot: Int) -> Float {
        let bandIncrease: Float = bandPower - bandPowerHistory[slot]
        let totalIncrease: Float = totalPower - totalPowerHistory[slot]
        guard bandIncrease > 0, bandIncrease.isFinite else { return BandTransientDetector.silentShare }
        // A falling total means the rest of the spectrum moved more than the band: not concentrated.
        guard totalIncrease > 0, totalIncrease.isFinite else { return BandTransientDetector.silentShare }
        guard totalIncrease > bandIncrease else { return 0 }
        let ratio: Float = bandIncrease / totalIncrease
        return 10 * log10f(ratio)
    }

    /// Adds `rise` to the window, dropping the oldest values beyond `target`.
    private func pushRise(_ rise: Float, target: Int) {
        while windowCount >= target, windowCount > 0 {
            let oldestSlot = (ringNext - windowCount + windowCapacity) % windowCapacity
            removeSorted(ring[oldestSlot])
            windowCount -= 1
        }
        ring[ringNext] = rise
        ringNext = ringNext + 1 == windowCapacity ? 0 : ringNext + 1
        insertSorted(rise)
        windowCount += 1
    }

    /// Inserts into `sorted[0..<windowCount]` (the count is incremented by the caller).
    private func insertSorted(_ value: Float) {
        var i = windowCount
        while i > 0, sorted[i - 1] > value {
            sorted[i] = sorted[i - 1]
            i -= 1
        }
        sorted[i] = value
    }

    /// Removes one copy of `value` from `sorted[0..<windowCount]` (the caller decrements the count).
    private func removeSorted(_ value: Float) {
        var i = 0
        while i < windowCount, sorted[i] != value { i += 1 }
        guard i < windowCount else { return }
        while i + 1 < windowCount {
            sorted[i] = sorted[i + 1]
            i += 1
        }
    }

    /// Median of ascending `values[0..<count]`; 0 when empty.
    private func median(_ values: UnsafeMutablePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        let middle = count / 2
        if count % 2 == 1 { return values[middle] }
        let sum: Float = values[middle - 1] + values[middle]
        return sum / 2
    }

    /// Median of |x − center| over the window (insertion sort into the scratch); 0 when empty.
    private func medianAbsoluteDeviation(center: Float) -> Float {
        let n = windowCount
        guard n > 0 else { return 0 }
        for i in 0..<n {
            let value: Float = abs(sorted[i] - center)
            var j = i
            while j > 0, deviations[j - 1] > value {
                deviations[j] = deviations[j - 1]
                j -= 1
            }
            deviations[j] = value
        }
        return median(deviations, count: n)
    }
}
