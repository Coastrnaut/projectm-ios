// MIDI-007-T08 to T11: scene selection in the app with a scripted MIDI system (discovery and input), a manual clock
// and a manual timeout scheduler; `drain()` stands in for the display link. The show is a real `ShowCoordinator` over
// a temporary store, and its `applyScene` runs the app's own settings path (`ShowSceneSnapshot.apply` and
// `AppCoordinator.set`) on the same UserDefaults suite as the MIDI mappings, so "stored mappings unchanged" is checked
// against everything a selection writes.
// * The row's acceptance (S1): PC 5 on channel 1 selects scene X, which is applied; `settings.midi.mappings` is
//   byte-identical (property-list bytes) before and after. The same for a note mapping.
// * S2: channel filtering, the debounce on the current scene, a missing scene. S3: the position mode.
// * Learn (T11): Assign MIDI learns a program or a note, the learning message selects nothing, moves, Undo, rows.
import Foundation
import ParameterGraph
import PerformanceControl
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDISceneSelectionCoordinatorTests: XCTestCase {
    @MainActor private final class Log {
        var applied: [String] = []
        var announcements: [String] = []
        var noteActions: [String] = []
        var now: UInt64 = 1_000_000_000
        var timeouts: [@MainActor () -> Void] = []
    }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let folder: URL
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let show: ShowCoordinator
        /// Scene IDs of cues 1…3 ("Opening", "Build", "Drop").
        let scenes: [String]
        let log: Log
    }

    private static let keysID: Int32 = 0x7007
    private static let records: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: keysID, direction: .source, displayName: "Pads", endpointName: "Port",
                           entityName: "Pads", deviceName: "Pads"),
    ]
    private static let labels: [String] = ["Opening", "Build", "Drop"]
    private static func sceneID(_ n: Int) -> String { "5CE7E000-0000-4000-8000-00000000070" + String(n) }

    private func look(_ visual: VisualChoice, bars: Int) -> ShowLook {
        ShowLook(visual: visual, bars: bars, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    /// Three cues; the third ("Drop") carries an SCN-001 binding with a MIDI-like source (MIDI-related scene state).
    private func makeShow(folder: URL, settings: AppSettings, texts: TextOverlayCoordinator, log: Log) throws -> ShowCoordinator {
        let registry: ParameterRegistry = try SceneArchiveService.appRegistry()
        let show = ShowCoordinator(store: ShowStore(directory: folder), registry: registry)
        let looks: [ShowLook] = [look(.circularSpectrum, bars: 64), look(.linearSpectrum, bars: 32), look(.circularSpectrum, bars: 16)]
        for (index, item) in looks.enumerated() {
            var document: SceneDocument = ShowSceneSnapshot.document(item, id: Self.sceneID(index + 1), name: Self.labels[index])
            if index == 2 {
                document.bindings = [SceneBinding(sourceID: "midi.cc.0.7", target: VisualParameterIDs.bloomRadius,
                                                  mapping: LinearMapping(outputStart: 0, outputEnd: 1))]
            }
            XCTAssertTrue(show.addScene(document, label: Self.labels[index]))
        }
        show.applyScene = { (document: SceneDocument, warnings: [SceneIssue]) -> [String] in
            let apply: ShowSceneApply = ShowSceneSnapshot.apply(of: document, warnings: warnings, registry: registry)
            AppCoordinator.set(apply, settings: settings, texts: texts)   // the app's settings path
            log.applied.append(document.id)
            return []
        }
        show.announce = { (_: String) -> Void in }
        show.go(to: show.list.cues[0].id)   // standing on cue 1
        log.applied.removeAll()
        return show
    }

    private func makeHarness(lines: [String]) throws -> Harness {
        let suite: String = "MIDISceneSelectionCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        if !lines.isEmpty { defaults.set(lines, forKey: MIDIMappingCoordinator.mappingsKey) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let folder: URL = FileManager.default.temporaryDirectory.appendingPathComponent("MIDISceneSelection-" + UUID().uuidString)
        let log = Log()
        let show: ShowCoordinator = try makeShow(folder: folder, settings: settings,
                                                 texts: TextOverlayCoordinator(store: TextOverlayStore(defaults: defaults)), log: log)
        let endpoints = ScriptedMIDIEndpointProvider(records: Self.records)
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(settings: settings,
                                                 discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler))
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDIInputProvider()
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let mappings = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: discovery, defaults: defaults,
            announce: { (text: String) -> Void in log.announcements.append(text) },
            clock: { () -> UInt64 in log.now },
            scheduler: { (_: UInt64, work: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in
                log.timeouts.append(work)
                return { () -> Void in }
            })
        // The app's wiring (AppCoordinator+Show), with the note triggers recorded.
        mappings.connectSceneActions(MIDISceneActionPerformer(show: show, announce: mappings.announce))
        mappings.sceneDisplayName = { [weak show] (id: String) -> String? in
            guard let show, show.firstCue(ofScene: id) != nil else { return nil }
            return show.displayName(ofScene: id)
        }
        let noteActions = MIDINoteActionPerformer.Actions(
            nextCue: { () -> Void in log.noteActions.append("next") },
            previousCue: { () -> Void in log.noteActions.append("previous") },
            isBlackoutRequested: { () -> Bool in false },
            setBlackout: { (_: Bool) -> Void in log.noteActions.append("blackout") })
        mappings.connectNoteActions(MIDINoteActionPerformer(actions: noteActions))
        mappings.open()
        let scenes: [String] = (1...3).map { (n: Int) -> String in Self.sceneID(n) }
        return Harness(defaults: defaults, suite: suite, folder: folder, inputProvider: inputProvider, input: input,
                       mappings: mappings, show: show, scenes: scenes, log: log)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
        try? FileManager.default.removeItem(at: h.folder)
    }

    private func send(_ h: Harness, _ bytes: [UInt8]) {
        h.log.now += 10_000_000
        h.inputProvider.send(bytes, timestamp: h.log.now)
        h.input.drain()
    }

    /// The stored mappings as bytes (binary property list of the stored value; nil-safe).
    private func storedBytes(_ h: Harness) throws -> Data {
        let value: Any = h.defaults.object(forKey: MIDIMappingCoordinator.mappingsKey) ?? [String]()
        return try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private func stored(_ h: Harness) -> [String]? {
        h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey)
    }

    // MARK: S1 — the row's acceptance

    func testProgramChangeSelectsTheSceneWithoutChangingStoredMappings() throws {
        let lines: [String] = ["cc:0:7=effect.bloom.intensity;invert=1", "note:0:60=cue.next",
                               "pc:0:5=cue.go:" + Self.sceneID(3), "pc:0:9=future.thing", "pc:*:*=cue.position"]
        let h: Harness = try makeHarness(lines: lines)
        defer { cleanUp(h) }
        let before: Data = try storedBytes(h)
        XCTAssertTrue(h.mappings.isInputClientRegistered, "scene mappings need the input")
        XCTAssertEqual(h.show.list.activeSceneID, h.scenes[0])

        send(h, [0xC0, 0x05])   // PC 5, channel 1

        XCTAssertEqual(h.show.list.activeSceneID, h.scenes[2], "the mapped scene's cue is current")
        XCTAssertEqual(h.show.appliedSceneID, h.scenes[2])
        XCTAssertEqual(h.log.applied, [h.scenes[2]], "applied once")
        XCTAssertEqual(try storedBytes(h), before, "settings.midi.mappings byte-identical")
        XCTAssertEqual(stored(h), lines, "and line for line (kept lines included)")

        send(h, [0xC0, 0x05])   // repeated: the scene is current
        XCTAssertEqual(h.log.applied, [h.scenes[2]], "a repeat re-applies nothing")
        send(h, [0xC1, 0x05])   // channel 2: no mapping there, and the position mode selects cue 6, which is missing
        XCTAssertEqual(h.show.list.activeSceneID, h.scenes[2])
        XCTAssertEqual(h.log.announcements.last, "Cue 6 not found.")
        XCTAssertEqual(try storedBytes(h), before)
    }

    func testNoteSelectsTheSceneWithoutChangingStoredMappings() throws {
        let lines: [String] = ["note:0:60=cue.next", "note:0:62=cue.go:" + Self.sceneID(2)]
        let h: Harness = try makeHarness(lines: lines)
        defer { cleanUp(h) }
        let before: Data = try storedBytes(h)
        send(h, [0x90, 0x3E, 0x64])   // note on 62
        XCTAssertEqual(h.show.list.activeSceneID, h.scenes[1])
        XCTAssertEqual(h.log.applied, [h.scenes[1]])
        send(h, [0x80, 0x3E, 0x00, 0x90, 0x3E, 0x00])   // releases select nothing
        send(h, [0x90, 0x3C, 0x64])   // the MIDI-006 trigger still fires
        XCTAssertEqual(h.log.noteActions, ["next"])
        send(h, [0x91, 0x3E, 0x64])   // channel 2
        XCTAssertEqual(h.log.applied, [h.scenes[1]])
        XCTAssertEqual(try storedBytes(h), before, "byte-identical")
        XCTAssertEqual(stored(h), lines)
    }

    // MARK: S2 — missing scenes

    func testAMissingSceneIsAnnouncedAndChangesNothing() throws {
        let h: Harness = try makeHarness(lines: ["pc:0:1=cue.go:0DDBA11E-0000-4000-8000-000000000001"])
        defer { cleanUp(h) }
        send(h, [0xC0, 0x01])
        XCTAssertEqual(h.show.list.activeSceneID, h.scenes[0])
        XCTAssertEqual(h.log.applied, [])
        XCTAssertEqual(h.log.announcements, [MIDIMappingCoordinator.sceneNotFoundText])
        XCTAssertEqual(h.mappings.sceneRows.map { (row: MIDISceneRow) -> String in row.name }, ["Scene not found"])
    }

    // MARK: S3 — the position mode

    func testProgramNumberSelectsCuePositionOnTheChosenChannel() throws {
        let h: Harness = try makeHarness(lines: ["pc:0:1=cue.go:" + Self.sceneID(3)])
        defer { cleanUp(h) }
        send(h, [0xC0, 0x02])
        XCTAssertEqual(h.log.applied, [], "off by default")
        h.mappings.setProgramCueMode(.channel(0))
        XCTAssertEqual(stored(h), ["pc:0:1=cue.go:" + Self.sceneID(3), "pc:0:*=cue.position"], "saved at once")
        XCTAssertFalse(h.mappings.canUndo, "no Undo entry")
        send(h, [0xC1, 0x02])
        XCTAssertEqual(h.log.applied, [], "another channel")
        send(h, [0xC0, 0x01])
        XCTAssertEqual(h.show.list.activeSceneID, h.scenes[2], "the explicit mapping wins over cue 2")
        send(h, [0xC0, 0x01, 0xC0, 0x01])   // repeats: Drop is current
        XCTAssertEqual(h.log.applied, [h.scenes[2]])
        send(h, [0xC0, 0x00])
        XCTAssertEqual(h.show.list.activeIndex, 0, "program 0 selects cue 1")
        send(h, [0xC0, 0x09])
        XCTAssertEqual(h.log.announcements.last, "Cue 10 not found.")
        XCTAssertEqual(h.show.list.activeIndex, 0)
        h.mappings.setProgramCueMode(.off)
        XCTAssertEqual(stored(h), ["pc:0:1=cue.go:" + Self.sceneID(3)])
    }

    // MARK: T11 — Assign MIDI (learn)

    func testAssignAProgramTheLearningMessageSelectsNothingThenItTriggers() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity"])
        defer { cleanUp(h) }
        h.mappings.startLearningScene(h.scenes[2])
        XCTAssertEqual(h.mappings.statusText, "Send a program change or press a key on your MIDI device to map Drop…")
        send(h, [0xB0, 0x00, 0x01, 0x90, 0x3C, 0x00])   // bank select and a release: not learned
        XCTAssertTrue(h.mappings.isLearning)
        send(h, [0xC0, 0x05])
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertEqual(h.log.applied, [], "the learning message selects nothing")
        XCTAssertEqual(h.mappings.statusText, "Drop mapped to program 5 on channel 1.")
        XCTAssertEqual(stored(h), ["cc:0:7=effect.bloom.intensity", "pc:0:5=cue.go:" + Self.sceneID(3)])
        XCTAssertEqual(h.mappings.sceneControl(for: h.scenes[2]), "Program 5 · Ch 1")
        let row: MIDISceneRow = try XCTUnwrap(h.mappings.sceneRows.first)
        XCTAssertEqual(row.accessibilityLabel, "Drop, program 5, channel 1")
        send(h, [0xC0, 0x05])
        XCTAssertEqual(h.show.list.activeSceneID, h.scenes[2])
        XCTAssertEqual(h.log.announcements, ["Send a program change or press a key on your MIDI device to map Drop.",
                                             "Drop mapped to program 5 on channel 1."], "learn on .midi; the cue on its own lane")
    }

    func testAssignANoteMovesItFromATriggerAndUndoRestoresEveryList() throws {
        let lines: [String] = ["note:0:60=cue.next", "pc:0:5=cue.go:" + Self.sceneID(2)]
        let h: Harness = try makeHarness(lines: lines)
        defer { cleanUp(h) }
        h.mappings.startLearningNote(.previousCue)
        h.mappings.startLearningScene(h.scenes[1])   // replaces the note learn
        XCTAssertNil(h.mappings.learningNoteTarget)
        send(h, [0x90, 0x3C, 0x64])
        XCTAssertEqual(h.log.noteActions, [], "the learning press fires no trigger")
        XCTAssertEqual(h.log.applied, [], "and selects nothing")
        XCTAssertEqual(h.mappings.statusText, "Build mapped to note C4 on channel 1 (moved from Next cue).")
        XCTAssertEqual(stored(h), ["note:0:60=cue.go:" + Self.sceneID(2)], "the scene keeps one key; the trigger lost the note")
        XCTAssertTrue(h.mappings.canUndo)
        h.mappings.undo()
        XCTAssertEqual(stored(h), lines)
        // A MIDI-006 note learn takes a note from a scene.
        h.mappings.startLearningScene(h.scenes[0])
        send(h, [0x90, 0x40, 0x64])   // E4 → Opening
        h.mappings.startLearningNote(.nextCue)
        send(h, [0x90, 0x40, 0x64])
        XCTAssertEqual(h.mappings.statusText, "Next cue mapped to note E4 on channel 1 (moved from Opening).")
        XCTAssertNil(h.mappings.sceneControl(for: h.scenes[0]))
    }

    func testSceneLearnTimesOutAndDeleteUsesUndo() throws {
        let h: Harness = try makeHarness(lines: ["pc:3:7=cue.go:" + Self.sceneID(1)])
        defer { cleanUp(h) }
        h.mappings.startLearningScene(h.scenes[1])
        h.log.now += MIDILearnSession<String>.timeoutNanoseconds
        h.log.timeouts.last?()
        XCTAssertFalse(h.mappings.isLearning)
        XCTAssertEqual(h.mappings.statusText, MIDIMappingCoordinator.timedOutText)
        XCTAssertEqual(h.mappings.sceneRows.map { (row: MIDISceneRow) -> String in row.control }, ["Program 7 · Ch 4"])
        h.mappings.deleteSceneMapping(h.scenes[0])
        XCTAssertNil(stored(h))
        XCTAssertFalse(h.mappings.isInputClientRegistered, "no mappings, no learn: no input client")
        h.mappings.undo()
        XCTAssertEqual(stored(h), ["pc:3:7=cue.go:" + Self.sceneID(1)])
    }
}
