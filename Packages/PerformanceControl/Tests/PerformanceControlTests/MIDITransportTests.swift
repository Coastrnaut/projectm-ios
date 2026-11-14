// MIDI-008-T05: the press filter (one press per physical press for notes, CC buttons and real-time), CC hysteresis,
// transport actions, the `ccbtn:`/`rt:` codec beside MIDI-003/004/006/007 lines, and trigger learn eligibility. Pure
// and deterministic: every message carries an explicit timestamp, no clock, no I/O.
import XCTest
import ParameterGraph
@testable import PerformanceControl

final class MIDITransportTests: XCTestCase {
    private static let ms: UInt64 = 1_000_000

    /// Parses MIDI 1.0 bytes, all stamped `at` (one packet list).
    private func parse(_ bytes: [UInt8], at timestamp: UInt64) -> [MIDIEvent] {
        var parser = MIDIByteStreamParser()
        var sink = MIDIEventCollector()
        bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Void in
            parser.feed(buffer, timestamp: timestamp, into: &sink)
        }
        return sink.events
    }

    private func list(_ lines: [String]) -> MIDINoteBindingList { MIDINoteBindingList(storageLines: lines) }

    /// Routes batches of (bytes, timestamp in ms) and returns the fired targets' IDs in order.
    private func fired(_ batches: [([UInt8], UInt64)], _ bindings: MIDINoteBindingList) -> [String] {
        var router = MIDINoteRouter()
        var result: [String] = []
        for (bytes, time) in batches {
            let commands: [MIDINoteCommand] = router.route(parse(bytes, at: 1_000 * Self.ms + time * Self.ms), bindings: bindings)
            result += commands.map { (c: MIDINoteCommand) -> String in c.target.id + (c.phase == .fire ? "" : "." + String(describing: c.phase)) }
        }
        return result
    }

    private static let noteLines: [String] = ["note:0:60=cue.next"]
    private static let buttonLines: [String] = ["ccbtn:0:20=cue.next"]
    private static let realTimeLines: [String] = ["rt:start=transport.toggle"]

    private static let notePress: [UInt8] = [0x90, 0x3C, 0x64, 0x80, 0x3C, 0x00]   // press and release
    private static let buttonPress: [UInt8] = [0xB0, 0x14, 0x7F, 0xB0, 0x14, 0x00]   // CC 20: 127 then 0
    private static let start: [UInt8] = [0xFA]

    // MARK: The row's acceptance (S1): each source kind × each repeat pattern fires once per press

    func testDoubledInOnePacketListFiresOnce() {
        XCTAssertEqual(fired([([0x90, 0x3C, 0x64, 0x90, 0x3C, 0x64], 0)], list(Self.noteLines)), ["cue.next"], "note on twice")
        XCTAssertEqual(fired([(Self.notePress + Self.notePress, 0)], list(Self.noteLines)), ["cue.next"], "press+release twice")
        XCTAssertEqual(fired([(Self.buttonPress + Self.buttonPress, 0)], list(Self.buttonLines)), ["cue.next"], "CC button")
        XCTAssertEqual(fired([([0xFA, 0xFA], 0)], list(Self.realTimeLines)), ["transport.toggle"], "Start twice")
    }

    func testDoubledAcrossTwoBatchesFiveMillisecondsApartFiresOnce() {
        XCTAssertEqual(fired([(Self.notePress, 0), (Self.notePress, 5)], list(Self.noteLines)), ["cue.next"], "note")
        XCTAssertEqual(fired([([0x90, 0x3C, 0x64], 0), ([0x90, 0x3C, 0x64], 5)], list(Self.noteLines)), ["cue.next"],
                       "note on twice, no release")
        XCTAssertEqual(fired([(Self.buttonPress, 0), (Self.buttonPress, 5)], list(Self.buttonLines)), ["cue.next"], "CC button")
        XCTAssertEqual(fired([(Self.start, 0), (Self.start, 5)], list(Self.realTimeLines)), ["transport.toggle"], "Start")
        XCTAssertEqual(fired([(Self.start, 0), ([0xFB], 5)], list(Self.realTimeLines)), ["transport.toggle"],
                       "Continue is the Start source")
    }

    func testCC127RepeatedWithoutAZeroFiresOnce() {
        let high: [UInt8] = [0xB0, 0x14, 0x7F]
        XCTAssertEqual(fired([(high + high + high, 0), (high, 200), (high, 900)], list(Self.buttonLines)), ["cue.next"])
    }

    func testADeliberateSecondPressFiresAgain() {
        XCTAssertEqual(fired([(Self.notePress, 0), (Self.notePress, 200)], list(Self.noteLines)), ["cue.next", "cue.next"])
        XCTAssertEqual(fired([(Self.buttonPress, 0), (Self.buttonPress, 200)], list(Self.buttonLines)), ["cue.next", "cue.next"])
        XCTAssertEqual(fired([(Self.start, 0), (Self.start, 200)], list(Self.realTimeLines)),
                       ["transport.toggle", "transport.toggle"])
        // A press 40 ms after the previous one, with a release between: deliberate (outside the 30 ms window).
        XCTAssertEqual(fired([(Self.notePress, 0), (Self.notePress, 40)], list(Self.noteLines)), ["cue.next", "cue.next"])
    }

    func testFilterRulesAndHysteresis() {
        var filter = MIDIPressFilter()
        let key = MIDIControlKey(kind: .controlChange, channel: 0, number: 20)
        func cc(_ value: UInt32) -> MIDITriggerEdge {
            MIDIPressFilter.rawEdge(MIDIEvent(kind: .controlChange, number: 20, value: value))!
        }
        filter.beginBatch()
        XCTAssertNil(filter.accept(cc(63), timestamp: 1 * Self.ms), "63 is below the threshold: a release of a key that is up")
        XCTAssertEqual(filter.accept(cc(64), timestamp: 2 * Self.ms), .press, "64 presses")
        filter.beginBatch()
        XCTAssertNil(filter.accept(cc(100), timestamp: 100 * Self.ms), "still down: no second press")
        XCTAssertNil(filter.accept(cc(127), timestamp: 200 * Self.ms))
        XCTAssertEqual(filter.accept(cc(63), timestamp: 300 * Self.ms), .release, "below 64 re-arms")
        XCTAssertEqual(filter.down, [])
        XCTAssertEqual(filter.accept(cc(64), timestamp: 400 * Self.ms), .press)
        XCTAssertEqual(filter.down, [key])
        // A dropped press changes no state: its release is ignored.
        var other = MIDIPressFilter()
        let note = MIDITriggerEdge(key: MIDIControlKey(kind: .noteOn, channel: 0, number: 60), edge: .on)
        let up = MIDITriggerEdge(key: note.key, edge: .off)
        other.beginBatch()
        XCTAssertEqual(other.accept(note, timestamp: 10 * Self.ms), .press)
        XCTAssertEqual(other.accept(up, timestamp: 11 * Self.ms), .release)
        other.beginBatch()
        XCTAssertNil(other.accept(note, timestamp: 15 * Self.ms), "within 30 ms")
        XCTAssertNil(other.accept(up, timestamp: 16 * Self.ms), "its release")
        // Unknown timestamps (0): only the down state and the batch rule apply.
        var unknown = MIDIPressFilter()
        unknown.beginBatch()
        XCTAssertEqual(unknown.accept(note, timestamp: 0), .press)
        XCTAssertEqual(unknown.accept(up, timestamp: 0), .release)
        XCTAssertNil(unknown.accept(note, timestamp: 0), "same batch")
        unknown.beginBatch()
        XCTAssertEqual(unknown.accept(note, timestamp: 0), .press)
        // Channel mode CCs and other kinds are no trigger sources.
        XCTAssertNil(MIDIPressFilter.rawEdge(MIDIEvent(kind: .controlChange, number: 123, value: 127)))
        XCTAssertNil(MIDIPressFilter.rawEdge(MIDIEvent(kind: .programChange, number: 5)))
        XCTAssertEqual(MIDIEvent(kind: .continue).triggerKey, MIDIPressFilter.startKey)
        XCTAssertEqual(MIDIEvent(kind: .stop).triggerKey, MIDIPressFilter.stopKey)
    }

    func testUnboundCCNeverReachesTheFilterAndHoldWorksWithACCButton() {
        var router = MIDINoteRouter()
        let bindings: MIDINoteBindingList = list(["ccbtn:0:21=blackout;mode=hold"])
        XCTAssertEqual(router.route(parse([0xB0, 0x07, 0x7F], at: 1 * Self.ms), bindings: bindings), [])
        XCTAssertFalse(router.hasKeysDown, "an unbound CC is not tracked")
        let engage: [MIDINoteCommand] = router.route(parse([0xB0, 0x15, 0x7F, 0xB0, 0x15, 0x7F], at: 100 * Self.ms), bindings: bindings)
        XCTAssertEqual(engage.map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.engage])
        let release: [MIDINoteCommand] = router.route(parse([0xB0, 0x15, 0x00], at: 900 * Self.ms), bindings: bindings)
        XCTAssertEqual(release.map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.release])
        // A held CC button is released by releaseAll (input stopped), as notes.
        _ = router.route(parse([0xB0, 0x15, 0x7F], at: 2_000 * Self.ms), bindings: bindings)
        XCTAssertEqual(router.releaseAll(bindings: bindings).map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.release])
    }

    func testRegisteredLearningPressSilencesItsCopies() {
        var router = MIDINoteRouter()
        let bindings: MIDINoteBindingList = list(Self.buttonLines)
        let key = MIDIControlKey(kind: .controlChange, channel: 0, number: 20)
        router.registerPress(key, timestamp: 1_000 * Self.ms)
        XCTAssertEqual(router.route(parse([0xB0, 0x14, 0x7F], at: 1_005 * Self.ms), bindings: bindings), [], "the copy")
        XCTAssertEqual(router.route(parse([0xB0, 0x14, 0x00], at: 1_100 * Self.ms), bindings: bindings), [], "the release")
        XCTAssertEqual(router.route(parse([0xB0, 0x14, 0x7F], at: 1_300 * Self.ms), bindings: bindings).count, 1, "next press")
    }

    // MARK: Codec (S4)

    func testTriggerLinesRoundTripBesideEveryOtherLine() {
        let stored: [String] = [
            "cc:0:7=effect.bloom.intensity;curve=easeIn(2);invert=1",   // MIDI-003/004
            "note:0:60=cue.next", "note:0:61=blackout;mode=hold",   // MIDI-006
            "ccbtn:1:20=transport.toggle", "ccbtn:0:21=blackout;x=1", "rt:start=transport.play", "rt:stop=transport.pause",
            "pc:0:5=cue.go:SCENE-A", "note:0:62=cue.go:SCENE-B", "pc:*:*=cue.position",   // MIDI-007
            "ccbtn:0:120=cue.next", "rt:stop=blackout;mode=hold", "rt:clock=transport.play", "ccbtn:0:22=transport.rewind",
        ]
        let triggers: MIDINoteBindingList = list(stored)
        XCTAssertEqual(triggers.bindings.map { (b: MIDINoteBinding) -> String in b.storageLine },
                       ["note:0:60=cue.next", "note:0:61=blackout;mode=hold", "ccbtn:1:20=transport.toggle",
                        "ccbtn:0:21=blackout;x=1", "rt:start=transport.play", "rt:stop=transport.pause"])
        XCTAssertEqual(triggers.keptLines, ["ccbtn:0:120=cue.next", "rt:stop=blackout;mode=hold", "rt:clock=transport.play",
                                            "ccbtn:0:22=transport.rewind"], "unreadable trigger lines kept verbatim")
        XCTAssertEqual(MIDINoteBindingList(storageLines: triggers.storageLines), triggers, "round trip")
        let allowed: Set<ParameterID> = [ParameterID("effect.bloom.intensity")]
        XCTAssertEqual(MIDIBindingList(storageLines: stored, allowedTargets: allowed).storageLines, [stored[0]], "MIDI-003 reads only cc:")
        XCTAssertEqual(MIDISceneBindingList(storageLines: stored).storageLines, ["pc:0:5=cue.go:SCENE-A", "note:0:62=cue.go:SCENE-B",
                                                                                 "pc:*:*=cue.position"], "MIDI-007 unchanged")
        XCTAssertEqual(triggers.binding(forKey: MIDIPressFilter.startKey)?.target, .play)
    }

    func testBindRejectsRealTimeOnTheHoldRowAndTitles() {
        var triggers = MIDINoteBindingList()
        XCTAssertEqual(triggers.bind(MIDIPressFilter.stopKey, to: .blackoutHold), .added)
        XCTAssertTrue(triggers.isEmpty, "real-time has no release: never a hold source")
        XCTAssertEqual(triggers.bind(MIDIPressFilter.stopKey, to: .pause), .added)
        let button = MIDIControlKey(kind: .controlChange, channel: 0, number: 20)
        XCTAssertEqual(triggers.bind(button, to: .pause), .replaced(previous: MIDIPressFilter.stopKey))
        XCTAssertEqual(triggers.storageLines, ["ccbtn:0:20=transport.pause"])
        XCTAssertEqual([MIDINoteTarget.playPause, .play, .pause].map { (t: MIDINoteTarget) -> String in t.title }, ["Play/Pause", "Play", "Pause"])
        XCTAssertFalse(MIDINoteAction.transportToggle.allowsHold)
    }

    func testTriggerLearnEligibility() {
        let batch: [MIDIEvent] = parse([0xB0, 0x14, 0x20, 0x90, 0x3C, 0x00, 0xFC, 0xB0, 0x14, 0x7F], at: 1)
        var hold = MIDILearnSession<String>()
        hold.start(target: "hold", now: 0)
        let holdRule: (MIDIEvent) -> Bool = { (e: MIDIEvent) -> Bool in MIDILearnEligibility.isTriggerEligible(e, allowsRealTime: false) }
        XCTAssertEqual(hold.handle(batch, now: 1, isEligible: holdRule),
                       .bound(key: MIDIControlKey(kind: .controlChange, channel: 0, number: 20), target: "hold", eventIndex: 3),
                       "CC 32 and a release are no press; Stop is skipped on the hold row")
        var any = MIDILearnSession<String>()
        any.start(target: "next", now: 0)
        let anyRule: (MIDIEvent) -> Bool = { (e: MIDIEvent) -> Bool in MIDILearnEligibility.isTriggerEligible(e, allowsRealTime: true) }
        XCTAssertEqual(any.handle(batch, now: 1, isEligible: anyRule),
                       .bound(key: MIDIControlKey(kind: .stop, channel: 0, number: 0), target: "next", eventIndex: 2))
    }
}
