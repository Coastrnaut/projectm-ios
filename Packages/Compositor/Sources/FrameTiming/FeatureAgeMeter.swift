// FeatureAgeMeter.swift — PERF-013 (specs/216-perf-013-audio-render-sync, R1, R2, R5, R7, R11; contracts/feature-age.md
// C1; research PERF-013-D3, D4): the age of the newest consumed analysis frame at each presented frame.
//
// * `frame(_:arrivalNanoseconds:presentationNanoseconds:)` runs on the frame thread once per presented frame, while the
//   performance overlay is shown. A stamp with a new sequence is a first read: its residual (arrival − bus host time)
//   feeds `AudioClockDriftEstimator`. A nil stamp means nothing new arrived; the newest stamp so far is still shown.
// * The applied correction moves toward the estimator's target by at most 0.25 ms per call and never past it, so the
//   mapping never jumps (R5). Age = presentation − (bus host time + correction); a negative age is an anomaly.
// * A new analysis session (the stamp's session changed) resets the estimate, the correction and the newest stamp
//   (R7). `beginCountingSession` (each overlay attach) resets the counting session's figures and the estimate, not the
//   app session's histogram (the PERF-012 report's, since launch).
// * One `Mutex`, every buffer allocated in `init`: a call allocates nothing. Times are injected (CLOCK_UPTIME_RAW
//   nanoseconds in the app); nothing here reads a clock. Local and in memory only (R11).
import Foundation
import Synchronization

/// A consumed analysis frame (data model: clock observation).
public struct FeatureFrameStamp: Sendable, Equatable {
    public var session: UInt64
    public var sequence: UInt64
    public var sessionSample: Int64
    public var busHostNanoseconds: UInt64

    public init(session: UInt64, sequence: UInt64, sessionSample: Int64, busHostNanoseconds: UInt64) {
        self.session = session
        self.sequence = sequence
        self.sessionSample = sessionSample
        self.busHostNanoseconds = busHostNanoseconds
    }
}

/// The age figures of a counting session (or the app session); unavailable values are nil, never 0.
public struct FeatureAgeSummary: Sendable, Equatable {
    public var count: Int
    public var smoothedMs: Double?
    public var p50Ms: Double?
    public var p95Ms: Double?
    public var maxMs: Double?
    /// Presentations earlier than the frame's corrected audio time.
    public var anomalies: Int
    public var driftDetected: Bool
    public var driftPPM: Double?
    public var correctionMs: Double
    public var detections: Int
    public var steps: Int

    public init(count: Int = 0, smoothedMs: Double? = nil, p50Ms: Double? = nil, p95Ms: Double? = nil, maxMs: Double? = nil,
                anomalies: Int = 0, driftDetected: Bool = false, driftPPM: Double? = nil, correctionMs: Double = 0,
                detections: Int = 0, steps: Int = 0) {
        self.count = count
        self.smoothedMs = smoothedMs
        self.p50Ms = p50Ms
        self.p95Ms = p95Ms
        self.maxMs = maxMs
        self.anomalies = anomalies
        self.driftDetected = driftDetected
        self.driftPPM = driftPPM
        self.correctionMs = correctionMs
        self.detections = detections
        self.steps = steps
    }
}

/// Feature age at presentation with drift-corrected audio times (contract C1).
public final class FeatureAgeMeter: Sendable {
    /// The largest change of the applied correction per presented frame (R5).
    public static let maxStepNanoseconds: Double = 250_000
    /// Time constant of the smoothed age.
    public static let smoothingSeconds: Double = 0.5

    private struct State {
        var estimator: AudioClockDriftEstimator
        var correction: Double = 0
        var newest: FeatureFrameStamp?
        var smoothed: Double?
        var lastPresentation: UInt64?
        var counting = FrameIntervalHistogram()
        var countingAnomalies: Int = 0
        var app = FrameIntervalHistogram()
        var appAnomalies: Int = 0
    }

    private let state: Mutex<State>

    public init(configuration: AudioClockDriftConfiguration = .standard) {
        state = Mutex(State(estimator: AudioClockDriftEstimator(configuration: configuration)))
    }

    /// Zeroes the counting session's figures and restarts the drift estimate and correction (each overlay attach: the
    /// visual may feed another analysis pipeline, whose sessions and sequences start over). The app session stays.
    public func beginCountingSession() {
        state.withLock { (s: inout State) -> Void in
            s.estimator.reset()
            s.correction = 0
            s.newest = nil
            s.counting = FrameIntervalHistogram()
            s.countingAnomalies = 0
            s.smoothed = nil
            s.lastPresentation = nil
        }
    }

    /// One presented frame. Returns the age sample in nanoseconds (nil without a consumed frame; negative = anomaly).
    @discardableResult
    public func frame(_ stamp: FeatureFrameStamp?, arrivalNanoseconds: UInt64, presentationNanoseconds: UInt64) -> Double? {
        state.withLock { (s: inout State) -> Double? in
            Self.step(&s, stamp: stamp, arrival: arrivalNanoseconds, presentation: presentationNanoseconds)
        }
    }

    /// The counting session's figures.
    public func summary() -> FeatureAgeSummary {
        state.withLock { (s: inout State) -> FeatureAgeSummary in Self.summarize(s, histogram: s.counting, anomalies: s.countingAnomalies) }
    }

    /// Every age measured since init (the PERF-012 report).
    public func appSummary() -> FeatureAgeSummary {
        state.withLock { (s: inout State) -> FeatureAgeSummary in Self.summarize(s, histogram: s.app, anomalies: s.appAnomalies) }
    }

    /// The applied correction in nanoseconds (tests).
    public var correctionNanoseconds: Double { state.withLock { (s: inout State) -> Double in s.correction } }

    // MARK: - Frame path

    private static func step(_ s: inout State, stamp: FeatureFrameStamp?, arrival: UInt64, presentation: UInt64) -> Double? {
        if let stamp { consume(&s, stamp: stamp, arrival: arrival) }
        guard let newest = s.newest else { return nil }
        let target: Double = s.estimator.targetNanoseconds(atSessionSample: newest.sessionSample)
        let delta: Double = min(max(target - s.correction, -maxStepNanoseconds), maxStepNanoseconds)
        s.correction += delta
        let audio: Double = Double(newest.busHostNanoseconds) + s.correction
        let age: Double = Double(presentation) - audio
        record(&s, age: age, presentation: presentation)
        return age
    }

    private static func consume(_ s: inout State, stamp: FeatureFrameStamp, arrival: UInt64) {
        if let newest = s.newest {
            if newest.session != stamp.session {
                s.estimator.reset()
                s.correction = 0
            } else if newest.sequence == stamp.sequence {
                return
            }
        }
        s.newest = stamp
        let residual: Double = Double(Int64(bitPattern: arrival &- stamp.busHostNanoseconds))
        s.estimator.observe(sessionSample: stamp.sessionSample, residualNanoseconds: residual)
    }

    private static func record(_ s: inout State, age: Double, presentation: UInt64) {
        guard age >= 0 else {
            s.countingAnomalies += 1
            s.appAnomalies += 1
            return
        }
        let seconds: Double = max(age, 1) / 1_000_000_000   // the histogram ignores 0
        s.counting.record(seconds: seconds)
        s.app.record(seconds: seconds)
        var weight: Double = 1
        if let last = s.lastPresentation, presentation > last, s.smoothed != nil {
            let dt: Double = Double(presentation - last) / 1_000_000_000
            weight = 1 - exp(-dt / smoothingSeconds)
        }
        s.smoothed = (s.smoothed ?? age) + weight * (age - (s.smoothed ?? age))
        s.lastPresentation = presentation
    }

    private static func summarize(_ s: State, histogram: FrameIntervalHistogram, anomalies: Int) -> FeatureAgeSummary {
        let available: Bool = histogram.count > 0
        return FeatureAgeSummary(count: histogram.count, smoothedMs: available ? s.smoothed.map { (v: Double) -> Double in v / 1_000_000 } : nil,
                                 p50Ms: histogram.percentile(0.5), p95Ms: histogram.percentile(0.95),
                                 maxMs: available ? histogram.maxMs : nil, anomalies: anomalies,
                                 driftDetected: s.estimator.detected, driftPPM: s.estimator.driftPPM,
                                 correctionMs: s.correction / 1_000_000, detections: s.estimator.detections,
                                 steps: s.estimator.steps)
    }
}
