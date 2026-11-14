// AudioClockDriftEstimator.swift — PERF-013 (specs/216-perf-013-audio-render-sync, R3, R4, R6; research PERF-013-D2):
// estimates the drift between the analysis sample clock and the host clock.
//
// * Input: one residual per analysis frame read for the first time, `arrival − busHost` in nanoseconds, at the frame's
//   session sample. ANL-016 maps a sample to host time with one anchor per session at the nominal rate, so a rate
//   difference between the audio clock and the host clock makes the residual grow linearly with audio time.
// * Arrival jitter is one-sided (a frame is never read before it exists), so each 1 s bucket of audio time keeps only
//   its minimum residual. The drift (ppm = ns per s / 1,000) is the least-squares slope through the last 64 bucket
//   minima (a lower convex hull was tried: with ~1 ms of noise on each minimum its two-point edges were noisier).
// * Verdict: at least 10 buckets; detected when |drift| ≥ 50 ppm and ≥ 3 standard errors of the slope (a noise guard:
//   with no drift, short fits reach ±100 ppm); cleared when |drift| < 25 ppm.
// * Steps: a closed bucket more than 10 ms off the previous minimum plus the drift prediction is a latency step (an
//   AUD-013 offset change, a route change), not drift. It starts a new segment: the fit gives every segment its own
//   intercept and one shared slope (pooled within-segment regression), so a step never biases the drift and the
//   history is kept; the verdict and the correction carry on.
// * Pure value: no clock is read here. Storage is allocated once in `init`; observing allocates nothing.
//   Nothing here reaches projectM (Constitution VIII).

/// The estimator's fixed parameters (research PERF-013-D2).
public struct AudioClockDriftConfiguration: Sendable, Equatable {
    /// The bus's nominal rate (ANL-016: the normalized ring's 44.1 kHz).
    public var sampleRate: Double
    public var bucketSeconds: Double
    public var capacity: Int
    public var minimumBuckets: Int
    public var detectPPM: Double
    public var clearPPM: Double
    /// Minimum significance of a detection, in standard errors of the slope.
    public var significance: Double
    public var stepNanoseconds: Double

    public init(sampleRate: Double = 44_100, bucketSeconds: Double = 1, capacity: Int = 64, minimumBuckets: Int = 10,
                detectPPM: Double = 50, clearPPM: Double = 25, significance: Double = 3, stepNanoseconds: Double = 10_000_000) {
        self.sampleRate = sampleRate
        self.bucketSeconds = bucketSeconds
        self.capacity = max(capacity, 3)
        self.minimumBuckets = min(max(minimumBuckets, 3), self.capacity)
        self.detectPPM = detectPPM
        self.clearPPM = clearPPM
        self.significance = significance
        self.stepNanoseconds = stepNanoseconds
    }

    public static let standard = AudioClockDriftConfiguration()
}

/// Drift between the analysis sample clock and the host clock (data model: drift estimate).
public struct AudioClockDriftEstimator: Sendable {
    public let configuration: AudioClockDriftConfiguration

    /// Bucket minima: audio time (s) and residual (ns), a ring of `capacity`.
    private var times: [Double]
    private var residuals: [Double]
    /// Each bucket's segment: a latency step starts a new one (its own intercept, the same slope).
    private var segments: [Int]
    private var segment: Int = 0
    private var head: Int = 0
    private var count: Int = 0
    private var newestTime: Double = 0
    private var newestResidual: Double = 0
    /// The open bucket: its index and minimum so far.
    private var openBucket: Int64?
    private var openTime: Double = 0
    private var openResidual: Double = 0

    /// The latest fitted drift in ppm (held across a step restart); nil before the first fit.
    public private(set) var driftPPM: Double?
    public private(set) var detected: Bool = false
    /// Times the verdict went from not detected to detected.
    public private(set) var detections: Int = 0
    /// Latency steps seen.
    public private(set) var steps: Int = 0

    public init(configuration: AudioClockDriftConfiguration = .standard) {
        self.configuration = configuration
        times = [Double](repeating: 0, count: configuration.capacity)
        residuals = [Double](repeating: 0, count: configuration.capacity)
        segments = [Int](repeating: 0, count: configuration.capacity)
    }

    /// Buckets in the current fit (tests).
    public var bucketCount: Int { count }

    /// Forgets everything (a new analysis session, PERF-013-R7).
    public mutating func reset() {
        head = 0
        count = 0
        openBucket = nil
        driftPPM = nil
        detected = false
    }

    /// One residual (`arrival − busHost`, ns) at `sessionSample`. Returns true when the verdict changed.
    @discardableResult
    public mutating func observe(sessionSample: Int64, residualNanoseconds raw: Double) -> Bool {
        guard raw.isFinite, sessionSample >= 0 else { return false }
        let residual: Double = raw
        let time: Double = Double(sessionSample) / configuration.sampleRate
        let bucket: Int64 = Int64((time / configuration.bucketSeconds).rounded(.down))
        guard let open = openBucket else {
            openBucket = bucket
            openTime = time
            openResidual = residual
            return false
        }
        if bucket == open {
            if residual < openResidual {
                openTime = time
                openResidual = residual
            }
            return false
        }
        guard bucket > open else { return false }   // a sample position going back within a session: ignored
        let changed: Bool = close(time: openTime, residual: openResidual)
        openBucket = bucket
        openTime = time
        openResidual = residual
        return changed
    }

    /// The correction target at `sessionSample` (ns to add to the bus host time): drift × audio time while detected.
    public func targetNanoseconds(atSessionSample sessionSample: Int64) -> Double {
        guard detected, let drift = driftPPM else { return 0 }
        let seconds: Double = Double(max(sessionSample, 0)) / configuration.sampleRate
        return drift * 1_000 * seconds
    }

    // MARK: - Fit

    private mutating func close(time: Double, residual: Double) -> Bool {
        if count > 0 {
            let slope: Double = (driftPPM ?? 0) * 1_000   // ns per s
            let predicted: Double = newestResidual + slope * (time - newestTime)
            if abs(residual - predicted) > configuration.stepNanoseconds {
                steps += 1
                segment += 1   // a new intercept from here on; the slope is shared
            }
        }
        append(time: time, residual: residual)
        guard count >= configuration.minimumBuckets, let fit = fit() else { return false }
        driftPPM = fit.ppm
        return updateVerdict(ppm: fit.ppm, standardError: fit.standardErrorPPM)
    }

    private mutating func append(time: Double, residual: Double) {
        let capacity: Int = configuration.capacity
        let index: Int = (head + count) % capacity
        times[index] = time
        residuals[index] = residual
        segments[index] = segment
        if count < capacity { count += 1 } else { head = (head + 1) % capacity }
        newestTime = time
        newestResidual = residual
    }

    /// Least-squares slope (ppm) shared by every segment, each with its own intercept (pooled within-segment
    /// regression), and the slope's standard error (ppm); nil when the times do not spread.
    private func fit() -> (ppm: Double, standardErrorPPM: Double)? {
        var sxx: Double = 0
        var sxy: Double = 0
        var groups: Int = 0
        var start: Int = 0
        while start < count {
            let end: Int = segmentEnd(from: start)
            let means: (t: Double, r: Double) = segmentMeans(start, end)
            for k in start..<end {
                let i: Int = ringIndex(k)
                let dt: Double = times[i] - means.t
                sxx += dt * dt
                sxy += dt * (residuals[i] - means.r)
            }
            groups += 1
            start = end
        }
        guard sxx > 0 else { return nil }
        let slope: Double = sxy / sxx
        var squares: Double = 0
        start = 0
        while start < count {
            let end: Int = segmentEnd(from: start)
            let means: (t: Double, r: Double) = segmentMeans(start, end)
            for k in start..<end {
                let i: Int = ringIndex(k)
                let error: Double = residuals[i] - (means.r + slope * (times[i] - means.t))
                squares += error * error
            }
            start = end
        }
        let variance: Double = squares / Double(max(count - groups - 1, 1))
        let standardError: Double = (variance / sxx).squareRoot()
        return (slope / 1_000, standardError / 1_000)
    }

    private func ringIndex(_ k: Int) -> Int { (head + k) % configuration.capacity }

    /// The end (exclusive) of the run of buckets in the same segment as bucket `start`.
    private func segmentEnd(from start: Int) -> Int {
        let id: Int = segments[ringIndex(start)]
        var end: Int = start + 1
        while end < count, segments[ringIndex(end)] == id { end += 1 }
        return end
    }

    private func segmentMeans(_ start: Int, _ end: Int) -> (t: Double, r: Double) {
        var sumT: Double = 0
        var sumR: Double = 0
        for k in start..<end {
            let i: Int = ringIndex(k)
            sumT += times[i]
            sumR += residuals[i]
        }
        let n: Double = Double(end - start)
        return (sumT / n, sumR / n)
    }

    private mutating func updateVerdict(ppm: Double, standardError: Double) -> Bool {
        let magnitude: Double = abs(ppm)
        if !detected {
            let significant: Bool = magnitude >= configuration.significance * standardError
            guard magnitude >= configuration.detectPPM, significant else { return false }
            detected = true
            detections += 1
            return true
        }
        guard magnitude < configuration.clearPPM else { return false }
        detected = false
        return true
    }
}
