// AppCoordinator+MIDIFeedback.swift — MIDI-009 wiring (specs/269-midi-009-midi-feedback, contract F6, research D6, D7).
// Feedback reads the native host's base glow (manual value with MIDI and OSC live values in place; never MOD-002 or LFO
// layers) and sends through the CoreMIDI output; with the DEBUG stand-in MIDI system (`-uitestFakeMIDI`) it records
// instead, so no system MIDI is touched.
import ParameterGraph
import PerformanceControl
import VisualEffects

extension AppCoordinator {
    #if DEBUG
    /// MIDI-009: the recording output used with `-uitestFakeMIDI`.
    static let uitestFeedbackOutput = RecordingMIDIFeedbackOutput()
    #endif

    func connectMIDIFeedback() {
        midiMappings.feedbackValues = { [weak self] () -> [ParameterID: Double] in
            guard let host = self?.nativeVisual else { return [:] }   // no native visual: nothing to send
            return host.glow.applying(host.externalValues).midiFeedbackValues
        }
        midiMappings.feedbackOutput = Self.makeMIDIFeedbackOutput()
    }

    private static func makeMIDIFeedbackOutput() -> (any MIDIFeedbackOutput)? {
        #if DEBUG
        if UITestFakeMIDI.isRequested { return uitestFeedbackOutput }
        #endif
        #if canImport(CoreMIDI)
        return CoreMIDIFeedbackOutput()
        #else
        return nil
        #endif
    }
}
