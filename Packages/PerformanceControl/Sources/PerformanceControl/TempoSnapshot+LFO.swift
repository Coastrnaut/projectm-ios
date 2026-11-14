// TempoSnapshot+LFO.swift — MOD-009: the tempo a synced oscillator follows (MOD-009-R3; specs/165-mod-009-tempo-lfo,
// research MOD-009-D1, contract T4).
//
// The snapshot's own order, unchanged: the manual tap tempo if set; otherwise ANL-005's estimate when its
// confidence is at least `TapTempoRules.minimumEstimateConfidence` (0.5) and its tempo is in range; otherwise nil, and
// the oscillator runs at its stored rate. `LFOSync.usableBPM` clamps what it receives to 40…240.
import ParameterGraph

extension TempoSnapshot {
    /// The BPM tempo-synced oscillators follow; nil without a tempo (they use their stored rate).
    public var lfoTempoBPM: Double? { bpm }
}
