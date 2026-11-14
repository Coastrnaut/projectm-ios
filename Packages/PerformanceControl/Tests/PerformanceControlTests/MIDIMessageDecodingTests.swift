// MIDI-002-T06 (MIDI-002-R3, R14, S3): the decoder tables. Byte streams (running status, interleaved real-time,
// SysEx, stray data) and UMP words (MIDI 1.0 protocol: system, channel voice, SysEx7 across packets, other
// message types skipped by word count). Pure Swift; runs on Linux.
import PerformanceControl
import XCTest

final class MIDIMessageDecodingTests: XCTestCase {
    private func bytes(_ input: [UInt8], timestamp: UInt64 = 7) -> [MIDIEvent] {
        var parser = MIDIByteStreamParser()
        var sink = MIDIEventCollector()
        input.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Void in
            parser.feed(buffer, timestamp: timestamp, into: &sink)
        }
        return sink.events
    }

    private func words(_ input: [UInt32], decoder: inout MIDIUMPDecoder) -> [MIDIEvent] {
        var sink = MIDIEventCollector()
        input.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt32>) -> Void in
            decoder.decode(buffer, timestamp: 9, into: &sink)
        }
        return sink.events
    }

    private func words(_ input: [UInt32]) -> [MIDIEvent] {
        var decoder = MIDIUMPDecoder()
        return words(input, decoder: &decoder)
    }

    private func ev(_ kind: MIDIEventKind, _ channel: UInt8 = 0, _ number: UInt8 = 0, _ value: UInt32 = 0,
                    _ timestamp: UInt64 = 7) -> MIDIEvent {
        MIDIEvent(kind: kind, channel: channel, number: number, value: value, timestamp: timestamp)
    }

    // MARK: Byte streams

    func testChannelMessageTable() {
        let rows: [(input: [UInt8], expected: MIDIEvent)] = [
            ([0x90, 60, 100], ev(.noteOn, 0, 60, 100)),
            ([0x9F, 127, 127], ev(.noteOn, 15, 127, 127)),
            ([0x90, 60, 0], ev(.noteOff, 0, 60, 0)),          // velocity 0 = note off
            ([0x80, 0, 64], ev(.noteOff, 0, 0, 64)),
            ([0xA3, 61, 33], ev(.polyPressure, 3, 61, 33)),
            ([0xB0, 7, 100], ev(.controlChange, 0, 7, 100)),
            ([0xB0, 0, 0], ev(.controlChange, 0, 0, 0)),
            ([0xBF, 127, 127], ev(.controlChange, 15, 127, 127)),
            ([0xC4, 5], ev(.programChange, 4, 5, 0)),
            ([0xD1, 90], ev(.channelPressure, 1, 0, 90)),
            ([0xE0, 0x00, 0x00], ev(.pitchBend, 0, 0, 0)),
            ([0xE0, 0x00, 0x40], ev(.pitchBend, 0, 0, 8_192)),
            ([0xE0, 0x7F, 0x7F], ev(.pitchBend, 0, 0, 16_383)),
        ]
        for row in rows {
            XCTAssertEqual(bytes(row.input), [row.expected], "bytes \(row.input)")
        }
    }

    func testRunningStatusRepeatsTheLastChannelStatus() {
        let events: [MIDIEvent] = bytes([0xB0, 7, 10, 7, 20, 7, 30, 0xC0, 1, 2])
        XCTAssertEqual(events, [ev(.controlChange, 0, 7, 10), ev(.controlChange, 0, 7, 20),
                                ev(.controlChange, 0, 7, 30), ev(.programChange, 0, 1), ev(.programChange, 0, 2)])
        XCTAssertEqual(bytes([0x90, 60, 100, 60, 0]), [ev(.noteOn, 0, 60, 100), ev(.noteOff, 0, 60, 0)],
                       "a note off sent as running-status velocity 0")
    }

    func testRealTimeInsideAMessageLeavesItIntact() {
        let events: [MIDIEvent] = bytes([0x90, 0xF8, 60, 0xFA, 100, 0xF8, 61, 0xFC, 101])
        XCTAssertEqual(events, [ev(.clock), ev(.start), ev(.noteOn, 0, 60, 100), ev(.clock), ev(.stop),
                                ev(.noteOn, 0, 61, 101)])
    }

    func testSystemExclusiveIsItsLengthOnly() {
        XCTAssertEqual(bytes([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]), [ev(.systemExclusive, 0, 0, 4)])
        // Real-time inside SysEx is reported; a new status ends SysEx and starts its own message.
        XCTAssertEqual(bytes([0xF0, 1, 2, 0xF8, 3, 0xB0, 7, 1]),
                       [ev(.clock), ev(.systemExclusive, 0, 0, 3), ev(.controlChange, 0, 7, 1)])
        XCTAssertEqual(bytes([0xF7, 0xF0, 0xF7]), [ev(.systemExclusive, 0, 0, 0)], "a lone end is ignored")
    }

    func testSystemCommonCancelsRunningStatusAndStrayDataIsIgnored() {
        let events: [MIDIEvent] = bytes([5, 6, 0xB0, 7, 1, 0xF2, 0x01, 0x02, 7, 2, 0xF3, 9, 0xF1, 0x31, 0xF6])
        XCTAssertEqual(events, [ev(.controlChange, 0, 7, 1), ev(.songPosition, 0, 0, 0x101),
                                ev(.songSelect, 0, 9, 9), ev(.timeCode, 0, 0, 0x31), ev(.tuneRequest)])
        XCTAssertEqual(bytes([0x90, 60, 0xB0, 7, 1]), [ev(.controlChange, 0, 7, 1)], "a cut-short note is dropped")
        XCTAssertEqual(bytes([0xF9, 0xFD, 0xF4, 1, 0xFE, 0xFF, 0xFB]), [ev(.activeSensing), ev(.reset), ev(.continue)])
    }

    // MARK: UMP

    func testUMPChannelVoiceAndSystemWords() {
        let input: [UInt32] = [
            0x2090_3C64,   // group 0, note on ch 1, 60, 100
            0x2390_3C00,   // group 3, note on velocity 0 → note off
            0x20B0_0764,   // CC 7 = 100
            0x20E0_0040,   // bend centre
            0x20C5_0500,   // program 5 on ch 6
            0x10F8_0000,   // clock
            0x10F2_0102,   // song position 0x101
            0x10FA_0000,   // start
        ]
        let t: UInt64 = 9
        XCTAssertEqual(words(input), [ev(.noteOn, 0, 60, 100, t), ev(.noteOff, 0, 60, 0, t), ev(.controlChange, 0, 7, 100, t),
                                      ev(.pitchBend, 0, 0, 8_192, t), ev(.programChange, 5, 5, 0, t), ev(.clock, 0, 0, 0, t),
                                      ev(.songPosition, 0, 0, 0x101, t), ev(.start, 0, 0, 0, t)])
    }

    func testUMPSysExSpansPacketsAndOtherTypesAreSkipped() {
        var decoder = MIDIUMPDecoder()
        let first: [UInt32] = [0x3016_7E7F, 0x0601_0203, 0x4090_3C00, 0x1234_5678, 0x0000_0000]  // start 6 bytes; MIDI 2.0 note (2 words); utility
        XCTAssertEqual(words(first, decoder: &decoder), [], "nothing complete yet; the MIDI 2.0 packet is skipped")
        let second: [UInt32] = [0x3026_0102, 0x0304_0506, 0x3032_0102, 0x0000_0000,
                                0x5000_0000, 0, 0, 0, 0x20B0_0101]
        XCTAssertEqual(words(second, decoder: &decoder),
                       [ev(.systemExclusive, 0, 0, 14, 9), ev(.controlChange, 0, 1, 1, 9)],
                       "6 + 6 + 2 bytes; the 4-word data-128 packet is skipped")
        XCTAssertEqual(words([0x3005_0102, 0x0304_0500]), [ev(.systemExclusive, 0, 0, 5, 9)], "complete in one packet")
        XCTAssertEqual(words([0x2090_3C64, 0x4090]), [ev(.noteOn, 0, 60, 100, 9)], "a truncated packet ends the walk")
    }

    // MARK: R14 — reusable model

    func testControlKeyAndNormalizedValue() {
        let on: MIDIEvent = ev(.noteOn, 2, 60, 127)
        let off: MIDIEvent = ev(.noteOff, 2, 60, 0)
        XCTAssertEqual(on.controlKey, off.controlKey, "a note's on and off share a key")
        XCTAssertNotEqual(ev(.controlChange, 0, 7, 1).controlKey, ev(.controlChange, 1, 7, 1).controlKey)
        XCTAssertEqual(ev(.controlChange, 0, 7, 0).normalizedValue, 0)
        XCTAssertEqual(ev(.controlChange, 0, 7, 127).normalizedValue, 1)
        XCTAssertEqual(ev(.pitchBend, 0, 0, 16_383).normalizedValue, 1)
        let centre: Double = ev(.pitchBend, 0, 0, 8_192).normalizedValue ?? -1
        XCTAssertEqual(centre, 8_192.0 / 16_383.0, accuracy: 1e-12)
        XCTAssertNil(ev(.programChange, 0, 5).normalizedValue)
        XCTAssertNil(ev(.systemExclusive, 0, 0, 12).normalizedValue)
        XCTAssertEqual(MemoryLayout<MIDIEvent>.size, 16, "a 16-byte value")
    }
}
