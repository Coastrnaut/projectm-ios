// MIDIUMPDecoder.swift — Universal MIDI Packet words (MIDI 1.0 protocol) to events (MIDI-002-R3; research
// MIDI-002-D1; contracts/midi-input.md C1).
//
// The system input port is created with the MIDI 1.0 protocol, so channel messages arrive as message type 0x2
// words with running status already resolved. Decoded here:
// * 0x1 system common and real-time (1 word): status in bits 16-23, data in bits 8-14 and 0-6;
// * 0x2 MIDI 1.0 channel voice (1 word): status, data 1, data 2;
// * 0x3 data 64-bit / SysEx7 (2 words): status nibble (0 complete, 1 start, 2 continue, 3 end) and a byte
//   count; the counts are summed and one system exclusive event carries the total. Contents are dropped.
// Every other message type is skipped by its word count, so a stray MIDI 2.0 or data-128 packet never
// desynchronizes the walk. Real-time safe: no allocation, no locks; state is the SysEx byte count only.

public struct MIDIUMPDecoder: Sendable {
    private var sysExLength: UInt32 = 0
    private var inSysEx = false

    public init() {}

    /// Words per packet for each message type (UMP specification, table 4).
    static func wordCount(messageType: UInt32) -> Int {
        switch messageType {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4   // 0x5, 0xD, 0xE, 0xF
        }
    }

    public mutating func decode<Sink: MIDIEventSink>(_ words: UnsafeBufferPointer<UInt32>, timestamp: UInt64,
                                                     into sink: inout Sink) {
        var index: Int = 0
        let count: Int = words.count
        while index < count {
            let first: UInt32 = words[index]
            let type: UInt32 = first >> 28
            let length: Int = Self.wordCount(messageType: type)
            if index + length > count { return }   // a truncated packet: nothing more to decode
            switch type {
            case 0x1:
                decodeSystem(first, timestamp: timestamp, into: &sink)
            case 0x2:
                let status: UInt8 = UInt8(truncatingIfNeeded: first >> 16)
                let data1: UInt8 = UInt8(truncatingIfNeeded: first >> 8)
                let data2: UInt8 = UInt8(truncatingIfNeeded: first)
                if let event = MIDIEvent.channelVoice(status: status, data1: data1, data2: data2, timestamp: timestamp) {
                    sink.receive(event)
                }
            case 0x3:
                decodeSysEx7(first, timestamp: timestamp, into: &sink)
            default:
                break
            }
            index += length
        }
    }

    private func decodeSystem<Sink: MIDIEventSink>(_ word: UInt32, timestamp: UInt64, into sink: inout Sink) {
        let status: UInt8 = UInt8(truncatingIfNeeded: word >> 16)
        let data1: UInt8 = UInt8(truncatingIfNeeded: word >> 8) & 0x7F
        let data2: UInt8 = UInt8(truncatingIfNeeded: word) & 0x7F
        if status >= 0xF8 {
            if let event = MIDIEvent.realTime(status: status, timestamp: timestamp) { sink.receive(event) }
            return
        }
        switch status {
        case 0xF1:
            sink.receive(MIDIEvent(kind: .timeCode, value: UInt32(data1), timestamp: timestamp))
        case 0xF2:
            let position: UInt32 = (UInt32(data2) << 7) | UInt32(data1)
            sink.receive(MIDIEvent(kind: .songPosition, value: position, timestamp: timestamp))
        case 0xF3:
            sink.receive(MIDIEvent(kind: .songSelect, number: data1, value: UInt32(data1), timestamp: timestamp))
        case 0xF6:
            sink.receive(MIDIEvent(kind: .tuneRequest, timestamp: timestamp))
        default:
            break
        }
    }

    private mutating func decodeSysEx7<Sink: MIDIEventSink>(_ word: UInt32, timestamp: UInt64, into sink: inout Sink) {
        let status: UInt32 = (word >> 20) & 0xF
        let bytes: UInt32 = min((word >> 16) & 0xF, 6)
        switch status {
        case 0x0:   // complete in one packet
            sink.receive(MIDIEvent(kind: .systemExclusive, value: bytes, timestamp: timestamp))
            inSysEx = false
            sysExLength = 0
        case 0x1:   // start
            inSysEx = true
            sysExLength = bytes
        case 0x2:   // continue
            if inSysEx { sysExLength &+= bytes }
        case 0x3:   // end
            if inSysEx {
                let total: UInt32 = sysExLength &+ bytes
                sink.receive(MIDIEvent(kind: .systemExclusive, value: total, timestamp: timestamp))
            }
            inSysEx = false
            sysExLength = 0
        default:
            break
        }
    }
}
