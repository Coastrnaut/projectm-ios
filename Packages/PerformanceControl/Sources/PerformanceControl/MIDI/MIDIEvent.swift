// MIDIEvent.swift — one received MIDI 1.0 message (MIDI-002-R3, R7, R14; specs/125-midi-002-midi-input-monitor,
// data-model.md).
//
// Pure Swift, Linux-testable, a 16-byte value with no references, so the real-time path copies it into a
// preallocated ring without allocating. It carries the message only: no field names the endpoint that sent it
// (MIDI-002-R7, research MIDI-002-D4). MIDI-003 (learn) keys bindings on `controlKey`; MIDI-004 (scaling)
// reads `normalizedValue`.

/// The MIDI 1.0 message kinds the decoders produce.
public enum MIDIEventKind: UInt8, Sendable, Hashable, CaseIterable {
    case noteOff
    case noteOn
    case polyPressure
    case controlChange
    case programChange
    case channelPressure
    case pitchBend
    /// System exclusive: `value` is the byte count; the contents are never kept.
    case systemExclusive
    /// MIDI time code quarter frame: `value` is the data byte.
    case timeCode
    /// Song position pointer: `value` is 0–16383 (MIDI beats).
    case songPosition
    case songSelect
    case tuneRequest
    /// Timing clock: counted by the ring, never stored (MIDI-002-R4).
    case clock
    case start
    case `continue`
    case stop
    /// Active sensing: counted by the ring, never stored (MIDI-002-R4).
    case activeSensing
    case reset

    /// Channel voice messages (they carry a channel).
    public var isChannelMessage: Bool { rawValue <= MIDIEventKind.pitchBend.rawValue }

    /// Real-time messages that are only counted (MIDI-002-R4).
    public var isCountedOnly: Bool { self == .clock || self == .activeSensing }
}

/// One message (data-model.md).
public struct MIDIEvent: Sendable, Hashable {
    public var kind: MIDIEventKind
    /// 0–15 for channel messages; 0 for system messages.
    public var channel: UInt8
    /// Note, controller or program; 0 when the kind has none.
    public var number: UInt8
    /// Velocity, controller value or pressure (0–127); pitch bend and song position (0–16383); system
    /// exclusive byte count; time code data byte.
    public var value: UInt32
    /// Monotonic nanoseconds (the system's uptime clock); 0 when unknown.
    public var timestamp: UInt64

    public init(kind: MIDIEventKind, channel: UInt8 = 0, number: UInt8 = 0, value: UInt32 = 0, timestamp: UInt64 = 0) {
        self.kind = kind
        self.channel = channel
        self.number = number
        self.value = value
        self.timestamp = timestamp
    }

    /// What a binding listens to (MIDI-003): kind, channel and number. A note on and its note off share a key
    /// kind of `.noteOn` so a learned note follows both.
    public var controlKey: MIDIControlKey {
        let keyKind: MIDIEventKind = kind == .noteOff ? .noteOn : kind
        return MIDIControlKey(kind: keyKind, channel: channel, number: number)
    }

    /// MIDI-006-R1 (contract N1): the one place that decides whether a note message presses or releases its key.
    /// `.on` for a note on with velocity > 0; `.off` for a note off or a note on with velocity 0 (MIDI 1.0); nil
    /// for every other kind. The parsers already build velocity-0 note ons as note offs; this also covers events
    /// built by hand.
    public var noteEdge: MIDINoteEdge? {
        switch kind {
        case .noteOn: return value == 0 ? .off : .on
        case .noteOff: return .off
        default: return nil
        }
    }

    /// 0…1 for 7-bit channel values (value / 127) and pitch bend (value / 16383); nil for other kinds (MIDI-004).
    public var normalizedValue: Double? {
        switch kind {
        case .noteOn, .noteOff, .polyPressure, .controlChange, .channelPressure:
            let clamped: UInt32 = min(value, 127)
            return Double(clamped) / 127.0
        case .pitchBend:
            let clamped: UInt32 = min(value, 16_383)
            return Double(clamped) / 16_383.0
        default:
            return nil
        }
    }

    /// Builds a channel voice message from MIDI 1.0 status and data bytes (data bytes masked to 7 bits);
    /// nil for a status outside 0x80–0xEF. A note on with velocity 0 becomes a note off with value 0.
    public static func channelVoice(status: UInt8, data1: UInt8, data2: UInt8, timestamp: UInt64) -> MIDIEvent? {
        guard status >= 0x80, status < 0xF0 else { return nil }
        let channel: UInt8 = status & 0x0F
        let d1: UInt8 = data1 & 0x7F
        let d2: UInt8 = data2 & 0x7F
        switch status & 0xF0 {
        case 0x80:
            return MIDIEvent(kind: .noteOff, channel: channel, number: d1, value: UInt32(d2), timestamp: timestamp)
        case 0x90:
            let kind: MIDIEventKind = d2 == 0 ? .noteOff : .noteOn
            return MIDIEvent(kind: kind, channel: channel, number: d1, value: UInt32(d2), timestamp: timestamp)
        case 0xA0:
            return MIDIEvent(kind: .polyPressure, channel: channel, number: d1, value: UInt32(d2), timestamp: timestamp)
        case 0xB0:
            return MIDIEvent(kind: .controlChange, channel: channel, number: d1, value: UInt32(d2), timestamp: timestamp)
        case 0xC0:
            return MIDIEvent(kind: .programChange, channel: channel, number: d1, value: 0, timestamp: timestamp)
        case 0xD0:
            return MIDIEvent(kind: .channelPressure, channel: channel, number: 0, value: UInt32(d1), timestamp: timestamp)
        default:   // 0xE0
            let low: UInt32 = UInt32(d1)
            let high: UInt32 = UInt32(d2) << 7
            return MIDIEvent(kind: .pitchBend, channel: channel, number: 0, value: high | low, timestamp: timestamp)
        }
    }

    /// Data bytes a channel status needs (1 for program change and channel pressure, else 2).
    static func dataLength(forChannelStatus status: UInt8) -> Int {
        let high: UInt8 = status & 0xF0
        return high == 0xC0 || high == 0xD0 ? 1 : 2
    }

    /// Real-time status bytes 0xF8–0xFF; nil for undefined ones (0xF9, 0xFD).
    static func realTime(status: UInt8, timestamp: UInt64) -> MIDIEvent? {
        let kind: MIDIEventKind
        switch status {
        case 0xF8: kind = .clock
        case 0xFA: kind = .start
        case 0xFB: kind = .continue
        case 0xFC: kind = .stop
        case 0xFE: kind = .activeSensing
        case 0xFF: kind = .reset
        default: return nil
        }
        return MIDIEvent(kind: kind, timestamp: timestamp)
    }
}

/// A key press or release (MIDI-006, `MIDIEvent.noteEdge`).
public enum MIDINoteEdge: Sendable, Hashable {
    case on
    case off
}

/// A binding key (MIDI-003): kind (note on for notes), channel and number.
public struct MIDIControlKey: Sendable, Hashable {
    public let kind: MIDIEventKind
    public let channel: UInt8
    public let number: UInt8

    public init(kind: MIDIEventKind, channel: UInt8, number: UInt8) {
        self.kind = kind
        self.channel = channel
        self.number = number
    }
}

/// Where decoders put events (contract C1). Generic use keeps the real-time path free of existentials.
public protocol MIDIEventSink {
    mutating func receive(_ event: MIDIEvent)
}

/// Collects events into an array (tests and non-real-time callers only: it allocates).
public struct MIDIEventCollector: MIDIEventSink {
    public private(set) var events: [MIDIEvent] = []

    public init() {}

    public mutating func receive(_ event: MIDIEvent) { events.append(event) }
}
