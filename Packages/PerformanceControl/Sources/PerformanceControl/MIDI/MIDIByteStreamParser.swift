// MIDIByteStreamParser.swift — MIDI 1.0 bytes to events (MIDI-002-R3; research MIDI-002-D2; contracts/midi-input.md C1).
//
// * Channel status bytes (0x80–0xEF) set running status: later data bytes without a status repeat it.
// * Real-time bytes (0xF8–0xFF) are reported at once wherever they appear and leave the message in progress,
//   running status and system exclusive untouched.
// * System common (0xF1–0xF6) cancels running status; 0xF0 starts system exclusive, whose data bytes are only
//   counted until 0xF7 or the next non-real-time status (one event with the byte count; contents dropped).
// * A data byte with no status, or a message cut short by a new status, is ignored.
// Used by `ScriptedMIDIInputProvider`; real-time safe like the UMP decoder (no allocation, no locks).

public struct MIDIByteStreamParser: Sendable {
    private var status: UInt8 = 0          // running status, or the pending system common status; 0 = none
    private var expected: Int = 0          // data bytes the status needs
    private var data1: UInt8 = 0
    private var received: Int = 0
    private var inSysEx = false
    private var sysExLength: UInt32 = 0

    public init() {}

    public mutating func feed<Sink: MIDIEventSink>(_ bytes: UnsafeBufferPointer<UInt8>, timestamp: UInt64,
                                                   into sink: inout Sink) {
        for byte in bytes { feed(byte, timestamp: timestamp, into: &sink) }
    }

    public mutating func feed<Sink: MIDIEventSink>(_ byte: UInt8, timestamp: UInt64, into sink: inout Sink) {
        if byte >= 0xF8 {
            if let event = MIDIEvent.realTime(status: byte, timestamp: timestamp) { sink.receive(event) }
            return
        }
        if byte >= 0x80 {
            if inSysEx { endSysEx(timestamp: timestamp, into: &sink) }
            if byte == 0xF7 { return }   // an end without a start: ignored
            beginStatus(byte, timestamp: timestamp, into: &sink)
            return
        }
        if inSysEx {
            sysExLength &+= 1
            return
        }
        guard status != 0 else { return }   // stray data byte
        if received == 0 {
            data1 = byte
            received = 1
            if expected == 1 { complete(data2: 0, timestamp: timestamp, into: &sink) }
        } else {
            complete(data2: byte, timestamp: timestamp, into: &sink)
        }
    }

    private mutating func beginStatus<Sink: MIDIEventSink>(_ byte: UInt8, timestamp: UInt64, into sink: inout Sink) {
        received = 0
        if byte < 0xF0 {
            status = byte
            expected = MIDIEvent.dataLength(forChannelStatus: byte)
            return
        }
        switch byte {
        case 0xF0:
            status = 0
            inSysEx = true
            sysExLength = 0
        case 0xF1, 0xF3:
            status = byte
            expected = 1
        case 0xF2:
            status = byte
            expected = 2
        case 0xF6:
            status = 0
            sink.receive(MIDIEvent(kind: .tuneRequest, timestamp: timestamp))
        default:   // 0xF4, 0xF5 undefined
            status = 0
        }
    }

    private mutating func complete<Sink: MIDIEventSink>(data2: UInt8, timestamp: UInt64, into sink: inout Sink) {
        received = 0
        if status < 0xF0 {
            if let event = MIDIEvent.channelVoice(status: status, data1: data1, data2: data2, timestamp: timestamp) {
                sink.receive(event)
            }
            return   // running status stays
        }
        switch status {
        case 0xF1:
            sink.receive(MIDIEvent(kind: .timeCode, value: UInt32(data1), timestamp: timestamp))
        case 0xF2:
            let position: UInt32 = (UInt32(data2) << 7) | UInt32(data1)
            sink.receive(MIDIEvent(kind: .songPosition, value: position, timestamp: timestamp))
        case 0xF3:
            sink.receive(MIDIEvent(kind: .songSelect, number: data1, value: UInt32(data1), timestamp: timestamp))
        default:
            break
        }
        status = 0   // system common does not run
    }

    private mutating func endSysEx<Sink: MIDIEventSink>(timestamp: UInt64, into sink: inout Sink) {
        sink.receive(MIDIEvent(kind: .systemExclusive, value: sysExLength, timestamp: timestamp))
        inSysEx = false
        sysExLength = 0
    }
}
