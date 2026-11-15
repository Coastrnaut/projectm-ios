// MIDIMappingCoordinator+Feedback.swift — MIDI feedback in the app (MIDI-009-R2, R7-R12; specs/269-midi-009-midi-feedback,
// contract F6, research MIDI-009-D5, D7).
//
// * `feedbackTick()` runs after every input drain (30 Hz, only while the input receives: listening on, foreground, a
//   mapping exists), so background and listening off stop feedback with no extra state. It follows the binding list,
//   pairs destinations with the listened inputs (MIDI-001's list), resyncs when a paired destination appears, and sends
//   what `MIDIFeedbackEngine` allows for the parameters' base values (`feedbackValues`: manual or live, never MOD-002
//   or LFO modulation).
// * `receive` drops echoes of sent bytes first and reports the values it applied (no echo to the sender).
// * The options screen's "Send feedback" switch saves at once and announces on the `.midi` lane; no Undo step.
// Nothing about feedback is logged or stored beyond `fb=1`.
import ParameterGraph
import PerformanceControl
import VisualEffects
import VisualParameters

extension MIDIMappingCoordinator {
    /// The options screen's switch (MIDI-009-R12): saved at once, announced, no Undo step.
    func setFeedback(_ enabled: Bool, for target: ParameterID) {
        guard var options = options(for: target) else { return }
        options.feedback = enabled
        guard updateOptions(options, for: target) else { return }
        announce(name(of: target) + (enabled ? " feedback on." : " feedback off."))
    }

    /// Drops received bytes that echo feedback sent within 100 ms (MIDI-009-R8).
    func filterFeedbackEchoes(_ batch: [MIDIEvent]) -> [MIDIEvent] {
        guard feedback.isActive else { return batch }
        return feedback.filterEchoes(batch, now: clock())
    }

    /// Values just applied from the controller: what it shows now, quiet for 100 ms (MIDI-009-R7).
    func noteFeedbackApplied(_ values: [ParameterID: Double]) {
        guard feedback.isActive else { return }
        feedback.incomingApplied(values, registry: registry, now: clock())
    }

    /// Panic (MIDI-009-R10): pending feedback dropped, current values taken as shown.
    func absorbFeedback() {
        guard feedback.isActive else { return }
        feedback.absorb(feedbackValues(), registry: registry)
    }

    /// One tick (MIDI-009-R2-R6, R9, R11). No work when no mapping has feedback or no output exists.
    func feedbackTick() {
        if feedbackBindings != bindings {
            feedbackBindings = bindings
            feedback.configure(bindings: bindings)
        }
        guard feedback.isActive, let output = feedbackOutput else {
            feedbackDestinations = []
            return
        }
        let destinations: Set<MIDIEndpointID> = MIDIFeedbackRouting.destinations(in: discovery.list)
        if !destinations.subtracting(feedbackDestinations).isEmpty { feedback.resync() }   // R11: a controller appeared
        feedbackDestinations = destinations
        guard !destinations.isEmpty else { return }   // nothing sent, nothing queued
        let messages: [MIDIFeedbackMessage] = feedback.tick(values: feedbackValues(), registry: registry, now: clock())
        if !messages.isEmpty { output.send(messages, to: destinations) }
    }
}

extension BloomParameters {
    /// MIDI-009: the glow parameters a MIDI control can drive, by catalog ID (the base before modulation).
    var midiFeedbackValues: [ParameterID: Double] {
        [VisualParameterIDs.bloomIntensity: Double(intensity), VisualParameterIDs.bloomRadius: Double(radius),
         VisualParameterIDs.bloomThreshold: Double(threshold), VisualParameterIDs.bloomKnee: Double(knee)]
    }
}
