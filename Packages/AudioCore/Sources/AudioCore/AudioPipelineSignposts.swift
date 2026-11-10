// AudioPipelineSignposts.swift — the latency stages of research R-06 (task T062; SC-006 budget).
//
// AudioCore cannot depend on Diagnostics (Diagnostics depends on AudioCore), so the analyzer calls
// this protocol and Diagnostics implements it with OSSignposter (`PipelineSignposts` in
// Logging.swift). Every call happens on the analysis work queue, never in an audio callback
// (Constitution VII).
public protocol AudioPipelineSignposts: Sendable {
    /// Wraps one drain of the source ring plus its conversion into the normalized ring, as a
    /// signpost interval (budget ≤ 20 ms).
    func ringAndConversion(_ body: () -> Void)
    /// The longest capture delivery since the previous call: from a buffer's capture timestamp to
    /// its arrival in PCMSink (budget ≤ 30 ms). Only sources that report capture timestamps count.
    func captureDelivery(milliseconds: Double)
    /// How much audio waited in the normalized ring when the renderer last read it, i.e. the age
    /// of the oldest frame read (budget ≤ 50 ms, capped by the freshness rule).
    func normalizedResidency(milliseconds: Double)
}
