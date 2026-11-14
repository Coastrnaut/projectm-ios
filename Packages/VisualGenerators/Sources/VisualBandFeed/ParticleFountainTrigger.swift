// ParticleFountainTrigger.swift — which analysis events launch a particle burst (VIS-008-R1, R2; contracts/
// particle-fountain.md C3; research VIS-008-D1).
//
// Every ANL-004 onset launches a burst sized by its strength and threshold; beats, transients and session
// markers never do. A pure function of the event; no allocation.
import AnalysisFeatures

public enum ParticleFountainTrigger {
    /// The onset's strength and threshold, nil for any other event.
    public static func onset(_ event: AnalysisEvent) -> (strength: Float, threshold: Float)? {
        guard case let .onset(strength, threshold) = event.kind else { return nil }
        return (strength, threshold)
    }
}
