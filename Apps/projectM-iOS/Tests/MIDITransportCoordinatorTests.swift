// MIDI-008-T06, T07, T08: transport mapping in the app with a scripted MIDI system (discovery and input), a manual
// clock and a manual timeout scheduler; `drain()` stands in for the display link and every packet carries an explicit
// timestamp. The performer's actions are recorded, so every path from MIDI bytes to "next cue" / "pause" is the app's
// real code apart from the show and the visual.
// * The row's acceptance (S1): note, CC button and real-time × doubled in one batch, doubled across two batches 5 ms
//   apart, CC 127 repeated without a 0: one action per press; a deliberate second press acts again.
// * Play/Pause (S2): toggle, Play and Pause idempotent, Start → Play and Stop → Pause.
// * Learn (R6, R7): a CC button (its copy and release fire nothing), MIDI Start, CC moved from a glow parameter and
//   back, Undo, announcements on the `.midi` announcer; a held CC button released when the input stops.
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDITransportCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var actions: [String] = []
        var blackedOut = false
        var paused = false
        var announcements: [String] = []
        var now: UInt64 = 1_000_000_000
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let scheduler: ManualMIDIScheduler
        let discovery: MIDIDiscoveryCoordinator
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let log: Log
    }

    private static let ms: UInt64 = 1_000_000
    private static let keysID: Int32 = 0x6008
    private static let records: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: keysID, direction: .source, displayName: "Pads", endpointName: "Port",
                           entityName: "Pads", deviceName: "Pads"),
    ]

    private static func actions(_ log: Log) -> MIDINoteActionPerformer.Actions {
        var actions = MIDINoteActionPerformer.Actions(
            nextCue: { () -> Void in log.actions.append("next") },
            previousCue: { () -> Void in log.actions.append("previous") },
            isBlackoutRequested: { () -> Bool in log.blackedOut },
            setBlackout: { (on: Bool) -> Void in
                log.blackedOut = on
                log.actions.append(on ? "blackout" : "restore")
            })
        actions.isPaused = { () -> Bool in log.paused }
        actions.setPaused = { (paused: Bool) -> Void in
            log.paused = paused
            log.actions.append(paused ? "pause" : "play")
        }
        return actions
    }

    private func makeHarness(lines: [String]) throws -> Harness {
        let suite: String = "MIDITransportCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        if !lines.isEmpty { defaults.set(lines, forKey: MIDIMappingCoordinator.mappingsKey) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let endpoints = ScriptedMIDIEndpointProvider(records: Self.records)
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(settings: settings,
                                                 discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler))
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDIInputProvider()
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let log = Log()
        let mappings = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: discovery, defaults: defaults,
            announce: { (text: String) -> Void in log.announcements.append(text) },
            clock: { () -> UInt64 in log.now },
            scheduler: { (_: UInt64, _: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in { () -> Void in } })
        mappings.connectNoteActions(MIDINoteActionPerformer(actions: Self.actions(log)))
        mappings.open()
        return Harness(defaults: defaults, suite: suite, scheduler: scheduler, discovery: discovery,
                       inputProvider: inputProvider, input: input, mappings: mappings, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    /// One delivered batch: each packet list stamped `offset` ms after the previous batch's base, then a drain.
    private func batch(_ h: Harness, _ packets: [[UInt8]], after offset: UInt64) {
        h.log.now += offset * Self.ms
        for bytes in packets { XCTAssertTrue(h.inputProvider.send(bytes, timestamp: h.log.now)) }
        h.input.drain()
    }

    private static let notePress: [UInt8] = [0x90, 0x3C, 0x64, 0x80, 0x3C, 0x00]
    private static let buttonPress: [UInt8] = [0xB0, 0x14, 0x7F, 0xB0, 0x14, 0x00]
    private static let start: [UInt8] = [0xFA]

    // MARK: S1 — each mapped message fires one action despite repeated packets

    func testEverySourceKindFiresOncePerPressDespiteRepeatedPackets() throws {
        let h: Harness = try makeHarness(lines: ["note:0:60=cue.next", "ccbtn:0:20=blackout", "rt:start=transport.toggle"])
        defer { cleanUp(h) }
        let sources: [([UInt8], String)] = [(Self.notePress, "next"), (Self.buttonPress, "blackout"), (Self.start, "pause")]
        for (press, action) in sources {
            h.log.actions = []
            batch(h, [press, press], after: 500)   // doubled in one packet list
            XCTAssertEqual(h.log.actions, [action], "doubled in one batch: \(action)")
            h.log.actions = []
            batch(h, [press], after: 500)
            batch(h, [press], after: 5)   // the copy, 5 ms later in the next batch
            XCTAssertEqual(h.log.actions.count, 1, "doubled across batches 5 ms apart: \(h.log.actions)")
            h.log.actions = []
            batch(h, [press], after: 200)   // a deliberate second press
            XCTAssertEqual(h.log.actions.count, 1, "a deliberate press acts again: \(action)")
        }
        h.log.actions = []
        batch(h, [[0xB0, 0x14, 0x7F]], after: 500)
        batch(h, [[0xB0, 0x14, 0x7F]], after: 200)   // 127 again, no 0 between
        batch(h, [[0xB0, 0x14, 0x7F, 0xB0, 0x14, 0x7F]], after: 200)
        XCTAssertEqual(h.log.actions, ["restore"], "CC 127 repeated without a 0: one press")
        batch(h, [[0xB0, 0x14, 0x00]], after: 200)
        batch(h, [[0xB0, 0x14, 0x7F]], after: 200)
        XCTAssertEqual(h.log.actions, ["restore", "blackout"], "after a 0, the next 127 presses")
    }

    // MARK: S2 — play and pause

    func testPlayPauseTogglesAndPlayAndPauseAreIdempotent() throws {
        let h: Harness = try makeHarness(lines: ["note:0:62=transport.toggle", "rt:start=transport.play", "rt:stop=transport.pause"])
        defer { cleanUp(h) }
        let toggle: [UInt8] = [0x90, 0x3E, 0x64, 0x80, 0x3E, 0x00]
        batch(h, [toggle], after: 500)
        XCTAssertTrue(h.log.paused)
        batch(h, [toggle], after: 500)
        XCTAssertFalse(h.log.paused)
        XCTAssertEqual(h.log.actions, ["pause", "play"])
        batch(h, [Self.start], after: 500)
        XCTAssertEqual(h.log.actions, ["pause", "play"], "Play while playing changes nothing")
        batch(h, [[0xFC]], after: 500)
        batch(h, [[0xFC]], after: 500)
        XCTAssertEqual(h.log.actions, ["pause", "play", "pause"], "Stop pauses once; a second Stop changes nothing")
        batch(h, [[0xFB]], after: 500)
        XCTAssertEqual(h.log.actions.last, "play", "Continue is Start")
    }

    // MARK: R6, R7 — learn

    func testLearnACCButtonItsCopiesFireNothingThenItTriggers() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:20=effect.bloom.intensity", "note:0:60=cue.next"])
        defer { cleanUp(h) }
        h.mappings.startLearningNote(.nextCue)
        batch(h, [[0xB0, 0x14, 0x20]], after: 500)   // below 64: no press
        XCTAssertTrue(h.mappings.isLearning)
        batch(h, [[0xB0, 0x14, 0x7F]], after: 500)
        XCTAssertFalse(h.mappings.isLearning)
        batch(h, [[0xB0, 0x14, 0x7F]], after: 5)   // the learning message's copy
        batch(h, [[0xB0, 0x14, 0x00]], after: 50)
        XCTAssertEqual(h.log.actions, [], "the learning press, its copy and its release fire nothing")
        XCTAssertEqual(h.mappings.statusText, "Next cue mapped to CC button 20 on channel 1 (moved from Glow intensity).")
        XCTAssertEqual(h.log.announcements.last, h.mappings.statusText)
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey), ["ccbtn:0:20=cue.next"],
                       "the CC left the glow and replaced the note")
        let row = try XCTUnwrap(h.mappings.noteRows.first { (r: MIDINoteRow) -> Bool in r.target == .nextCue })
        XCTAssertEqual(row.control, "CC 20 · Ch 1")
        XCTAssertEqual(row.accessibilityLabel, "Next cue, CC 20, channel 1")
        batch(h, [Self.buttonPress], after: 500)
        batch(h, [Self.buttonPress], after: 500)
        XCTAssertEqual(h.log.actions, ["next", "next"])
        h.mappings.undo()
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey),
                       ["cc:0:20=effect.bloom.intensity", "note:0:60=cue.next"], "Undo restores both lists")
    }

    func testLearnMIDIStartAndBackToAParameter() throws {
        let h: Harness = try makeHarness(lines: ["ccbtn:0:7=blackout"])
        defer { cleanUp(h) }
        h.mappings.startLearningNote(.blackoutHold)
        batch(h, [[0xFC]], after: 500)
        XCTAssertTrue(h.mappings.isLearning, "real-time is not a hold source")
        h.mappings.startLearningNote(.playPause)
        batch(h, [[0xFB]], after: 500)   // Continue learns as Start
        XCTAssertEqual(h.mappings.statusText, "Play/Pause mapped to MIDI Start.")
        XCTAssertEqual(h.mappings.noteRows.first?.control, "MIDI Start")
        batch(h, [Self.start], after: 10)
        XCTAssertEqual(h.log.actions, [], "a Start right after the learning Continue is its copy")
        batch(h, [Self.start], after: 500)
        XCTAssertEqual(h.log.actions, ["pause"])
        let glow = try XCTUnwrap(MIDIMappingCoordinator.appliedIDs.first { (id) -> Bool in id.rawValue == "effect.bloom.intensity" })
        h.mappings.startLearning(glow)
        batch(h, [[0xB0, 0x07, 0x40]], after: 500)
        XCTAssertEqual(h.mappings.statusText, "Glow intensity mapped to CC 7 on channel 1 (moved from Black out).")
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey),
                       ["cc:0:7=effect.bloom.intensity", "rt:start=transport.toggle"])
    }

    func testAHeldCCButtonIsReleasedWhenTheInputStops() throws {
        let h: Harness = try makeHarness(lines: ["ccbtn:0:21=blackout;mode=hold"])
        defer { cleanUp(h) }
        batch(h, [[0xB0, 0x15, 0x7F]], after: 500)
        XCTAssertEqual(h.log.actions, ["blackout"])
        h.discovery.setEnabled(false)
        XCTAssertEqual(h.log.actions, ["blackout", "restore"])
    }
}
