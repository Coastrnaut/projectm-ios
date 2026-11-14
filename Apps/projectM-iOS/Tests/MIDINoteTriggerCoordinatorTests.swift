// MIDI-006-T08, T11, T13: note triggers in the app with a scripted MIDI system (discovery and input), a manual clock
// and a manual timeout scheduler; `drain()` stands in for the display link. The performer's actions are recorded,
// so every path from MIDI bytes to "next cue" / "black out" is the app's real code apart from the show and display.
// * The row's acceptance (S1, S4): the three equivalent sequences step the show exactly once each.
// * Hold: engage and release, repeats ignored, stuck keys released on listening off and on unplug (S2).
// * Learn: the learning press fires nothing, moves, Undo, announcements; storage beside MIDI-003/004 lines (S3).
import PerformanceControl
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDINoteTriggerCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var actions: [String] = []
        var blackedOut = false
        var announcements: [String] = []
        var now: UInt64 = 1_000_000_000
        var timeouts: [@MainActor () -> Void] = []
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let endpoints: ScriptedMIDIEndpointProvider
        let scheduler: ManualMIDIScheduler
        let discovery: MIDIDiscoveryCoordinator
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let performer: MIDINoteActionPerformer
        let log: Log
    }

    private static let keysID: Int32 = 0x6006
    private static let records: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: keysID, direction: .source, displayName: "Keys", endpointName: "Port",
                           entityName: "Keys", deviceName: "Keys"),
    ]

    private func makeHarness(lines: [String]) throws -> Harness {
        let suite: String = "MIDINoteTriggerCoordinatorTests-" + UUID().uuidString
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
            scheduler: { (_: UInt64, work: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in
                log.timeouts.append(work)
                return { () -> Void in }
            })
        let actions = MIDINoteActionPerformer.Actions(
            nextCue: { () -> Void in log.actions.append("next") },
            previousCue: { () -> Void in log.actions.append("previous") },
            isBlackoutRequested: { () -> Bool in log.blackedOut },
            setBlackout: { (on: Bool) -> Void in
                log.blackedOut = on
                log.actions.append(on ? "blackout" : "restore")
            })
        let performer = MIDINoteActionPerformer(actions: actions)
        mappings.connectNoteActions(performer)
        mappings.open()
        return Harness(defaults: defaults, suite: suite, endpoints: endpoints, scheduler: scheduler, discovery: discovery,
                       inputProvider: inputProvider, input: input, mappings: mappings, performer: performer, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    private func send(_ h: Harness, _ bytes: [UInt8]) {
        h.log.now += 10_000_000
        h.inputProvider.send(bytes, timestamp: h.log.now)
        h.input.drain()
    }

    // MARK: S1, S4 — the acceptance end to end

    func testNextCueStepsOncePerPressForEveryNoteOffForm() throws {
        let h: Harness = try makeHarness(lines: ["note:0:60=cue.next"])
        defer { cleanUp(h) }
        XCTAssertTrue(h.mappings.isInputClientRegistered, "note bindings need the input")
        XCTAssertTrue(h.input.isReceiving)
        send(h, [0x90, 0x3C, 0x64])   // note on
        send(h, [0x90, 0x3C, 0x00])   // velocity 0: release
        send(h, [0x90, 0x3C, 0x64])
        send(h, [0x80, 0x3C, 0x40])   // note off
        send(h, [0x90, 0x3C, 0x64, 0x3C, 0x00])   // running status release, one batch
        XCTAssertEqual(h.log.actions, ["next", "next", "next"])
        send(h, [0x90, 0x3C, 0x64])
        send(h, [0x90, 0x3C, 0x64])   // repeated press without a release
        XCTAssertEqual(h.log.actions.count, 4, "a repeated note on fires nothing")
        send(h, [0x91, 0x3C, 0x00, 0x91, 0x3C, 0x64])   // channel 2
        XCTAssertEqual(h.log.actions.count, 4, "another channel fires nothing")
    }

    func testHoldBlacksOutWhileHeldAndOnlyUndoesWhatItDid() throws {
        let h: Harness = try makeHarness(lines: ["note:0:61=blackout;mode=hold", "note:0:62=blackout"])
        defer { cleanUp(h) }
        send(h, [0x90, 0x3D, 0x64])
        XCTAssertTrue(h.log.blackedOut)
        send(h, [0x90, 0x3D, 0x7F])
        XCTAssertEqual(h.log.actions, ["blackout"], "a repeated note on does not toggle")
        send(h, [0x90, 0x3D, 0x00])
        XCTAssertEqual(h.log.actions, ["blackout", "restore"])
        // Already blacked out (the toggle): the hold neither blacks out again nor restores.
        send(h, [0x90, 0x3E, 0x64, 0x80, 0x3E, 0x00])
        send(h, [0x90, 0x3D, 0x64, 0x80, 0x3D, 0x00])
        XCTAssertEqual(h.log.actions, ["blackout", "restore", "blackout"])
        XCTAssertTrue(h.log.blackedOut)
        XCTAssertFalse(h.performer.holdBlackedOut)
    }

    func testStuckHoldReleasesOnListeningOffAndOnUnplug() throws {
        let h: Harness = try makeHarness(lines: ["note:0:61=blackout;mode=hold"])
        defer { cleanUp(h) }
        send(h, [0x90, 0x3D, 0x64])
        XCTAssertTrue(h.log.blackedOut)
        h.discovery.setEnabled(false)
        XCTAssertFalse(h.input.isReceiving)
        XCTAssertFalse(h.log.blackedOut, "listening off releases the held key")
        h.discovery.setEnabled(true)
        _ = h.scheduler.runAll()
        XCTAssertTrue(h.input.isReceiving)
        send(h, [0x90, 0x3D, 0x64])
        XCTAssertTrue(h.log.blackedOut)
        h.endpoints.unplug(uniqueIDs: [Self.keysID])
        _ = h.scheduler.runAll()
        XCTAssertFalse(h.log.blackedOut, "the input disappearing releases the held key")
        XCTAssertEqual(h.log.actions, ["blackout", "restore", "blackout", "restore"])
    }

    func testDeletingAHeldMappingReleasesIt() throws {
        let h: Harness = try makeHarness(lines: ["note:0:61=blackout;mode=hold"])
        defer { cleanUp(h) }
        send(h, [0x90, 0x3D, 0x64])
        h.mappings.deleteNoteMapping(.blackoutHold)
        XCTAssertEqual(h.log.actions, ["blackout", "restore"])
        send(h, [0x80, 0x3D, 0x00])
        XCTAssertEqual(h.log.actions.count, 2, "the later release does nothing")
        XCTAssertNil(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey), "nothing left to store")
    }

    // MARK: Learn (T13)

    func testLearnANoteTheLearningPressFiresNothing() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity;invert=1"])
        defer { cleanUp(h) }
        h.mappings.startLearningNote(.nextCue)
        XCTAssertTrue(h.mappings.isLearning)
        XCTAssertEqual(h.mappings.statusText, "Press a key or pad on your MIDI device to map Next cue…")
        send(h, [0xB0, 0x07, 0x40, 0x90, 0x3C, 0x00])   // a CC and a release: not learned
        XCTAssertTrue(h.mappings.isLearning)
        send(h, [0x90, 0x3C, 0x64])
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertEqual(h.log.actions, [], "the learning press fires nothing")
        send(h, [0x80, 0x3C, 0x00])
        XCTAssertEqual(h.log.actions, [], "nor its release")
        send(h, [0x90, 0x3C, 0x64])
        XCTAssertEqual(h.log.actions, ["next"])
        XCTAssertEqual(h.log.announcements, ["Press a key or pad on your MIDI device to map Next cue.",
                                             "Next cue mapped to note C4 on channel 1."])
        let row = try XCTUnwrap(h.mappings.noteRows.first)
        XCTAssertEqual(row.control, "Note C4 · Ch 1")
        XCTAssertEqual(row.accessibilityLabel, "Next cue, note C4, channel 1")
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey),
                       ["cc:0:7=effect.bloom.intensity;invert=1", "note:0:60=cue.next"], "the CC line is unchanged")
    }

    func testLearnMovesANoteAndUndoRestoresBothLists() throws {
        let h: Harness = try makeHarness(lines: ["note:0:60=cue.next", "note:0:1=cue.fire:XYZ"])
        defer { cleanUp(h) }
        h.mappings.startLearning(MIDIMappingCoordinator.appliedIDs.sorted { (a, b) -> Bool in a.rawValue < b.rawValue }[0])
        h.mappings.startLearningNote(.previousCue)
        XCTAssertNil(h.mappings.learningTarget, "a note learn replaces a CC learn")
        send(h, [0x90, 0x3C, 0x64])
        XCTAssertEqual(h.mappings.statusText, "Previous cue mapped to note C4 on channel 1 (moved from Next cue).")
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey),
                       ["note:0:60=cue.previous", "note:0:1=cue.fire:XYZ"], "an unknown action is kept")
        XCTAssertTrue(h.mappings.canUndo)
        h.mappings.undo()
        XCTAssertEqual(h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey),
                       ["note:0:60=cue.next", "note:0:1=cue.fire:XYZ"])
    }

    func testNoteLearnTimesOutAndCancels() throws {
        let h: Harness = try makeHarness(lines: [])
        defer { cleanUp(h) }
        h.mappings.startLearningNote(.blackoutHold)
        h.log.now += MIDILearnSession<MIDINoteTarget>.timeoutNanoseconds
        h.log.timeouts.last?()
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertEqual(h.mappings.statusText, MIDIMappingCoordinator.timedOutText)
        h.mappings.startLearningNote(.blackoutHold)
        h.mappings.cancelLearning()
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertEqual(h.mappings.statusText, MIDIMappingCoordinator.cancelledText)
        XCTAssertFalse(h.mappings.isInputClientRegistered, "no bindings, no learn: no input client")
    }
}
