// AudioClockDriftEstimator.swift — PERF-013 (specs/216-perf-013-audio-render-sync, R3, R4, R6; research PERF-013-D2):
// estimates the drift between the analysis sample clock and the host clock.
//
// * Input: one residual per analysis frame read for the first time, `arrival − busHost` in nanoseconds, at the frame's
//   session sample. ANL-016 maps a sample to host time with one anchor per session at the nominal rate, so a rate
//   difference between the audio clock and the host clock makes the residual grow linearly with audio time.
// * Arrival jitter is one-sided (a frame is never read before it exists), so each 1 s bucket of audio time keeps only
//   its minimum residual. The drift (ppm = ns per s / 1,000) is the least-squares slope through the last 64 bucket
//   minima (a lower convex hull was tried: with ~1 ms of noise on each minimum its two-point edges were noisier).
// * Verdict: at least 30 buckets (30 s of audio); detected when |drift| ≥ 50 ppm and ≥ 3 standard errors of the slope
//   (a noise guard: with no drift, short fits reach ±100 ppm) and the slope is stable: the older and the newer half of
//   the fit window agree within 3 standard errors of their difference (at least 50 ppm). Cleared when |drift| < 25 ppm
//   or when the halves stop agreeing (4 standard errors): a real clock difference is a constant rate, while a wandering
//   arrival latency (QA-011 D2 microphone, 2026-11-20: fits from −753 to +316 ppm within 2 minutes) bends the floor.
//   A slope beyond `maximumPPM` (300) is never a detection: audio and host crystals differ by tens of ppm, ±100 ppm
//   at worst (QA-011 2026-11-15: 2,000; lowered 2026-11-20). The fit must also be straight: its residual variance at
//   most twice the noise variance from successive bucket differences.
// * The correction target (drift × audio time) never exceeds what the residual floor actually moved since the session
//   start, outside latency steps, plus a 2 ms margin, and never has the opposite sign: the correction cannot make an
//   age larger than the floor's movement justifies (QA-011 D2, 2026-11-20: a −753 ppm "drift" over a floor that had
//   not moved raised ages from 65 ms to 104 ms, 167 ms in an earlier run).
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
    /// A fitted slope beyond this is not clock drift (audio clocks drift by tens of ppm, ±100 ppm at worst; PERF-013's
    /// tests inject ±250 ppm): no detection. QA-011 (D1/D2, 2026-11-15): a newly attached visual's start-up lateness
    /// fitted as −3,300 and −5,600 ppm; QA-011 (D2 microphone, 2026-11-20): a wandering latency fitted as −753 ppm.
    /// Either way the correction toward that target inflated every measured age.
    public var maximumPPM: Double
    /// Keeping a detection: the window's halves must agree within this many standard errors of their difference
    /// (looser than `significance`, hysteresis against noise).
    public var stabilitySignificance: Double
    /// Slack of the correction target beyond the residual floor's observed movement (about two bucket minima of noise).
    public var floorMarginNanoseconds: Double
    /// A straight floor: the fit's residual variance at most this many times the successive-difference noise variance.
    public var maximumLinearity: Double
    /// Consecutive passing fits (closed buckets) before a detection, with the slope steady within 2 × `significance`
    /// standard errors (at least `detectPPM`).
    public var confirmBuckets: Int

    public init(sampleRate: Double = 44_100, bucketSeconds: Double = 1, capacity: Int = 64, minimumBuckets: Int = 30,
                detectPPM: Double = 50, clearPPM: Double = 25, significance: Double = 3, stepNanoseconds: Double = 10_000_000,
                maximumPPM: Double = 300, stabilitySignificance: Double = 4, floorMarginNanoseconds: Double = 2_000_000,
                maximumLinearity: Double = 2, confirmBuckets: Int = 10) {
        self.sampleRate = sampleRate
        self.bucketSeconds = bucketSeconds
        self.capacity = max(capacity, 3)
        self.minimumBuckets = min(max(minimumBuckets, 3), self.capacity)
        self.detectPPM = detectPPM
        self.clearPPM = clearPPM
        self.significance = significance
        self.stepNanoseconds = stepNanoseconds
        self.maximumPPM = maximumPPM
        self.stabilitySignificance = stabilitySignificance
        self.floorMarginNanoseconds = floorMarginNanoseconds
        self.maximumLinearity = maximumLinearity
        self.confirmBuckets = max(confirmBuckets, 1)
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

    /// The detection candidate: consecutive fits that passed, and their slope range (ppm).
    private var candidateRun: Int = 0
    private var candidateLow: Double = 0
    private var candidateHigh: Double = 0
    /// How far the residual floor moved since the session's first closed bucket, latency steps excluded (ns).
    private var floorMovement: Double = 0

    /// The latest fitted drift in ppm (held across a step restart); nil before the first fit.
    public private(set) var driftPPM: Double?
    public private(set) var detected: Bool = false
    /// Times the verdict went from not detected to detected.
    public private(set) var detections: Int = 0
    /// Latency steps seen.
    public private(set) var steps: Int = 0
    /// Fits whose window halves disagreed (a wandering latency, not a clock rate): no detection, or a cleared one.
    public private(set) var unstableFits: Int = 0

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
        floorMovement = 0
        candidateRun = 0
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

    /// The correction target at `sessionSample` (ns to add to the bus host time): drift × audio time while detected,
    /// limited to the residual floor's observed movement plus the margin, in the same direction.
    public func targetNanoseconds(atSessionSample sessionSample: Int64) -> Double {
        guard detected, let drift = driftPPM else { return 0 }
        let seconds: Double = Double(max(sessionSample, 0)) / configuration.sampleRate
        let target: Double = drift * 1_000 * seconds
        // The floor's movement up to the newest closed bucket, carried on to `sessionSample` at the fitted drift.
        let moved: Double = floorMovement + drift * 1_000 * max(seconds - newestTime, 0)
        let margin: Double = configuration.floorMarginNanoseconds
        let limit: Double = target * moved < 0 ? margin : abs(moved) + margin
        return max(min(target, limit), -limit)
    }

    // MARK: - Fit

    private mutating func close(time: Double, residual: Double) -> Bool {
        if count > 0 {
            let slope: Double = (driftPPM ?? 0) * 1_000   // ns per s
            let predicted: Double = newestResidual + slope * (time - newestTime)
            if abs(residual - predicted) > configuration.stepNanoseconds {
                steps += 1
                segment += 1   // a new intercept from here on; the slope is shared
                floorMovement += predicted - newestResidual   // the step itself is latency, not drift
            } else {
                floorMovement += residual - newestResidual
            }
        }
        append(time: time, residual: residual)
        guard count >= configuration.minimumBuckets, let fit = fit(0, count) else { return false }
        driftPPM = fit.ppm
        return updateVerdict(ppm: fit.ppm, standardError: fit.standardErrorPPM)
    }

    /// The slopes of the window's older and newer halves differ by at most `sigmas` standard errors of their difference
    /// (and at least `detectPPM`): a constant clock rate, not a bending latency.
    private func halvesAgree(sigmas: Double) -> Bool {
        let half: Int = count / 2
        guard let whole = fit(0, count), whole.linearity <= configuration.maximumLinearity,
              let older = fit(0, half), let newer = fit(half, count) else { return false }
        let error: Double = (older.standardErrorPPM * older.standardErrorPPM + newer.standardErrorPPM * newer.standardErrorPPM).squareRoot()
        return abs(older.ppm - newer.ppm) <= max(configuration.detectPPM, sigmas * error)
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
    /// regression), and the slope's standard error (ppm); nil when the times do not spread. Over the window's buckets
    /// `from..<to` (oldest = 0). `linearity`: the fit's residual variance over the noise variance estimated from
    /// successive differences (von Neumann); about 1 for a straight line plus independent noise, large for a bending
    /// floor (a wandering latency), whose successive differences stay small while the line misses it.
    private func fit(_ from: Int, _ to: Int) -> (ppm: Double, standardErrorPPM: Double, linearity: Double)? {
        var sxx: Double = 0
        var sxy: Double = 0
        var groups: Int = 0
        var start: Int = from
        while start < to {
            let end: Int = segmentEnd(from: start, to: to)
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
        var differenceSquares: Double = 0
        var differences: Int = 0
        start = from
        while start < to {
            let end: Int = segmentEnd(from: start, to: to)
            let means: (t: Double, r: Double) = segmentMeans(start, end)
            for k in start..<end {
                let i: Int = ringIndex(k)
                let error: Double = residuals[i] - (means.r + slope * (times[i] - means.t))
                squares += error * error
                if k > start {
                    let p: Int = ringIndex(k - 1)
                    let d: Double = residuals[i] - residuals[p] - slope * (times[i] - times[p])
                    differenceSquares += d * d
                    differences += 1
                }
            }
            start = end
        }
        let variance: Double = squares / Double(max(to - from - groups - 1, 1))
        let standardError: Double = (variance / sxx).squareRoot()
        let noise: Double = differenceSquares / Double(max(2 * differences, 1))
        let linearity: Double = noise > 0 ? variance / noise : (variance > 0 ? .infinity : 1)
        return (slope / 1_000, standardError / 1_000, linearity)
    }

    private func ringIndex(_ k: Int) -> Int { (head + k) % configuration.capacity }

    /// The end (exclusive) of the run of buckets in the same segment as bucket `start`.
    private func segmentEnd(from start: Int, to limit: Int) -> Int {
        let id: Int = segments[ringIndex(start)]
        var end: Int = start + 1
        while end < limit, segments[ringIndex(end)] == id { end += 1 }
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
            guard magnitude >= configuration.detectPPM, magnitude <= configuration.maximumPPM, significant else {
                candidateRun = 0
                return false
            }
            guard halvesAgree(sigmas: configuration.significance) else {
                unstableFits += 1
                candidateRun = 0
                return false
            }
            // Persistence: the candidate must hold, with a steady slope, over `confirmBuckets` consecutive fits.
            if candidateRun == 0 {
                candidateLow = ppm
                candidateHigh = ppm
            } else {
                candidateLow = min(candidateLow, ppm)
                candidateHigh = max(candidateHigh, ppm)
            }
            candidateRun += 1
            guard candidateHigh - candidateLow <= max(configuration.detectPPM, 2 * configuration.significance * standardError) else {
                unstableFits += 1
                candidateRun = 0
                return false
            }
            guard candidateRun >= configuration.confirmBuckets else { return false }
            candidateRun = 0
            detected = true
            detections += 1
            return true
        }
        let stable: Bool = magnitude <= configuration.maximumPPM && halvesAgree(sigmas: configuration.stabilitySignificance)
        if !stable { unstableFits += 1 }
        guard magnitude < configuration.clearPPM || !stable else { return false }
        detected = false
        return true
    }
}
