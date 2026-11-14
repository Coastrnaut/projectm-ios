// HapticCue+Analysis.swift — ACC-007 contract C2: ANL-016 events as haptic cues
// (specs/238-acc-007-haptic-beat-feedback). Beats (ANL-005) carry their confidence, ANL-007 kicks map to
// `.kick`, session markers restart the downbeat count; onsets, mid and high transients and section changes
// never pulse. Nothing here reaches projectM (Constitution VIII).
import AnalysisFeatures
import PerformanceControl

extension HapticCue {
    public init?(_ event: AnalysisEvent) {
        switch event.kind {
        case let .beat(_, _, confidence):
            self = .beat(confidence: confidence)
        case let .transient(band, _, _, _, _):
            guard band == .kick else { return nil }
            self = .kick
        case .sessionStarted, .sessionEnded:
            self = .sessionBoundary
        case .onset, .sectionChange:
            return nil
        }
    }
}
