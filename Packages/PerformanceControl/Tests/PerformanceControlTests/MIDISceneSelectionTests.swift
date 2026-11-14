// MIDI-007-T06: the scene line codec beside MIDI-003/004/006 lines, the position mode, the scene mapping list (moves,
// capacity, kept lines), the router (channel filtering, newest wins, explicit before the mode, note edges) and scene
// learn eligibility. Pure and deterministic: no clock, no I/O.
import XCTest
import ParameterGraph
@testable import PerformanceControl

final class MIDISceneSelectionTests: XCTestCase {
    private static let sceneX: String = "5CE7E000-0000-4000-8000-000000000003"
    private static let sceneY: String = "5CE7E000-0000-4000-8000-000000000004"

    private func pc(_ channel: UInt8, _ program: UInt8) -> MIDIEvent {
        MIDIEvent(kind: .programChange, channel: channel, number: program)
    }

    private func pcKey(_ channel: UInt8, _ program: UInt8) -> MIDIControlKey {
        MIDIControlKey(kind: .programChange, channel: channel, number: program)
    }

    private func noteKey(_ channel: UInt8, _ note: UInt8) -> MIDIControlKey {
        MIDIControlKey(kind: .noteOn, channel: channel, number: note)
    }

    // MARK: Stored form (S4)

    func testSceneLinesRoundTripBesideCCAndNoteTriggerLines() {
        let lines: [String] = [
            "cc:0:7=effect.bloom.intensity;curve=easeIn:2.0;invert=1",   // MIDI-003/004
            "note:0:60=cue.next", "note:0:61=blackout;mode=hold",          // MIDI-006
            "note:0:1=cue.fire:XYZ",                                        // MIDI-006 unknown action
            "pc:0:5=cue.go:" + Self.sceneX,
            "note:0:62=cue.go:" + Self.sceneY + ";bank=3",
            "pc:*:*=cue.position",
            "pc:0:6=cue.go:bad id",                                         // unreadable: kept
            "pc:16:1=cue.go:" + Self.sceneX,                                // bad channel: kept
            "pc:0:7=scene.future:abc",                                      // unknown pc action: kept
            "pc:0:5=cue.go:" + Self.sceneY,                                 // repeated key: dropped
            "pc:3:*=cue.position",                                          // second mode line: dropped
        ]
        let scenes = MIDISceneBindingList(storageLines: lines)
        XCTAssertEqual(scenes.bindings, [MIDISceneBinding(key: pcKey(0, 5), sceneID: Self.sceneX),
                                         MIDISceneBinding(key: noteKey(0, 62), sceneID: Self.sceneY, extraSegments: ["bank=3"])])
        XCTAssertEqual(scenes.programCueMode, .anyChannel)
        XCTAssertEqual(scenes.storageLines, ["pc:0:5=cue.go:" + Self.sceneX, "note:0:62=cue.go:" + Self.sceneY + ";bank=3",
                                             "pc:*:*=cue.position", "pc:0:6=cue.go:bad id", "pc:16:1=cue.go:" + Self.sceneX,
                                             "pc:0:7=scene.future:abc"])
        // MIDI-006 reads its own lines exactly as before and no longer keeps the scene lines.
        let notes = MIDINoteBindingList(storageLines: lines)
        XCTAssertEqual(notes.storageLines, ["note:0:60=cue.next", "note:0:61=blackout;mode=hold", "note:0:1=cue.fire:XYZ"])
        // MIDI-003/004 reading is unchanged.
        let cc = MIDIBindingList(storageLines: lines, allowedTargets: [ParameterID("effect.bloom.intensity")])
        XCTAssertEqual(cc.storageLines, [lines[0]])
        // Together the three lists write every line once (the app's save order: cc, notes, scenes).
        let saved: [String] = cc.storageLines + notes.storageLines + scenes.storageLines
        XCTAssertEqual(Set(saved), Set(lines).subtracting(["pc:0:5=cue.go:" + Self.sceneY, "pc:3:*=cue.position"]))
        XCTAssertEqual(MIDISceneBindingList(storageLines: saved), scenes, "round trip")
    }

    func testModeLinesAndSceneIDs() {
        XCTAssertEqual(MIDIProgramCueMode(storageLine: "pc:*:*=cue.position"), .anyChannel)
        XCTAssertEqual(MIDIProgramCueMode(storageLine: "pc:15:*=cue.position"), .channel(15))
        XCTAssertNil(MIDIProgramCueMode(storageLine: "pc:16:*=cue.position"))
        XCTAssertNil(MIDIProgramCueMode(storageLine: "pc:0:5=cue.position"))
        XCTAssertEqual(MIDIProgramCueMode.channel(2).storageLine, "pc:2:*=cue.position")
        XCTAssertNil(MIDIProgramCueMode.off.storageLine)
        XCTAssertTrue(MIDISceneBinding.isValidSceneID(Self.sceneX))
        XCTAssertFalse(MIDISceneBinding.isValidSceneID(""))
        XCTAssertFalse(MIDISceneBinding.isValidSceneID("a;b"))
        XCTAssertFalse(MIDISceneBinding.isValidSceneID(String(repeating: "a", count: 65)))
        XCTAssertTrue(MIDISceneBinding.isSceneLine("note:0:1=cue.go:"), "owned even when unreadable")
        XCTAssertFalse(MIDISceneBinding.isSceneLine("note:0:1=cue.next"))
        XCTAssertNil(MIDISceneBinding(storageLine: "note:0:1=cue.go:"))
        XCTAssertEqual(MIDIProgramCueMode(storageLine: "pc:0:*=cue.position")?.matches(channel: 0), true)
        XCTAssertEqual(MIDIProgramCueMode.channel(0).matches(channel: 1), false)
    }

    func testBindMovesReplacesAndCapacity() {
        var list = MIDISceneBindingList()
        XCTAssertEqual(list.bind(pcKey(0, 5), to: "A"), .added)
        XCTAssertEqual(list.bind(pcKey(0, 5), to: "A"), .added, "rebinding the same pair changes nothing")
        XCTAssertEqual(list.bind(noteKey(0, 60), to: "A"), .replaced(previous: pcKey(0, 5)), "a scene keeps one key")
        XCTAssertEqual(list.bind(noteKey(0, 60), to: "B"), .moved(fromScene: "A"))
        XCTAssertEqual(list.bind(pcKey(0, 1), to: "C"), .added)
        XCTAssertEqual(list.bind(pcKey(0, 1), to: "B"), .movedAndReplaced(fromScene: "C", previous: noteKey(0, 60)))
        XCTAssertEqual(list.bindings.map { (b: MIDISceneBinding) -> String in b.sceneID }, ["B"])
        XCTAssertNotNil(list.remove(key: pcKey(0, 1)))
        XCTAssertNil(list.remove(sceneID: "B"))
        for program in 0..<128 { list.bind(pcKey(1, UInt8(program)), to: "S" + String(program)) }
        XCTAssertEqual(list.bindings.count, MIDISceneBindingList.capacity)
        XCTAssertEqual(list.bind(pcKey(2, 0), to: "Z"), .full)
        XCTAssertEqual(list.bind(pcKey(2, 0), to: "S0"), .replaced(previous: pcKey(1, 0)), "a move frees its own slot")
    }

    // MARK: Router (S2, S3)

    func testRouterFiltersChannelsAndTheNewestWins() {
        let list = MIDISceneBindingList(storageLines: ["pc:0:5=cue.go:X", "pc:0:6=cue.go:Y", "note:0:60=cue.go:Z"])
        XCTAssertEqual(MIDISceneRouter.route([pc(0, 5)], list: list), .scene(id: "X", key: pcKey(0, 5)))
        XCTAssertNil(MIDISceneRouter.route([pc(1, 5)], list: list), "another channel selects nothing")
        XCTAssertNil(MIDISceneRouter.route([pc(0, 9)], list: list), "an unmapped program with the mode off")
        XCTAssertEqual(MIDISceneRouter.route([pc(0, 5), pc(0, 6), pc(3, 5)], list: list), .scene(id: "Y", key: pcKey(0, 6)))
        let press = MIDIEvent(kind: .noteOn, channel: 0, number: 60, value: 100)
        let release = MIDIEvent(kind: .noteOff, channel: 0, number: 60)
        let zero = MIDIEvent(kind: .noteOn, channel: 0, number: 60, value: 0)
        XCTAssertEqual(MIDISceneRouter.route([press], list: list), .scene(id: "Z", key: noteKey(0, 60)))
        XCTAssertNil(MIDISceneRouter.route([release, zero], list: list), "releases select nothing (velocity 0 included)")
        XCTAssertNil(MIDISceneRouter.route([MIDIEvent(kind: .controlChange, channel: 0, number: 5, value: 5)], list: list))
        XCTAssertNil(MIDISceneRouter.route([pc(0, 5)], list: MIDISceneBindingList()), "no mappings, no mode")
    }

    func testPositionModeAndExplicitMappingsWin() {
        var list = MIDISceneBindingList(storageLines: ["pc:0:2=cue.go:X"])
        list.programCueMode = .channel(0)
        XCTAssertEqual(MIDISceneRouter.route([pc(0, 4)], list: list), .cue(index: 4, key: pcKey(0, 4)))
        XCTAssertNil(MIDISceneRouter.route([pc(1, 4)], list: list), "the mode's channel only")
        XCTAssertEqual(MIDISceneRouter.route([pc(0, 2)], list: list), .scene(id: "X", key: pcKey(0, 2)), "explicit wins")
        list.programCueMode = .anyChannel
        XCTAssertEqual(MIDISceneRouter.route([pc(9, 0)], list: list), .cue(index: 0, key: pcKey(9, 0)))
        XCTAssertEqual(list.storageLines, ["pc:0:2=cue.go:X", "pc:*:*=cue.position"])
        XCTAssertFalse(MIDISceneBindingList(storageLines: ["pc:*:*=cue.position"]).isEmpty, "the mode alone needs the input")
        XCTAssertTrue(MIDISceneBindingList(storageLines: ["pc:0:7=scene.future:abc"]).isEmpty, "kept lines drive nothing")
    }

    func testSceneLearnEligibility() {
        XCTAssertTrue(MIDILearnEligibility.isSceneEligible(pc(0, 5)))
        XCTAssertTrue(MIDILearnEligibility.isSceneEligible(MIDIEvent(kind: .noteOn, channel: 0, number: 60, value: 1)))
        XCTAssertFalse(MIDILearnEligibility.isSceneEligible(MIDIEvent(kind: .noteOn, channel: 0, number: 60, value: 0)))
        XCTAssertFalse(MIDILearnEligibility.isSceneEligible(MIDIEvent(kind: .noteOff, channel: 0, number: 60)))
        XCTAssertFalse(MIDILearnEligibility.isSceneEligible(MIDIEvent(kind: .controlChange, channel: 0, number: 0, value: 1)),
                       "bank select is not learned (research MIDI-007-D7)")
        var session = MIDILearnSession<String>()
        session.start(target: "X", now: 0)
        let batch: [MIDIEvent] = [MIDIEvent(kind: .controlChange, number: 32), pc(2, 9)]
        XCTAssertEqual(session.handle(batch, now: 1, isEligible: MIDILearnEligibility.isSceneEligible),
                       .bound(key: pcKey(2, 9), target: "X", eventIndex: 1))
    }

    func testParsedProgramChangeRoutes() {
        var parser = MIDIByteStreamParser()
        var sink = MIDIEventCollector()
        let bytes: [UInt8] = [0xC0, 0x05, 0xF8, 0x06]   // running status with a clock byte inside
        bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Void in parser.feed(buffer, timestamp: 1, into: &sink) }
        let list = MIDISceneBindingList(storageLines: ["pc:0:5=cue.go:X", "pc:0:6=cue.go:Y"])
        XCTAssertEqual(sink.events.filter { (e: MIDIEvent) -> Bool in e.kind == .programChange }.count, 2)
        XCTAssertEqual(MIDISceneRouter.route(sink.events, list: list), .scene(id: "Y", key: pcKey(0, 6)))
    }
}
