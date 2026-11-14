// MIDI-012-T07, T09, T11-T13: MIDI mapping profiles in the app with a scripted MIDI system and a temporary profiles
// folder (specs/171-midi-012-profiles, contract P2).
// * The row's acceptance (S1): every line kind → Save Current → reopened store → exported file → import → Apply leaves
//   `settings.midi.mappings` byte-identical (UTF-8) and in order, and the CC, trigger and scene lists drive as before.
// * Apply is one Undo step restoring the previous list exactly, announced on the `.midi` lane (S3); import never
//   applies; unread lines survive a later learn (R7); refusals change nothing; an unreadable store is never
//   overwritten (S2); the device suggestion (R8); backup and erase policy (S4).
import Foundation
import LibraryBackup
import ParameterGraph
import PerformanceControl
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class MIDIProfilesCoordinatorTests: XCTestCase {
    @MainActor private final class AnnouncementLog { var texts: [String] = [] }

    private struct Harness {
        let defaults: UserDefaults
        let suite: String
        let endpoints: ScriptedMIDIEndpointProvider
        let scheduler: ManualMIDIScheduler
        let inputProvider: ScriptedMIDIInputProvider
        let input: MIDIInputCoordinator
        let mappings: MIDIMappingCoordinator
        let profiles: MIDIProfilesCoordinator
        let announcements: AnnouncementLog
        let root: URL
    }

    static let keysID: Int32 = 0x4B455953
    private static let records: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: keysID, direction: .source, displayName: "Fake Keys", endpointName: "Keys Port",
                           entityName: "Keys Entity", deviceName: "Fake Keys"),
    ]

    /// Every line kind in a non-canonical order (CC on channels 1 and 16, controller 119, triggers, scenes, unknown).
    static let everyKind: [String] = [
        "note:15:60=blackout;mode=hold",
        "cc:0:7=effect.bloom.intensity",
        "cc:15:119=effect.bloom.radius;curve=log:9.0;invert=1",
        "ccbtn:3:64=transport.toggle",
        "rt:start=transport.play", "rt:stop=transport.pause",
        "pc:0:5=cue.go:5CE7E000-0000-4000-8000-00000000000A",
        "note:9:36=cue.go:5CE7E000-0000-4000-8000-00000000000B",
        "pc:*:*=cue.position",
        "osc:/projectm/glow=effect.bloom.intensity",
        "cc:0:200=effect.bloom.knee",
    ]

    private func makeHarness(lines: [String] = [], root existing: URL? = nil) throws -> Harness {
        let suite: String = "MIDIProfilesCoordinatorTests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: AppSettings.midiEnabledKey)
        if !lines.isEmpty { defaults.set(lines, forKey: MIDIMappingCoordinator.mappingsKey) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let endpoints = ScriptedMIDIEndpointProvider(records: [])
        let scheduler = ManualMIDIScheduler()
        let discovery = MIDIDiscoveryCoordinator(settings: settings,
                                                 discovery: MIDIEndpointDiscovery(provider: endpoints, scheduler: scheduler.scheduler))
        _ = scheduler.runAll()
        let inputProvider = ScriptedMIDIInputProvider()
        let input = MIDIInputCoordinator(service: MIDIInputService(provider: inputProvider), discovery: discovery,
                                         drivesDisplayLink: false)
        let announcements = AnnouncementLog()
        let mappings = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: discovery, defaults: defaults,
            announce: { (text: String) -> Void in announcements.texts.append(text) })
        let root: URL = existing ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("MIDIProfilesCoordinatorTests-" + UUID().uuidString, isDirectory: true)
        let store = MIDIProfileFileStore(directory: root.appendingPathComponent(LibraryErasePolicy.midiProfilesFolderName, isDirectory: true))
        var next: Int = 0
        let profiles = MIDIProfilesCoordinator(mappings: mappings, store: store,
                                               makeID: { () -> String in next += 1; return "P" + String(next) },
                                               temporaryDirectory: root.appendingPathComponent("tmp", isDirectory: true))
        mappings.profiles = profiles
        mappings.open()
        return Harness(defaults: defaults, suite: suite, endpoints: endpoints, scheduler: scheduler, inputProvider: inputProvider,
                       input: input, mappings: mappings, profiles: profiles, announcements: announcements, root: root)
    }

    private func cleanUp(_ h: Harness) {
        h.mappings.close()
        h.defaults.removePersistentDomain(forName: h.suite)
        try? FileManager.default.removeItem(at: h.root)
    }

    private func stored(_ h: Harness) -> [[UInt8]] {
        (h.defaults.stringArray(forKey: MIDIMappingCoordinator.mappingsKey) ?? []).map { (line: String) -> [UInt8] in Array(line.utf8) }
    }

    private func bytes(_ lines: [String]) -> [[UInt8]] {
        lines.map { (line: String) -> [UInt8] in Array(line.utf8) }
    }

    // MARK: S1 — the row's acceptance

    func testProfileRoundTripThroughAFileAndApplyIsByteIdentical() throws {
        let source: Harness = try makeHarness(lines: Self.everyKind)
        defer { cleanUp(source) }
        source.profiles.saveCurrent()
        XCTAssertEqual(source.profiles.rows.map(\.name), ["Profile 1"])
        XCTAssertEqual(source.profiles.rows.first?.inUse, true)
        XCTAssertEqual(source.profiles.rows.first?.accessibilityLabel, "Profile 1, 11 mappings, in use")
        source.profiles.rename(id: "P1", to: "Launch Control")

        // In-store round trip: a new coordinator over the same folder.
        let reopened: Harness = try makeHarness(root: source.root)
        defer { reopened.mappings.close(); reopened.defaults.removePersistentDomain(forName: reopened.suite) }
        let kept: MIDIProfile = try XCTUnwrap(reopened.profiles.list.profiles.first)
        XCTAssertEqual(kept.name, "Launch Control")
        XCTAssertEqual(bytes(kept.lines), bytes(Self.everyKind))

        // Export to a file.
        XCTAssertTrue(source.profiles.prepareExport(id: "P1"))
        XCTAssertTrue(source.profiles.showMover)
        let file: URL = try XCTUnwrap(source.profiles.exportFile)
        XCTAssertEqual(file.lastPathComponent, "Launch Control.pmmidi")
        let exported = try Data(contentsOf: file)
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("link"))
        let shared: URL = source.root.appendingPathComponent("Launch Control.pmmidi")
        try FileManager.default.copyItem(at: file, to: shared)   // the file mover moves it to Files
        source.profiles.exportFinished(.success(shared))
        XCTAssertNil(source.profiles.exportFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path), "nothing left in tmp")

        // Import on another "device" with different mappings: added, not applied.
        let target: Harness = try makeHarness(lines: ["cc:2:1=effect.bloom.knee"])
        defer { cleanUp(target) }
        target.profiles.importFile(at: shared)
        XCTAssertEqual(target.profiles.rows.map(\.name), ["Launch Control"])
        XCTAssertEqual(stored(target), bytes(["cc:2:1=effect.bloom.knee"]), "import never applies")
        XCTAssertEqual(target.profiles.message, "Imported MIDI profile Launch Control. 2 controls, 1 note trigger, 1 button, "
                       + "2 Start/Stop triggers, 3 scene triggers. 2 lines are not used by this version and are kept as they are. "
                       + "Tap Apply to use it.")

        // Apply: the stored list is byte-identical and in order; the lists drive as before.
        let imported: String = try XCTUnwrap(target.profiles.rows.first?.id)
        target.profiles.apply(id: imported)
        XCTAssertEqual(stored(target), bytes(Self.everyKind))
        XCTAssertEqual(target.mappings.bindings.storageLines,
                       ["cc:0:7=effect.bloom.intensity", "cc:15:119=effect.bloom.radius;curve=log:9.0;invert=1"])
        XCTAssertEqual(target.mappings.noteBindings.storageLines,
                       ["note:15:60=blackout;mode=hold", "ccbtn:3:64=transport.toggle", "rt:start=transport.play", "rt:stop=transport.pause"])
        XCTAssertEqual(target.mappings.sceneBindings.storageLines,
                       ["pc:0:5=cue.go:5CE7E000-0000-4000-8000-00000000000A", "note:9:36=cue.go:5CE7E000-0000-4000-8000-00000000000B",
                        "pc:*:*=cue.position"])
        XCTAssertEqual(target.mappings.otherLines, ["osc:/projectm/glow=effect.bloom.intensity", "cc:0:200=effect.bloom.knee"])
        XCTAssertTrue(target.mappings.isInputClientRegistered, "applied bindings receive")
        XCTAssertEqual(target.profiles.rows.first?.inUse, true)
        XCTAssertEqual(target.announcements.texts.last, "Applied MIDI profile Launch Control.")
    }

    // MARK: S3 — one Undo step

    func testApplyIsOneUndoStepRestoringThePreviousListExactly() throws {
        let previous: [String] = ["pc:*:*=cue.position", "zz:unknown", "cc:0:7=effect.bloom.intensity"]   // non-canonical order
        let h: Harness = try makeHarness(lines: previous)
        defer { cleanUp(h) }
        h.profiles.importData(MIDIProfileDocument.encode(name: "Pads", lines: ["note:0:36=cue.next"]))
        XCTAssertFalse(h.mappings.canUndo, "import changes no mapping")
        h.profiles.apply(id: "P1")
        XCTAssertEqual(stored(h), bytes(["note:0:36=cue.next"]))
        XCTAssertTrue(h.mappings.canUndo)
        XCTAssertEqual(h.mappings.statusText, "Applied MIDI profile Pads.")
        h.mappings.undo()
        XCTAssertEqual(stored(h), bytes(previous), "the previous list, verbatim and in order")
        XCTAssertEqual(h.mappings.bindings.storageLines, ["cc:0:7=effect.bloom.intensity"])
        XCTAssertTrue(h.mappings.noteBindings.isEmpty)
        XCTAssertFalse(h.mappings.canUndo, "one step")
    }

    // MARK: R7 — unread lines survive an edit

    func testUnreadLinesSurviveALaterEdit() throws {
        let h: Harness = try makeHarness(lines: ["osc:/x=y", "cc:0:7=effect.bloom.intensity", "cc:0:200=effect.bloom.knee"])
        defer { cleanUp(h) }
        h.mappings.deleteMapping(VisualParameterIDs.bloomIntensity)
        XCTAssertEqual(stored(h), bytes(["osc:/x=y", "cc:0:200=effect.bloom.knee"]), "kept after an edit")
        h.mappings.undo()
        XCTAssertEqual(stored(h), bytes(["cc:0:7=effect.bloom.intensity", "osc:/x=y", "cc:0:200=effect.bloom.knee"]))
    }

    // MARK: S2 — refusals change nothing; an unreadable store is never overwritten

    func testRefusedImportsChangeNothing() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity"])
        defer { cleanUp(h) }
        h.profiles.importData(Data("not a profile".utf8))
        XCTAssertEqual(h.profiles.message, "Could not import: The file is not a projectM MIDI profile.")
        let oversized: URL = h.root.appendingPathComponent("big.pmmidi")
        try FileManager.default.createDirectory(at: h.root, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: MIDIProfileLimits.maxImportBytes + 10).write(to: oversized)
        h.profiles.importFile(at: oversized)
        XCTAssertEqual(h.profiles.message, "Could not import: The file is too large to be a MIDI profile.")
        XCTAssertTrue(h.profiles.rows.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.profiles.store.fileURL.path))
        XCTAssertEqual(stored(h), bytes(["cc:0:7=effect.bloom.intensity"]))
        XCTAssertEqual(h.announcements.texts.count, 2, "refusals are announced")
    }

    func testAnUnreadableStoreIsNeverOverwritten() throws {
        let h: Harness = try makeHarness()
        defer { cleanUp(h) }
        let file: URL = h.profiles.store.fileURL
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data(#"{"format":"org.projectmios.midi-profiles","version":9,"profiles":[]}"#.utf8)
        try newer.write(to: file)
        h.profiles.reload()
        XCTAssertEqual(h.profiles.readError, .newerVersion(9))
        XCTAssertFalse(h.profiles.canSave)
        h.profiles.saveCurrent()
        h.profiles.importData(MIDIProfileDocument.encode(name: "A", lines: []))
        XCTAssertEqual(try Data(contentsOf: file), newer, "untouched")
    }

    // MARK: R8 — the device suggestion; R12 — rename, delete, duplicates, limit

    func testALinkedListedInputIsSuggestedAndNothingAppliesByItself() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity"])
        defer { cleanUp(h) }
        h.profiles.importData(MIDIProfileDocument.encode(name: "Keys", lines: ["note:0:36=cue.next"]))
        XCTAssertTrue(h.profiles.linkTargets.isEmpty, "nothing listed")
        h.endpoints.plug(Self.records)
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.profiles.linkTargets.map(\.name), ["Fake Keys"])
        h.profiles.link(id: "P1", to: try XCTUnwrap(h.profiles.linkTargets.first).endpoint)
        XCTAssertEqual(h.profiles.list.profile(id: "P1")?.link, Self.keysID)
        XCTAssertEqual(h.profiles.rows.first?.accessibilityLabel, "Keys, 1 mapping, linked to Fake Keys")
        XCTAssertEqual(h.profiles.suggestion?.profile.name, "Keys")
        XCTAssertEqual(h.profiles.suggestion?.inputName, "Fake Keys")
        XCTAssertEqual(stored(h), bytes(["cc:0:7=effect.bloom.intensity"]), "a suggestion never applies")
        h.profiles.apply(id: "P1")
        XCTAssertNil(h.profiles.suggestion, "in use: no longer suggested")
        let text: String = String(decoding: try Data(contentsOf: h.profiles.store.fileURL), as: UTF8.self)
        XCTAssertFalse(text.contains("Fake Keys"), "no device name is stored")
        h.endpoints.unplug(uniqueIDs: [Self.keysID])
        _ = h.scheduler.runAll()
        XCTAssertEqual(h.profiles.rows.first?.linkText, MIDIProfilesCoordinator.notConnectedText)
    }

    func testRenameDeleteDuplicatesAndTheLimit() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity"])
        defer { cleanUp(h) }
        h.profiles.saveCurrent()
        h.profiles.saveCurrent()
        XCTAssertEqual(h.profiles.rows.map(\.name), ["Profile 1", "Profile 2"])
        h.profiles.startRename("P2")
        XCTAssertEqual(h.profiles.renameText, "Profile 2")
        h.profiles.renameText = "profile 1"
        h.profiles.finishRename()
        XCTAssertEqual(h.profiles.rows.map(\.name), ["Profile 1", "profile 1 (2)"])
        h.profiles.importData(MIDIProfileDocument.encode(name: "Profile 1", lines: ["cc:0:7=effect.bloom.intensity"]))
        XCTAssertEqual(h.profiles.rows.last?.name, "Profile 1 (3)", "unique ignoring case: “profile 1 (2)” exists")
        XCTAssertTrue(h.profiles.message?.contains("Same mappings as “Profile 1”.") ?? false, h.profiles.message ?? "")
        h.profiles.deleteID = "P3"
        XCTAssertEqual(h.profiles.profileName(h.profiles.deleteID), "Profile 1 (3)")
        h.profiles.confirmDelete()
        XCTAssertEqual(h.profiles.rows.count, 2)
        XCTAssertEqual(h.announcements.texts.last, "Deleted MIDI profile Profile 1 (3).")
        while h.profiles.canSave { h.profiles.saveCurrent() }
        XCTAssertEqual(h.profiles.rows.count, 32)
        h.profiles.importData(MIDIProfileDocument.encode(name: "More", lines: []))
        XCTAssertEqual(h.profiles.message, "Could not import: No more profiles fit (32). Delete one first.")
    }

    // MARK: S4 — backup and erase policy (FILE-005, FILE-011)

    func testProfilesAreNotBackedUpAndTheSettingsEraseRemovesThem() throws {
        let h: Harness = try makeHarness(lines: ["cc:0:7=effect.bloom.intensity"])
        defer { cleanUp(h) }
        h.profiles.saveCurrent()
        XCTAssertEqual(MIDIProfilesCoordinator.folderName, LibraryErasePolicy.midiProfilesFolderName)
        XCTAssertEqual(LibraryErasePolicy.folders(.settings), [MIDIProfilesCoordinator.folderName])
        XCTAssertFalse(LibraryFolders.Folder.allCases.map(\.rawValue).contains(MIDIProfilesCoordinator.folderName),
                       "not a backed-up library folder")
        let inventory = LibraryEraseInventory.measure(root: h.root, settings: [:])
        XCTAssertEqual(inventory.item(.settings).count, 1, "the profiles file counts as one Settings item")
        let plan = LibraryErasePlanner.plan([.settings], root: h.root, settings: [:])
        XCTAssertEqual(plan.folders, [MIDIProfilesCoordinator.folderName])
        XCTAssertFalse(LibraryErasePlanner.plan([.scenes, .presets, .collections, .media, .importedAudio], root: h.root, settings: [:])
            .folders.contains(MIDIProfilesCoordinator.folderName), "only Settings erases them")
    }
}
