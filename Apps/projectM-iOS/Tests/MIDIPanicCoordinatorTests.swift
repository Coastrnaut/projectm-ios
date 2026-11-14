// MIDI-013-T06, T09, T11: the MIDI panic in the app with the scripted MIDI system (discovery and an input over a source
// system with handles), a manual scheduler and clock, and `drain()` for the display link. From MIDI bytes to the
// router, the performer's hold blackout and the stored list, everything is the app's real code.
// * Acceptance (S1-S3): three held notes (one "Black out while held"), a held CC button and a learn session → panic →
//   zero active gates, an empty press rule, the blackout restored, learning cancelled, stored lines byte-identical,
//   live CC values, listening and the scene untouched, "MIDI reset" on the `.midi` lane; later presses fire.
// * Idle (S4), queued input dropped (R3), a `midi.panic` binding (R8) and the shortcut (R7).
import ParameterGraph
import PerformanceControl
import SwiftUI
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIPanicCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var actions: [String] = []
        var blackedOut = false
        var announcements: [String] = []
        var scenes: [MIDISceneCommand] = []
        var now: UInt64 = 1_000_000_000
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let inputProvider: ScriptedMIDISourceInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let log: Log
    }

    private static let keysID: Int32 = 0x1301
    private static let keys = MIDIEndpointRecord(uniqueID: keysID, direction: .source, displayName: "Keys",
                                                 endpointName: "Port", entityName: "Keys", deviceName: "Keys")
    private static let lines: [String] = ["cc:0:7=effect.bloom.intensity", "note:0:60=cue.next", "note:0:62=blackout;mode=hold",
                                          "note:0:64=cue.previous", "ccbtn:0:20=transport.toggle", "pc:0:5=cue.go:scene-a"]

    private func makeHarness(lines: [String] = lines) throws -> Harness {
        let suite: String = "MIDIPanicCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        defaults.set(lines, forKey: MIDIMappingCoordinator.mappingsKey)
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let log = Log()
        let endpoints = ScriptedMIDIEndpointProvider(records: [Self.keys])
        let system = ScriptedMIDISourceSystem(records: [Self.keys])
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(
            settings: settings, discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler),
            announce: { (_: String) -> Void in })
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDISourceInputProvider(system: system, scheduler: scheduler.scheduler)
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let mappings = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: discovery, defaults: defaults,
            announce: { (text: String) -> Void in log.announcements.append(text) },
            clock: { () -> UInt64 in log.now },
            scheduler: { (_: UInt64, _: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in { () -> Void in } })
        let actions = MIDINoteActionPerformer.Actions(
            nextCue: { () -> Void in log.actions.append("next") },
            previousCue: { () -> Void in log.actions.append("previous") },
            isBlackoutRequested: { () -> Bool in log.blackedOut },
            setBlackout: { (on: Bool) -> Void in
                log.blackedOut = on
                log.actions.append(on ? "blackout" : "restore")
            })
        mappings.connectNoteActions(MIDINoteActionPerformer(actions: actions))
        mappings.performScenes = { (command: MIDISceneCommand) -> Void in log.scenes.append(command) }
        mappings.open()
        return Harness(defaults: defaults, suite: suite, inputProvider: inputProvider, input: input, mappings: mappings, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
    }

    /// Queues bytes from Keys `ms` milliseconds later, without draining.
    private func queue(_ h: Harness, _ bytes: [UInt8], after ms: UInt64 = 100) {
        h.log.now += ms * 1_000_000
        h.inputProvider.send(bytes, from: Self.keysID, timestamp: h.log.now)
    }

    private func send(_ h: Harness, _ bytes: [UInt8], after ms: UInt64 = 100) {
        queue(h, bytes, after: ms)
        h.input.drain()
    }

    private func storedBytes(_ h: Harness) -> [[UInt8]] {
        (h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey) ?? []).map { (line: String) -> [UInt8] in Array(line.utf8) }
    }

    // MARK: Acceptance (MIDI-013-S1, S2, S3)

    func testPanicLeavesNoActiveGatesAndKeepsMappings() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        XCTAssertTrue(h.input.isReceiving)
        send(h, [0xB0, 0x07, 0x7F])   // a live CC value
        let liveBefore: [ParameterID: Double] = h.mappings.liveValues
        send(h, [0x90, 0x3C, 0x64, 0x90, 0x3E, 0x64, 0x90, 0x40, 0x64, 0xB0, 0x14, 0x7F])   // three notes and a CC button
        XCTAssertEqual(h.log.actions, ["next", "blackout", "previous"], "the CC button toggles Pause (not logged)")
        XCTAssertEqual(h.mappings.heldKeyCount, 4)
        XCTAssertTrue(h.log.blackedOut)
        h.mappings.startLearningNote(.pause)
        XCTAssertTrue(h.mappings.isLearning)
        let storedBefore: [[UInt8]] = storedBytes(h)
        h.log.actions.removeAll()
        h.log.announcements.removeAll()

        h.mappings.panic()

        XCTAssertEqual(h.mappings.heldKeyCount, 0, "no active note gates")
        XCTAssertTrue(h.mappings.isNoteRouterIdle, "the press rule holds nothing")
        XCTAssertEqual(h.log.actions, ["restore"], "the hold's blackout restored through the release path")
        XCTAssertFalse(h.log.blackedOut)
        XCTAssertFalse(h.mappings.isLearning, "learning cancelled")
        XCTAssertNil(h.mappings.learningNoteTarget)
        XCTAssertEqual(storedBytes(h), storedBefore, "stored mappings byte-identical")
        XCTAssertEqual(h.mappings.storedLines, Self.lines)
        XCTAssertNil(h.mappings.noteBindings.binding(for: .pause), "nothing learned")
        XCTAssertEqual(h.mappings.liveValues, liveBefore, "live CC values kept")
        XCTAssertTrue(h.input.isReceiving, "listening unchanged")
        XCTAssertTrue(h.log.scenes.isEmpty, "the scene untouched")
        XCTAssertEqual(h.log.announcements, ["MIDI reset"])
        XCTAssertEqual(h.mappings.statusText, "MIDI reset.")

        // Later presses work normally: the late releases are ignored, then fresh presses fire once.
        send(h, [0x80, 0x3C, 0x00, 0x80, 0x3E, 0x00, 0xB0, 0x14, 0x00], after: 5)
        XCTAssertEqual(h.log.actions, ["restore"])
        send(h, [0x90, 0x3C, 0x64, 0x90, 0x3E, 0x64], after: 5)
        XCTAssertEqual(h.log.actions, ["restore", "next", "blackout"])
        send(h, [0x80, 0x3E, 0x00])
        XCTAssertEqual(h.log.actions, ["restore", "next", "blackout", "restore"])
    }

    // MARK: Idle (MIDI-013-S4, R9)

    func testPanicWhileIdleIsANoOp() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        let storedBefore: [[UInt8]] = storedBytes(h)
        h.mappings.panic()
        XCTAssertTrue(h.log.actions.isEmpty)
        XCTAssertTrue(h.log.scenes.isEmpty)
        XCTAssertEqual(storedBytes(h), storedBefore)
        XCTAssertTrue(h.mappings.isNoteRouterIdle)
        XCTAssertEqual(h.log.announcements, ["MIDI reset"], "the command is still confirmed")
    }

    // MARK: Queued input (MIDI-013-R3)

    func testQueuedMessagesAreDropped() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        queue(h, [0x90, 0x3C, 0x64, 0x90, 0x3E, 0x64])
        h.mappings.panic()
        h.input.drain()
        XCTAssertTrue(h.log.actions.isEmpty, "messages sent before the command never press")
        XCTAssertEqual(h.mappings.heldKeyCount, 0)
    }

    // MARK: A `midi.panic` binding (MIDI-013-R8)

    func testAPanicBindingRunsPanicAfterEarlierCommands() throws {
        let h: Harness = try makeHarness(lines: ["note:0:60=cue.next", "note:0:62=blackout;mode=hold", "note:0:61=midi.panic"])
        defer { cleanUp(h) }
        send(h, [0x90, 0x3E, 0x64])   // hold blackout
        XCTAssertEqual(h.log.actions, ["blackout"])
        // In one batch: next cue, panic, then next cue again (dropped with the rest of the batch).
        send(h, [0x90, 0x3C, 0x64, 0x90, 0x3D, 0x64, 0x80, 0x3C, 0x00, 0x90, 0x3C, 0x64])
        XCTAssertEqual(h.log.actions, ["blackout", "next", "restore"])
        XCTAssertEqual(h.mappings.heldKeyCount, 0, "the panic key is not left down")
        XCTAssertEqual(h.log.announcements.last, "MIDI reset")
        send(h, [0x90, 0x3C, 0x64])
        XCTAssertEqual(h.log.actions, ["blackout", "next", "restore", "next"])
        XCTAssertTrue(h.mappings.noteRows.contains { (row: MIDINoteRow) -> Bool in row.id == "midi.panic" && row.control != nil })
    }

    // MARK: Keyboard shortcut (MIDI-013-R7)

    func testShortcutIsCommandShiftM() {
        XCTAssertEqual(MIDIPanicShortcut.key, KeyEquivalent("m"))
        XCTAssertEqual(MIDIPanicShortcut.modifiers, [.command, .shift])
    }
}
