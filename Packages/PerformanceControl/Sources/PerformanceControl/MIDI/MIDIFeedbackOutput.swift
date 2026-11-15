// MIDIFeedbackOutput.swift — where feedback messages go (MIDI-009-R9, R13; specs/269-midi-009-midi-feedback, contract F5,
// research MIDI-009-D6).
//
// Pure Swift, Linux-testable. The app holds one `MIDIFeedbackOutput`: `CoreMIDIFeedbackOutput` on Apple platforms
// (MIDISystem/), a `RecordingMIDIFeedbackOutput` in tests and with the DEBUG stand-in MIDI system. Messages are MIDI 1.0
// control changes; `MIDIFeedbackUMP` builds their Universal MIDI Packet words (message type 0x2, group 0).

/// Sends feedback messages to destinations (main actor in the app).
public protocol MIDIFeedbackOutput: AnyObject {
    /// Sends `messages`, in order, to each of `destinations` (MIDI-001 IDs); unknown IDs are skipped.
    func send(_ messages: [MIDIFeedbackMessage], to destinations: Set<MIDIEndpointID>)
}

/// Keeps every send (the mock output; data only, nothing leaves the process).
public final class RecordingMIDIFeedbackOutput: MIDIFeedbackOutput {
    public struct Send: Sendable, Hashable {
        public let messages: [MIDIFeedbackMessage]
        public let destinations: Set<MIDIEndpointID>
    }

    public private(set) var sends: [Send] = []

    public init() {}

    public func send(_ messages: [MIDIFeedbackMessage], to destinations: Set<MIDIEndpointID>) {
        guard !messages.isEmpty, !destinations.isEmpty else { return }
        sends.append(Send(messages: messages, destinations: destinations))
    }

    /// Every message sent, in order (once per send call, whatever the destination count).
    public var messages: [MIDIFeedbackMessage] { sends.flatMap { (send: Send) -> [MIDIFeedbackMessage] in send.messages } }

    public func removeAll() { sends.removeAll() }
}

/// MIDI 1.0 channel voice words in Universal MIDI Packets (research MIDI-009-D6).
public enum MIDIFeedbackUMP {
    /// `0x2` (MIDI 1.0 channel voice) · group 0 · status 0xB0 | channel · controller · value.
    public static func word(_ message: MIDIFeedbackMessage) -> UInt32 {
        let type: UInt32 = 0x2 << 28
        let status: UInt32 = UInt32(0xB0 | (message.channel & 0x0F)) << 16
        let controller: UInt32 = UInt32(message.controller & 0x7F) << 8
        let value: UInt32 = UInt32(message.value & 0x7F)
        return type | status | controller | value
    }
}
