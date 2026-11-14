// BeatRingTrigger.swift — which analysis events emit a beat ring (VIS-006-R2; contracts/beat-rings.md C3;
// research VIS-006-D1).
//
// ANL-005 beats with confidence ≥ 0.5 (`AdaptiveBeatTracker.highConfidence`) emit. ANL-007 kick transients
// emit only while no confident beat arrived in the previous 2 s on the bus clock (a song's start, rubato,
// beatless passages), so a beat and its kick give one ring. Onsets and the mid and high transients never emit.
// A session marker forgets the last beat. A pure function of the event sequence; a value type, no allocation.
import AnalysisFeatures

public struct BeatRingTrigger: Sendable, Equatable {
    /// The least ANL-005 confidence that emits.
    public static let minimumBeatConfidence = AdaptiveBeatTracker.highConfidence
    /// Kicks wait this long after a confident beat before they emit again, seconds.
    public static let kickFallbackDelay = 2.0

    /// Bus time of the newest confident beat, nil when none (or after a session marker).
    public private(set) var lastConfidentBeatNanoseconds: UInt64?

    public init() {}

    /// Whether `event` emits a ring; remembers confident beats.
    public mutating func shouldEmit(_ event: AnalysisEvent) -> Bool {
        let now: UInt64 = event.time.hostNanoseconds
        switch event.kind {
        case let .beat(_, _, confidence):
            guard confidence >= Self.minimumBeatConfidence else { return false }
            lastConfidentBeatNanoseconds = now
            return true
        case let .transient(band, _, _, _, _):
            guard band == .kick else { return false }
            guard let beat = lastConfidentBeatNanoseconds else { return true }
            guard now >= beat else { return false }
            return Double(now - beat) / 1e9 >= Self.kickFallbackDelay
        case .sessionStarted, .sessionEnded:
            lastConfidentBeatNanoseconds = nil
            return false
        case .onset:
            return false
        }
    }
}
