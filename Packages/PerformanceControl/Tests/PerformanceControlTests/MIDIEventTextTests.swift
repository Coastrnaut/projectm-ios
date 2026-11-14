// MIDI-002-T09 (MIDI-002-R6; spec Clarifications: 60 = C4, sharps only): display and spoken texts per kind.
import PerformanceControl
import XCTest

final class MIDIEventTextTests: XCTestCase {
    private func text(_ kind: MIDIEventKind, _ channel: UInt8 = 0, _ number: UInt8 = 0, _ value: UInt32 = 0) -> MIDIEventText {
        MIDIEventText(MIDIEvent(kind: kind, channel: channel, number: number, value: value))
    }

    func testChannelMessages() {
        let cc: MIDIEventText = text(.controlChange, 0, 7, 100)
        XCTAssertEqual([cc.type, cc.channel, cc.number, cc.value], ["Control change", "Ch 1", "CC 7", "100"])
        XCTAssertEqual(cc.spoken, "Control change, channel 1, controller 7, value 100")
        let note: MIDIEventText = text(.noteOn, 9, 61, 127)
        XCTAssertEqual([note.type, note.channel, note.number, note.value], ["Note on", "Ch 10", "61 C♯4", "127"])
        XCTAssertEqual(note.spoken, "Note on, channel 10, note 61 C sharp 4, velocity 127")
        XCTAssertEqual(text(.noteOff, 15, 60, 0).spoken, "Note off, channel 16, note 60 C4, velocity 0")
        XCTAssertEqual(text(.polyPressure, 0, 0, 5).spoken, "Poly pressure, channel 1, note 0 C-1, pressure 5")
        XCTAssertEqual(text(.programChange, 3, 5).spoken, "Program change, channel 4, program 5")
        XCTAssertEqual(text(.programChange, 3, 5).number, "Program 5")
        XCTAssertEqual(text(.channelPressure, 0, 0, 90).spoken, "Channel pressure, channel 1, pressure 90")
        XCTAssertEqual(text(.pitchBend, 1, 0, 8_192).spoken, "Pitch bend, channel 2, value 8192")
        XCTAssertEqual(text(.pitchBend, 1, 0, 16_383).value, "16383")
    }

    func testSystemMessagesHaveNoChannel() {
        let sysex: MIDIEventText = text(.systemExclusive, 0, 0, 24)
        XCTAssertEqual([sysex.channel, sysex.value, sysex.spoken], ["", "24 bytes", "System exclusive, 24 bytes"])
        XCTAssertEqual(text(.systemExclusive, 0, 0, 1).value, "1 byte")
        XCTAssertEqual(text(.songSelect, 0, 9, 9).spoken, "Song select, song 9")
        XCTAssertEqual(text(.songPosition, 0, 0, 257).spoken, "Song position, value 257")
        XCTAssertEqual(text(.timeCode, 0, 0, 49).spoken, "Time code, value 49")
        for kind in [MIDIEventKind.start, .continue, .stop, .reset, .tuneRequest] {
            let t: MIDIEventText = text(kind)
            XCTAssertEqual(t.spoken, t.type, "\(kind): type only")
            XCTAssertEqual(t.channel + t.number + t.value, "")
        }
    }

    func testNoteNames() {
        XCTAssertEqual(MIDIEventText.noteName(60), "C4")
        XCTAssertEqual(MIDIEventText.noteName(69), "A4")
        XCTAssertEqual(MIDIEventText.noteName(0), "C-1")
        XCTAssertEqual(MIDIEventText.noteName(127), "G9")
        XCTAssertEqual(MIDIEventText.spokenNoteName(70), "A sharp 4")
    }
}
