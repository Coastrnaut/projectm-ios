// AdaptiveBeatTracker.swift — tempo, beat grid and confidence from onset intervals (ANL-005-R1 to R13,
// R15, R16; research ANL-005-D1 to D6; contracts/beat-tracker.md).
//
// On every accepted onset (ANL-004 events, or any sample index on the same clock):
//   1. History: the onsets of the last `windowSeconds` behind the newest one, at most 64.
//   2. Coarse tempo: every pair at most 4 s apart votes, for n = 1…4, for the tempi whose period is
//      within the timing tolerance τ of interval / n: triangular weight × 1/n × recency 2^(−age/2 s)
//      of the older onset, on a 0.25 BPM grid; × the preference exp(−½ log2(BPM / preferred)²); the
//      first maximum wins, unless the tracked tempo still scores ≥ 90 % of it (hysteresis).
//   3. Grid: the anchor is the onset with the largest recency-weighted count of onsets within 2τ of
//      the coarse grid through it (the later one on a tie); three unweighted least-squares fits of
//      time = anchor + k · period over the on-grid onsets (2τ, then τ, τ) give period and phase.
//   4. Estimate (≥ 4 distinct matched beats and a tempo in range, else the previous one stays):
//      confidence = precision × coverage × support × freshness (ANL-005-R7).
// `advance(to:)` moves the stream position: it drops the estimate and history 4 s (the silence
// timeout) after the last matched onset and reports the latest predicted beat it passes
// (previous position − τ ≤ beat < new position), each beat once.
//
// Determinism (ANL-005-R12): all sums are scalar Double loops in a fixed order. vDSP is used only
// for exact element-wise steps (clear, multiply by the preference, first maximum), so the vDSP and
// portable paths are bit-identical.
//
// Real-time safety (Constitution VII): every buffer is allocated in `init`; `add`, `advance` and
// `process` only read and write preallocated memory and return optional values. Not Sendable:
// confined to the worker that owns it (ANL-001-R14).
//
// Boundary (Constitution VIII, ADR-0008 decision 5): nothing computed here is passed to projectM.
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

public final class AdaptiveBeatTracker {
    /// Confidence at or above this means the tempo is supported (ANL-005-R8).
    public static let highConfidence = 0.5

    public let configuration: BeatTrackerConfiguration
    public let resolvedBackend: SpectrumBackend

    public private(set) var acceptedOnsets = 0
    /// Onsets at another sample rate, or not after the previous onset.
    public private(set) var ignoredOnsets = 0
    /// Positions earlier than the previous position.
    public private(set) var ignoredPositions = 0
    /// Predicted beats passed in one advance besides the one reported.
    public private(set) var skippedBeats = 0
    /// Predictions within half a period of the previously reported beat (not reported again).
    public private(set) var suppressedBeats = 0
    /// The last beat sequence number issued (0 before the first beat).
    public private(set) var beatCount: UInt64 = 0

    private let rate: Double
    private let tolerance: Double
    private let windowSamples: Int64
    private let timeoutSamples: Double
    private let maximumLag: Double
    private let halfLife: Double
    private let bins: Int
    private let minimumBPM: Double
    private let maximumBPM: Double
    private let capacity = BeatTrackerConfiguration.maximumOnsets

    private let onsets: UnsafeMutablePointer<Int64>
    private let weights: UnsafeMutablePointer<Double>
    private let histogram: UnsafeMutablePointer<Double>
    private let preference: UnsafeMutablePointer<Double>
    private let scores: UnsafeMutablePointer<Double>
    private var onsetCount = 0
    private var lastAccepted: Int64?

    private var hasFit = false
    private var period = 0.0
    private var anchor = 0.0
    private var lastMatched: Int64 = 0
    private var precision = 0.0
    private var coverage = 0.0
    private var support = 0.0
    private var matchedBeats = 0
    private var onsetsInFit = 0

    private var position: Int64?
    private var lastReported: Double?

    public init(configuration: BeatTrackerConfiguration = .standard, backend: SpectrumBackend = .automatic) {
        self.configuration = configuration
        resolvedBackend = backend != .portable && SpectrumBackend.isAcceleratedAvailable ? .accelerated : .portable
        rate = configuration.sampleRate
        tolerance = configuration.timingToleranceSeconds * rate
        windowSamples = Int64((configuration.windowSeconds * rate).rounded())
        timeoutSamples = configuration.silenceTimeoutSeconds * rate
        maximumLag = BeatTrackerConfiguration.maximumLagSeconds * rate
        halfLife = BeatTrackerConfiguration.recencyHalfLifeSeconds * rate
        bins = configuration.gridBins
        minimumBPM = configuration.minimumBPM
        maximumBPM = configuration.maximumBPM
        onsets = .allocate(capacity: capacity)
        onsets.initialize(repeating: 0, count: capacity)
        weights = .allocate(capacity: capacity)
        weights.initialize(repeating: 0, count: capacity)
        histogram = .allocate(capacity: bins)
        histogram.initialize(repeating: 0, count: bins)
        scores = .allocate(capacity: bins)
        scores.initialize(repeating: 0, count: bins)
        preference = .allocate(capacity: bins)
        for k in 0..<bins {
            let octaves = log2((minimumBPM + Double(k) * BeatTrackerConfiguration.gridStepBPM) / configuration.preferredBPM)
            (preference + k).initialize(to: exp(-0.5 * octaves * octaves))
        }
    }

    deinit {
        onsets.deinitialize(count: capacity); onsets.deallocate()
        weights.deinitialize(count: capacity); weights.deallocate()
        histogram.deinitialize(count: bins); histogram.deallocate()
        scores.deinitialize(count: bins); scores.deallocate()
        preference.deinitialize(count: bins); preference.deallocate()
    }

    // MARK: Input

    /// Adds an ANL-004 onset; ignored and counted at another sample rate or when not after the
    /// previous onset.
    public func add(_ onset: OnsetEvent) {
        guard onset.sampleRate == rate else { ignoredOnsets += 1; return }
        add(onsetAt: onset.sampleIndex)
    }

    /// Adds an onset at `sampleIndex` on the stream's clock (taps, tests).
    public func add(onsetAt sampleIndex: Int64) {
        if let lastAccepted, sampleIndex <= lastAccepted { ignoredOnsets += 1; return }
        lastAccepted = sampleIndex
        acceptedOnsets += 1
        if onsetCount == capacity { dropOldest(1) }
        onsets[onsetCount] = sampleIndex
        onsetCount += 1
        var stale = 0
        while stale < onsetCount - 1, sampleIndex - onsets[stale] > windowSamples { stale += 1 }
        if stale > 0 { dropOldest(stale) }
        refit()
    }

    /// Moves the stream position to `newPosition` and returns the latest predicted beat it passed
    /// (previous position − τ ≤ beat < new position) that was not reported yet, if any. Earlier positions are ignored and counted.
    public func advance(to newPosition: Int64) -> BeatEvent? {
        if let position, newPosition < position { ignoredPositions += 1; return nil }
        let previous = position
        position = newPosition
        if hasFit, Double(newPosition - lastMatched) >= timeoutSamples {
            hasFit = false
            onsetCount = 0
            return nil
        }
        if !hasFit, onsetCount > 0, Double(newPosition - onsets[onsetCount - 1]) >= timeoutSamples { onsetCount = 0 }
        guard hasFit, let previous, newPosition > previous else { return nil }
        let p0 = Double(previous), p1 = Double(newPosition)
        let high = ((p1 - anchor) / period).rounded(.up) - 1               // latest grid beat < p1
        // A re-fit on this frame's onset may move a beat that was still ahead of p0 to just before
        // it; beats down to τ before p0 therefore still count (once: see `lastReported`).
        let low = ((p0 - tolerance - anchor) / period).rounded(.up)
        guard high >= low else { return nil }
        skippedBeats += max(0, Int(high - ((p0 - anchor) / period).rounded(.up)))
        let beat = anchor + high * period
        if let lastReported, beat - lastReported < 0.5 * period { suppressedBeats += 1; return nil }
        lastReported = beat
        beatCount += 1
        return BeatEvent(sequence: beatCount, sampleIndex: Int64(beat.rounded()), bpm: 60 * rate / period,
                         periodSamples: period, confidence: precision * coverage * support * freshness(at: newPosition),
                         sampleRate: rate)
    }

    /// One spectrum frame: adds its onset (if any), then advances to the frame's end (index + size).
    public func process(_ frame: SpectrumFrame, onset: OnsetEvent?) -> BeatEvent? {
        if let onset { add(onset) }
        return advance(to: frame.index + Int64(frame.size.rawValue))
    }

    /// Drops the estimate, the history, the position and the last reported beat; keeps the beat
    /// sequence and the counters (ANL-005-R15).
    public func reset() {
        onsetCount = 0
        lastAccepted = nil
        hasFit = false
        position = nil
        lastReported = nil
    }

    // MARK: Output

    /// The current estimate; nil means no tempo.
    public var estimate: BeatEstimate? {
        guard hasFit else { return nil }
        let at = position ?? lastMatched
        let fresh = freshness(at: at)
        let next = anchor + ((Double(at) - anchor) / period).rounded(.up) * period
        return BeatEstimate(bpm: 60 * rate / period, periodSamples: period, anchorSample: anchor,
                            nextBeatSample: Int64(next.rounded()), confidence: precision * coverage * support * fresh,
                            precision: precision, coverage: coverage, support: support, freshness: fresh,
                            matchedBeats: matchedBeats, onsetsInWindow: onsetsInFit, sampleRate: rate, position: at)
    }

    /// `estimate?.confidence ?? 0`.
    public var confidence: Double { estimate?.confidence ?? 0 }

    // MARK: Internals

    private func dropOldest(_ count: Int) {
        let remaining = onsetCount - count
        for i in 0..<remaining { onsets[i] = onsets[i + count] }
        onsetCount = remaining
    }

    private func freshness(at point: Int64) -> Double {
        let age = Double(point - lastMatched)
        let grace = 1.5 * period
        guard age > grace else { return 1 }
        return max(0, 1 - (age - grace) / (timeoutSamples - grace))
    }

    private func refit() {
        let n = onsetCount
        guard n >= BeatTrackerConfiguration.minimumMatchedBeats else { return }
        let newest = onsets[n - 1]
        for i in 0..<n { weights[i] = exp2(-Double(newest - onsets[i]) / halfLife) }

        // 2. Coarse tempo.
        clearHistogram()
        let step = BeatTrackerConfiguration.gridStepBPM
        let scale = 60 * rate
        for i in 0..<(n - 1) {
            let w = weights[i]
            for j in (i + 1)..<n {
                let d = Double(onsets[j] - onsets[i])
                if d > maximumLag { break }
                if d <= tolerance { continue }
                for h in 1...BeatTrackerConfiguration.harmonics {
                    let multiple = Double(h)
                    let centre = scale * multiple / d
                    let lowBPM = scale * multiple / (d + tolerance)
                    let highBPM = scale * multiple / (d - tolerance)
                    if highBPM < minimumBPM || lowBPM > maximumBPM { continue }
                    let first = max(0, Int(((lowBPM - minimumBPM) / step).rounded(.up)))
                    let last = min(bins - 1, Int(((highBPM - minimumBPM) / step).rounded(.down)))
                    if first > last { continue }
                    let vote = w / multiple
                    for k in first...last {
                        let bpm = minimumBPM + Double(k) * step
                        let half = bpm >= centre ? highBPM - centre : centre - lowBPM
                        let triangle = 1 - abs(bpm - centre) / half
                        if triangle > 0 { histogram[k] += vote * triangle }
                    }
                }
            }
        }
        let (bestBin, bestScore) = weightedMaximum()
        guard bestScore > 0 else { return }
        var coarse = scale / (minimumBPM + Double(bestBin) * step)
        if hasFit {
            let tracked = min(bins - 1, max(0, Int(((scale / period - minimumBPM) / step).rounded())))
            if scores[tracked] >= BeatTrackerConfiguration.hysteresis * bestScore { coarse = period }
        }

        // 3. Anchor: the onset whose coarse grid catches the most recency-weighted onsets.
        var anchorIndex = 0
        var anchorScore = -1.0
        for a in 0..<n {
            var score = 0.0
            for o in 0..<n {
                let x = Double(onsets[o] - onsets[a])
                if abs(x - (x / coarse).rounded() * coarse) <= 2 * tolerance { score += weights[o] }
            }
            if score >= anchorScore { anchorScore = score; anchorIndex = a }
        }

        // Least squares on time (relative to the anchor onset) against beat number.
        let base = onsets[anchorIndex]
        var p = coarse
        var phase = 0.0
        for iteration in 0..<3 {
            let limit = iteration == 0 ? 2 * tolerance : tolerance
            var count = 0.0, sumK = 0.0, sumX = 0.0
            for o in 0..<n {
                let x = Double(onsets[o] - base)
                let k = ((x - phase) / p).rounded()
                if abs(x - phase - k * p) <= limit { count += 1; sumK += k; sumX += x }
            }
            guard count >= 2 else { return }
            let meanK = sumK / count, meanX = sumX / count
            var sxy = 0.0, sxx = 0.0
            for o in 0..<n {
                let x = Double(onsets[o] - base)
                let k = ((x - phase) / p).rounded()
                if abs(x - phase - k * p) <= limit {
                    sxy += (k - meanK) * (x - meanX)
                    sxx += (k - meanK) * (k - meanK)
                }
            }
            guard sxx > 0 else { return }
            let fitted = sxy / sxx
            guard fitted.isFinite, fitted > 0 else { return }
            phase = meanX - meanK * fitted
            p = fitted
        }
        let bpm = scale / p
        guard bpm >= minimumBPM, bpm <= maximumBPM else { return }

        // 4. Matched beats, precision and coverage on the final grid.
        var matched = 0, inliers = 0
        var previousK = -Double.infinity
        var lastMatchedX = 0.0
        for o in 0..<n {
            let x = Double(onsets[o] - base)
            let k = ((x - phase) / p).rounded()
            if abs(x - phase - k * p) <= tolerance {
                inliers += 1
                if k != previousK { matched += 1; previousK = k }
                lastMatchedX = x
            }
        }
        guard matched >= BeatTrackerConfiguration.minimumMatchedBeats else { return }
        let firstK = ((Double(onsets[0] - base) - phase) / p).rounded()
        let lastK = ((Double(newest - base) - phase) / p).rounded()
        hasFit = true
        period = p
        anchor = Double(base) + phase + ((lastMatchedX - phase) / p).rounded() * p
        lastMatched = base + Int64(lastMatchedX)
        matchedBeats = matched
        onsetsInFit = n
        precision = Double(inliers) / Double(n)
        coverage = min(1, Double(matched) / (lastK - firstK + 1))
        support = min(1, max(0, Double(matched - 4) / 4))
    }

    private func clearHistogram() {
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        if resolvedBackend == .accelerated { vDSP_vclrD(histogram, 1, vDSP_Length(bins)); return }
        #endif
        histogram.update(repeating: 0, count: bins)
    }

    /// scores = histogram × preference; returns the first maximum (index, value).
    private func weightedMaximum() -> (Int, Double) {
        #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
        if resolvedBackend == .accelerated {
            vDSP_vmulD(histogram, 1, preference, 1, scores, 1, vDSP_Length(bins))
            var value = 0.0
            var index: vDSP_Length = 0
            vDSP_maxviD(scores, 1, &value, &index, vDSP_Length(bins))
            return (Int(index), value)
        }
        #endif
        var best = 0
        for k in 0..<bins {
            scores[k] = histogram[k] * preference[k]
            if scores[k] > scores[best] { best = k }
        }
        return (best, scores[best])
    }
}
