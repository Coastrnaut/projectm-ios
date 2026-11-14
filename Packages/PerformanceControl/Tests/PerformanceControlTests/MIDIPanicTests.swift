// MIDI-013-T05, T09, T11 (specs/183-midi-013-panic, contract P1): the router's panic releases every held key through the
// source-loss path and the press rule forgets everything; `midi.panic` is a trigger-only action in MIDI-006's line
// format. Pure and deterministic: explicit timestamps, no clock, no I/O.
import XCTest
@testable import PerformanceControl

final class MIDIPanicTests: XCTestCase {
    private static let ms: UInt64 = 1_000_000

    private func parse(_ bytes: [UInt8], at timestamp: UInt64) -> [MIDIEvent] {
        var parser = MIDIByteStreamParser()
        var sink = MIDIEventCollector()
        bytes.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) -> Void in
            parser.feed(buffer, timestamp: timestamp, into: &sink)
        }
        return sink.events
    }

    private static let lines: [String] = ["note:0:60=cue.next", "note:0:62=blackout;mode=hold", "note:1:64=cue.previous",
                                          "ccbtn:0:20=blackout"]

    /// Three notes (one hold) and a CC button down.
    private func heldRouter(_ bindings: MIDINoteBindingList) -> MIDINoteRouter {
        var router = MIDINoteRouter()
        let press: [UInt8] = [0x90, 0x3C, 0x64, 0x90, 0x3E, 0x64, 0x91, 0x40, 0x64, 0xB0, 0x14, 0x7F]
        let commands: [MIDINoteCommand] = router.route(parse(press, at: 1_000 * Self.ms), bindings: bindings)
        XCTAssertEqual(commands.map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.fire, .engage, .fire, .fire])
        XCTAssertEqual(router.down.count, 4)
        return router
    }

    func testPanicReleasesEveryHeldKeyAndEmptiesThePressRule() {
        let bindings = MIDINoteBindingList(storageLines: Self.lines)
        var router: MIDINoteRouter = heldRouter(bindings)
        let commands: [MIDINoteCommand] = router.panic(bindings: bindings)
        XCTAssertEqual(commands, [MIDINoteCommand(target: .blackoutHold, phase: .release,
                                                  key: MIDIControlKey(kind: .noteOn, channel: 0, number: 62))],
                       "one release, for the hold binding only")
        XCTAssertTrue(router.down.isEmpty, "no active gates")
        XCTAssertTrue(router.filter.isEmpty)
        XCTAssertTrue(router.isIdle)
        XCTAssertEqual(bindings.storageLines, MIDINoteBindingList(storageLines: Self.lines).storageLines, "bindings unchanged")
    }

    func testPressesAfterPanicAreFreshAndLateReleasesAreIgnored() {
        let bindings = MIDINoteBindingList(storageLines: Self.lines)
        var router: MIDINoteRouter = heldRouter(bindings)
        _ = router.panic(bindings: bindings)
        let late: [MIDINoteCommand] = router.route(parse([0x80, 0x3E, 0x00, 0xB0, 0x14, 0x00], at: 1_005 * Self.ms), bindings: bindings)
        XCTAssertTrue(late.isEmpty, "the late note-off and CC release find the keys up")
        // 10 ms after the first press: inside the old 30 ms repeat window, still a fresh press after panic.
        let again: [MIDINoteCommand] = router.route(parse([0x90, 0x3C, 0x64, 0x90, 0x3E, 0x64], at: 1_010 * Self.ms), bindings: bindings)
        XCTAssertEqual(again.map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.fire, .engage])
        let release: [MIDINoteCommand] = router.route(parse([0x80, 0x3E, 0x00], at: 1_100 * Self.ms), bindings: bindings)
        XCTAssertEqual(release.map { (c: MIDINoteCommand) -> MIDINotePhase in c.phase }, [.release])
    }

    func testPanicWhileIdleReturnsNothing() {
        var router = MIDINoteRouter()
        XCTAssertTrue(router.isIdle)
        XCTAssertTrue(router.panic(bindings: MIDINoteBindingList(storageLines: Self.lines)).isEmpty)
        XCTAssertTrue(router.isIdle)
    }

    func testFilterResetForgetsDownKeysTimesAndBatchPresses() {
        var filter = MIDIPressFilter()
        let key = MIDIControlKey(kind: .noteOn, channel: 0, number: 60)
        filter.beginBatch()
        XCTAssertEqual(filter.accept(MIDITriggerEdge(key: key, edge: .on), timestamp: 5 * Self.ms), .press)
        XCTAssertFalse(filter.isEmpty)
        filter.reset()
        XCTAssertTrue(filter.isEmpty)
        XCTAssertEqual(filter.accept(MIDITriggerEdge(key: key, edge: .on), timestamp: 6 * Self.ms), .press,
                       "same batch and 1 ms later: fresh after the reset")
    }

    func testPanicActionLinesRoundTripAndAreTriggerOnly() {
        // One binding per target: each source kind on its own.
        for line in ["note:0:61=midi.panic", "ccbtn:0:21=midi.panic", "rt:stop=midi.panic"] {
            let list = MIDINoteBindingList(storageLines: [line])
            XCTAssertEqual(list.binding(for: .panic)?.target, .panic, line)
            XCTAssertEqual(list.storageLines, [line], line)
        }
        let hold = MIDINoteBindingList(storageLines: ["note:0:63=midi.panic;mode=hold"])
        XCTAssertNil(hold.binding(forKey: MIDIControlKey(kind: .noteOn, channel: 0, number: 63)), "hold is unreadable")
        XCTAssertEqual(hold.storageLines, ["note:0:63=midi.panic;mode=hold"], "kept verbatim")
        XCTAssertFalse(MIDINoteAction.panic.allowsHold)
        XCTAssertNil(MIDINoteTarget(action: .panic, mode: .hold))
        XCTAssertEqual(MIDINoteTarget.panic.id, "midi.panic")
        XCTAssertEqual(MIDINoteTarget.panic.title, "MIDI panic")
        XCTAssertEqual(MIDINoteTarget.all.last, .panic)
    }
}
