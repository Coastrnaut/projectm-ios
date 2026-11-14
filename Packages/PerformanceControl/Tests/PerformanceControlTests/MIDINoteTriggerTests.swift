// MIDI-006-T05, T09, T12: note edges, the parsers' velocity-0 equivalence, the `note:` codec beside MIDI-003/004
// lines, the router (trigger, hold, repeats, channels, panic, release) and note learn eligibility. Pure and
// deterministic: no clock, no I/O.
import XCTest
import ParameterGraph
@testable import PerformanceControl

final class MIDINoteTriggerTests: XCTestCase {
    private static let next: MIDINoteTarget = .nextCue
    private static let hold: MIDINoteTarget = .blackoutHold

    /// One key with its edge: what the router consumes.
    private struct Edge: Hashable {
        let channel: UInt8
        let note: UInt8
        let edge: MIDINoteEdge
    }

    /// MIDI-008: each parsed batch is 100 ms after the previous one (MIDIPressFilter's 30 ms window reads timestamps).
    private var timestamp: UInt64 = 7
    private var advancesTime: Bool = true

    private func parse(_ bytes: [UInt8]) -> [MIDIEvent] {
        var parser = MIDIByteStreamParser()
        var sink = MIDIEventCollector()
        if advancesTime { timestamp += 100_000_000 }
        let stamp: UInt64 = timestamp
        bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Void in
            parser.feed(buffer, timestamp: stamp, into: &sink)
        }
        return sink.events
    }

    private func decode(_ words: [UInt32]) -> [MIDIEvent] {
        var decoder = MIDIUMPDecoder()
        var sink = MIDIEventCollector()
        words.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt32>) -> Void in
            decoder.decode(buffer, timestamp: timestamp, into: &sink)
        }
        return sink.events
    }

    private func edges(_ events: [MIDIEvent]) -> [Edge] {
        events.compactMap { (event: MIDIEvent) -> Edge? in
            event.noteEdge.map { (edge: MIDINoteEdge) -> Edge in Edge(channel: event.channel, note: event.number, edge: edge) }
        }
    }

    private func list(_ lines: [String]) -> MIDINoteBindingList { MIDINoteBindingList(storageLines: lines) }

    private func route(_ events: [MIDIEvent], _ bindings: MIDINoteBindingList) -> [MIDINotePhase] {
        var router = MIDINoteRouter()
        return router.route(events, bindings: bindings).map { (command: MIDINoteCommand) -> MIDINotePhase in command.phase }
    }

    // MARK: Normalisation (N1)

    func testNoteEdgeTreatsVelocityZeroNoteOnAsRelease() {
        XCTAssertEqual(MIDIEvent(kind: .noteOn, channel: 0, number: 60, value: 100).noteEdge, .on)
        XCTAssertEqual(MIDIEvent(kind: .noteOn, channel: 0, number: 60, value: 0).noteEdge, .off)   // hand-built
        XCTAssertEqual(MIDIEvent(kind: .noteOff, channel: 0, number: 60, value: 64).noteEdge, .off)
        XCTAssertNil(MIDIEvent(kind: .controlChange, channel: 0, number: 60, value: 0).noteEdge)
        XCTAssertNil(MIDIEvent(kind: .polyPressure, channel: 0, number: 60, value: 0).noteEdge)
    }

    // MARK: The row's acceptance (S1)

    /// The three sequences, as bytes: (on v>0, on v=0), (on v>0, off v=0), (on v>0, running-status v=0 with a clock
    /// byte in the middle). Identical event streams (velocity 0 note on becomes note off, value 0) and identical edges.
    func testVelocityZeroNoteOnNoteOffAndRunningStatusGiveIdenticalStreams() {
        advancesTime = false   // compares whole events, timestamps included
        let onOn: [MIDIEvent] = parse([0x91, 0x3C, 0x64, 0x91, 0x3C, 0x00])
        let onOff: [MIDIEvent] = parse([0x91, 0x3C, 0x64, 0x81, 0x3C, 0x00])
        let running: [MIDIEvent] = parse([0x91, 0x3C, 0x64, 0x3C, 0xF8, 0x00]).filter { (e: MIDIEvent) -> Bool in e.kind != .clock }
        XCTAssertEqual(onOn, onOff)
        XCTAssertEqual(onOn, running)
        XCTAssertEqual(onOn.map { (e: MIDIEvent) -> MIDIEventKind in e.kind }, [.noteOn, .noteOff])
        // A note off with a release velocity carries the value but the same edges.
        let releaseVelocity: [MIDIEvent] = parse([0x91, 0x3C, 0x64, 0x81, 0x3C, 0x40])
        XCTAssertEqual(edges(releaseVelocity), edges(onOn))
        XCTAssertEqual(edges(onOn), [Edge(channel: 1, note: 60, edge: .on), Edge(channel: 1, note: 60, edge: .off)])
        // UMP (MIDI 1.0 channel voice words): the same.
        let ump: [MIDIEvent] = decode([0x2091_3C64, 0x2091_3C00])
        XCTAssertEqual(ump, onOn)
    }

    func testTriggerAndHoldGiveTheSameCommandsForAllThreeSequences() {
        let sequences: [[UInt8]] = [[0x91, 0x3C, 0x64, 0x91, 0x3C, 0x00],
                                    [0x91, 0x3C, 0x64, 0x81, 0x3C, 0x40],
                                    [0x91, 0x3C, 0x64, 0x3C, 0x00]]
        let trigger: MIDINoteBindingList = list(["note:1:60=cue.next"])
        let held: MIDINoteBindingList = list(["note:1:60=blackout;mode=hold"])
        for bytes in sequences {
            XCTAssertEqual(route(parse(bytes), trigger), [.fire], "trigger: \(bytes)")
            XCTAssertEqual(route(parse(bytes), held), [.engage, .release], "hold: \(bytes)")
        }
        // A hand-built velocity-0 note on is a release too (the router reads only noteEdge).
        let handBuilt: [MIDIEvent] = [MIDIEvent(kind: .noteOn, channel: 1, number: 60, value: 9),
                                      MIDIEvent(kind: .noteOn, channel: 1, number: 60, value: 0)]
        XCTAssertEqual(route(handBuilt, held), [.engage, .release])
    }

    func testChannelFilteringAndUnboundNotes() {
        let bindings: MIDINoteBindingList = list(["note:0:60=cue.next"])
        XCTAssertEqual(route(parse([0x91, 0x3C, 0x64, 0x81, 0x3C, 0x00]), bindings), [], "channel 2 is not channel 1")
        XCTAssertEqual(route(parse([0x90, 0x3D, 0x64]), bindings), [], "another note")
        XCTAssertEqual(route(parse([0xB0, 0x3C, 0x64]), bindings), [], "a CC with the same number")
        XCTAssertEqual(route(parse([0x90, 0x3C, 0x64]), bindings), [.fire])
    }

    // MARK: Repeats, batches, stuck notes (S2)

    func testRepeatedNoteOnNeitherRefiresNorRetoggles() {
        let bindings: MIDINoteBindingList = list(["note:0:60=cue.next", "note:0:61=blackout;mode=hold"])
        var router = MIDINoteRouter()
        let first: [MIDINoteCommand] = router.route(parse([0x90, 0x3C, 0x64, 0x3C, 0x50, 0x3D, 0x64, 0x3D, 0x70]), bindings: bindings)
        XCTAssertEqual(first.map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.fire, .engage])
        let again: [MIDINoteCommand] = router.route(parse([0x90, 0x3C, 0x64, 0x90, 0x3D, 0x64]), bindings: bindings)
        XCTAssertEqual(again, [], "still down: nothing")
        let up: [MIDINoteCommand] = router.route(parse([0x80, 0x3C, 0x00, 0x80, 0x3D, 0x00, 0x80, 0x3D, 0x00]), bindings: bindings)
        XCTAssertEqual(up.map { (c: MIDINoteCommand) -> MIDINoteTarget in c.target }, [.blackoutHold])
        XCTAssertFalse(router.hasKeysDown)
    }

    func testOneFirePerBindingPerBatchAndReleaseOfAnUpKeyIsIgnored() {
        let bindings: MIDINoteBindingList = list(["note:0:60=cue.next"])
        let flood: [UInt8] = [0x90, 0x3C, 0x64, 0x3C, 0x00, 0x3C, 0x64, 0x3C, 0x00, 0x3C, 0x64]
        XCTAssertEqual(route(parse(flood), bindings), [.fire])
        XCTAssertEqual(route(parse([0x80, 0x3C, 0x00]), bindings), [], "the release of the learning press")
    }

    func testPanicAndResetReleaseStuckKeys() {
        let bindings: MIDINoteBindingList = list(["note:0:61=blackout;mode=hold", "note:2:62=cue.next"])
        var router = MIDINoteRouter()
        _ = router.route(parse([0x90, 0x3D, 0x64, 0x92, 0x3E, 0x64]), bindings: bindings)
        XCTAssertEqual(router.route(parse([0xB1, 0x7B, 0x00]), bindings: bindings), [], "All Notes Off on another channel")
        let panic: [MIDINoteCommand] = router.route(parse([0xB0, 0x7B, 0x00]), bindings: bindings)
        XCTAssertEqual(panic.map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.release])
        XCTAssertEqual(router.down, [MIDIControlKey(kind: .noteOn, channel: 2, number: 62)])
        XCTAssertEqual(router.route([MIDIEvent(kind: .reset)], bindings: bindings), [], "a trigger key releases silently")
        XCTAssertFalse(router.hasKeysDown)
        _ = router.route(parse([0x90, 0x3D, 0x64]), bindings: bindings)
        XCTAssertEqual(router.route(parse([0xB0, 0x78, 0x00]), bindings: bindings).count, 1, "All Sound Off")
    }

    func testReleaseAllAndReleaseKeys() {
        let bindings: MIDINoteBindingList = list(["note:0:61=blackout;mode=hold", "note:0:60=cue.next"])
        var router = MIDINoteRouter()
        _ = router.route(parse([0x90, 0x3D, 0x64, 0x3C, 0x64]), bindings: bindings)
        let held: MIDIControlKey = MIDIControlKey(kind: .noteOn, channel: 0, number: 61)
        XCTAssertEqual(router.release(keys: [held], bindings: bindings),
                       [MIDINoteCommand(target: .blackoutHold, phase: .release, key: held)])
        XCTAssertEqual(router.releaseAll(bindings: bindings), [])
        XCTAssertFalse(router.hasKeysDown)
        XCTAssertEqual(router.releaseAll(bindings: bindings), [], "idempotent")
    }

    // MARK: Stored form (S3)

    func testNoteLinesRoundTripBesideCCLines() {
        let lines: [String] = ["cc:0:7=effect.bloom.intensity;curve=easeIn:2.0;invert=1", "note:0:60=cue.next",
                               "note:15:127=blackout;mode=hold;velocity=40", "note:0:61=cue.fire:ABC", "note:0:62=blackout;mode=trigger",
                               "note:0:63=cue.next;mode=hold", "note:16:1=cue.next", "note:0:60=cue.previous"]
        let notes: MIDINoteBindingList = list(lines)
        XCTAssertEqual(notes.bindings.map { (b: MIDINoteBinding) -> MIDINoteTarget in b.target }, [.nextCue, .blackoutHold, .blackoutToggle])
        XCTAssertEqual(notes.storageLines, ["note:0:60=cue.next", "note:15:127=blackout;mode=hold;velocity=40", "note:0:62=blackout",
                                            "note:0:61=cue.fire:ABC", "note:0:63=cue.next;mode=hold", "note:16:1=cue.next"],
                       "unknown action, disallowed hold and bad channel kept verbatim; a repeated note dropped")
        let cc: MIDIBindingList = MIDIBindingList(storageLines: lines, allowedTargets: [ParameterID("effect.bloom.intensity")])
        XCTAssertEqual(cc.storageLines, [lines[0]], "MIDI-003/004 reading is unchanged and ignores note lines")
        XCTAssertNil(MIDINoteBinding(storageLine: "cc:0:7=effect.bloom.intensity"))
        XCTAssertNil(MIDIControlBinding(storageLine: "note:0:60=cue.next"))
    }

    func testBindMovesAndReplaces() {
        var notes = MIDINoteBindingList()
        let c4: MIDIControlKey = MIDIControlKey(kind: .noteOn, channel: 0, number: 60)
        let d4: MIDIControlKey = MIDIControlKey(kind: .noteOn, channel: 0, number: 62)
        XCTAssertEqual(notes.bind(c4, to: .nextCue), .added)
        XCTAssertEqual(notes.bind(c4, to: .nextCue), .added)
        XCTAssertEqual(notes.bind(c4, to: .previousCue), .moved(from: .nextCue))
        XCTAssertEqual(notes.bind(d4, to: .previousCue), .replaced(previous: c4))
        XCTAssertEqual(notes.storageLines, ["note:0:62=cue.previous"])
        XCTAssertNotNil(notes.remove(target: .previousCue))
        XCTAssertTrue(notes.isEmpty)
        XCTAssertNil(MIDINoteTarget(action: .cueNext, mode: .hold))
        XCTAssertEqual(MIDINoteTarget.all.map { (t: MIDINoteTarget) -> String in t.id }, ["transport.toggle", "transport.play", "transport.pause",   // MIDI-008
                                                                                     "cue.next", "cue.previous", "blackout", "blackout.hold"])
    }

    // MARK: Learn (T12)

    func testNoteLearnTakesAPressAndCCLearnIgnoresNotes() {
        let batch: [MIDIEvent] = parse([0x90, 0x3C, 0x00, 0xB0, 0x07, 0x64, 0x90, 0x3E, 0x64])
        var notes = MIDILearnSession<String>()
        notes.start(target: "next", now: 0)
        XCTAssertEqual(notes.handle(batch, now: 1, isEligible: MIDILearnEligibility.isNoteEligible),
                       .bound(key: MIDIControlKey(kind: .noteOn, channel: 0, number: 62), target: "next", eventIndex: 2))
        var cc = MIDILearnSession<String>()
        cc.start(target: "glow", now: 0)
        XCTAssertEqual(cc.handle(batch, now: 1), .bound(key: MIDIControlKey(kind: .controlChange, channel: 0, number: 7),
                                                         target: "glow", eventIndex: 1))
    }
}
