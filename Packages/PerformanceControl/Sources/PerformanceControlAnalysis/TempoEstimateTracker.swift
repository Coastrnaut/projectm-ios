// TempoEstimateTracker.swift — the ANL-016 bus's tempo, as a `TempoEstimate` (SHOW-011-R9, R14;
// research SHOW-011-D4).
//
// Frames carry ANL-005's tempo and confidence (the latest frame wins; `bpm == nil` means no tempo).
// Beat events carry the beat's own sample in the session; its host time is the event's host time
// minus the samples between the beat and the end of the window that reported it. Session markers
// clear everything: a new session starts from no tempo, like the tracker itself.
import AnalysisFeatures
import PerformanceControl

public struct TempoEstimateTracker: Sendable {
    public let sampleRate: Double
    private var bpm: Double?
    private var confidence = 0.0
    private var beatNanoseconds: UInt64?

    public init(sampleRate: Double) {
        precondition(sampleRate > 0, "a positive sample rate")
        self.sampleRate = sampleRate
    }

    /// The current estimate; nil without a tempo.
    public var estimate: TempoEstimate? {
        bpm.map { TempoEstimate(bpm: $0, confidence: confidence, beatNanoseconds: beatNanoseconds) }
    }

    public mutating func observe(_ frame: AnalysisFrame) {
        bpm = frame.bpm
        confidence = frame.bpm == nil ? 0 : frame.beatConfidence
        if frame.bpm == nil { beatNanoseconds = nil }
    }

    public mutating func observe(_ event: AnalysisEvent) {
        switch event.kind {
        case .beat:
            let lagSamples = max(0, event.time.sessionSample - event.eventSample)
            let lag = UInt64((Double(lagSamples) / sampleRate * 1e9).rounded())
            let host = event.time.hostNanoseconds
            beatNanoseconds = host >= lag ? host - lag : 0
        case .sessionStarted, .sessionEnded:
            clear()
        case .onset, .transient:
            break
        }
    }

    public mutating func clear() {
        bpm = nil
        confidence = 0
        beatNanoseconds = nil
    }
}
