// MIDIEventText.swift — what the monitor shows and VoiceOver reads for one message (MIDI-002-R6; spec
// Clarifications: middle C 60 = C4, sharps only). Pure Swift, Linux-testable; strings are built in typed steps.
// Only the message is described: no source, no time (the monitor adds the time column itself).

public struct MIDIEventText: Sendable, Hashable {
    /// "Control change"
    public let type: String
    /// "Ch 1"; empty for system messages.
    public let channel: String
    /// "CC 7", "60 C4", "Program 5", "Song 9"; empty when none.
    public let number: String
    /// "100", "8192", "24 bytes"; empty when none.
    public let value: String
    /// "Control change, channel 1, controller 7, value 100"
    public let spoken: String

    private static let sharpNames: [String] = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let spokenNames: [String] = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp", "G", "G sharp",
                                                "A", "A sharp", "B"]

    /// "C4" for 60, "C♯-1" for 1.
    public static func noteName(_ note: UInt8) -> String {
        let index: Int = Int(note % 12)
        let octave: Int = Int(note / 12) - 1
        return sharpNames[index] + String(octave)
    }

    /// "C4" for 60, "C sharp 4" for 61.
    public static func spokenNoteName(_ note: UInt8) -> String {
        let index: Int = Int(note % 12)
        let octave: Int = Int(note / 12) - 1
        let name: String = spokenNames[index]
        let separator: String = name.count > 1 ? " " : ""
        return name + separator + String(octave)
    }

    public static func typeName(_ kind: MIDIEventKind) -> String {
        switch kind {
        case .noteOn: "Note on"
        case .noteOff: "Note off"
        case .polyPressure: "Poly pressure"
        case .controlChange: "Control change"
        case .programChange: "Program change"
        case .channelPressure: "Channel pressure"
        case .pitchBend: "Pitch bend"
        case .systemExclusive: "System exclusive"
        case .timeCode: "Time code"
        case .songPosition: "Song position"
        case .songSelect: "Song select"
        case .tuneRequest: "Tune request"
        case .clock: "Clock"
        case .start: "Start"
        case .continue: "Continue"
        case .stop: "Stop"
        case .activeSensing: "Active sensing"
        case .reset: "Reset"
        }
    }

    public init(_ event: MIDIEvent) {
        let type: String = Self.typeName(event.kind)
        let channelNumber: String = String(Int(event.channel) + 1)
        let numberDigits: String = String(event.number)
        let valueDigits: String = String(event.value)
        var channel: String = ""
        var number: String = ""
        var value: String = ""
        var parts: [String] = [type]
        if event.kind.isChannelMessage {
            channel = "Ch " + channelNumber
            parts.append("channel " + channelNumber)
        }
        switch event.kind {
        case .noteOn, .noteOff:
            number = numberDigits + " " + Self.noteName(event.number)
            value = valueDigits
            parts.append("note " + numberDigits + " " + Self.spokenNoteName(event.number))
            parts.append("velocity " + valueDigits)
        case .polyPressure:
            number = numberDigits + " " + Self.noteName(event.number)
            value = valueDigits
            parts.append("note " + numberDigits + " " + Self.spokenNoteName(event.number))
            parts.append("pressure " + valueDigits)
        case .controlChange:
            number = "CC " + numberDigits
            value = valueDigits
            parts.append("controller " + numberDigits)
            parts.append("value " + valueDigits)
        case .programChange:
            number = "Program " + numberDigits
            parts.append("program " + numberDigits)
        case .channelPressure:
            value = valueDigits
            parts.append("pressure " + valueDigits)
        case .pitchBend, .timeCode, .songPosition:
            value = valueDigits
            parts.append("value " + valueDigits)
        case .songSelect:
            number = "Song " + numberDigits
            parts.append("song " + numberDigits)
        case .systemExclusive:
            let unit: String = event.value == 1 ? " byte" : " bytes"
            value = valueDigits + unit
            parts.append(value)
        case .tuneRequest, .clock, .start, .continue, .stop, .activeSensing, .reset:
            break
        }
        self.type = type
        self.channel = channel
        self.number = number
        self.value = value
        self.spoken = parts.joined(separator: ", ")
    }
}
