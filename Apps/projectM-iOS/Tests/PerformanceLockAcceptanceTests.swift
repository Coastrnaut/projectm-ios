// PerformanceLockAcceptanceTests.swift — SHOW-015-T07, T08 (US1, US2; R1-R5; S1-S3): the roadmap acceptance "Lock
// blocks delete/reorder but blackout remains accessible". The SCN-015 scene lock is the performance lock (research
// SHOW-015-D1): one `AppSettings` over a private defaults suite owns it and is wired into a real show (temporary
// store), a real `PresetCoordinator` (synthetic library, temporary collection and smart stores) and a real
// `LibraryBackupCoordinator` (temporary folders), as `AppCoordinator.connectSceneLock()` does. Every attempt goes
// through the coordinator API the UI calls. Blackout runs on an `ExternalDisplayCoordinator` with injected frame
// times. No clock, no simulator UI.
import Foundation
import LibraryBackup
import PresentationLifecycle
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import projectM_iOS

@MainActor
final class PerformanceLockAcceptanceTests: XCTestCase {
    final class FakeLoader: PresetLoading {
        func load(_ preset: IndexedPreset) async throws {}
    }

    @MainActor
    private final class Harness {
        let id = UUID().uuidString
        let root: URL
        let defaults: UserDefaults
        let settings: AppSettings
        let show: ShowCoordinator
        let presets: PresetCoordinator
        let backup: LibraryBackupCoordinator
        var announced: [String] = []

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("SHOW015-\(id)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defaults = try XCTUnwrap(UserDefaults(suiteName: "SHOW015-\(id)"))
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            show = ShowCoordinator(store: ShowStore(directory: root.appendingPathComponent("Show", isDirectory: true)),
                                   registry: try SceneArchiveService.appRegistry())
            let presetsFolder: URL = root.appendingPathComponent("Presets", isDirectory: true)
            presets = PresetCoordinator(store: FavoritesStore(defaults: defaults), settings: settings, loader: FakeLoader(),
                                        collections: PresetCollectionStore(directory: presetsFolder),
                                        tags: PresetTagStore(directory: presetsFolder),
                                        smart: PresetSmartCollectionStore(directory: presetsFolder))
            presets.attach(try Self.library())
            backup = LibraryBackupCoordinator(folders: LibraryFolders(root: root.appendingPathComponent("Library", isDirectory: true)),
                                              defaults: defaults,
                                              temporaryRoot: root.appendingPathComponent("Temp", isDirectory: true))
            // AppCoordinator.connectSceneLock
            show.sceneLock = settings.sceneLock
            presets.sceneLock = settings.sceneLock
            backup.sceneLock = settings.sceneLock
            show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in [] }
            show.announce = { (_: String) in }
            settings.sceneLock.announce = { [unowned self] (text: String) -> Void in self.announced.append(text) }
        }

        private static func record(_ name: String) -> [String: Any] {
            ["id": "frontend-uwp/\(name).milk", "name": name, "author": "A", "source": "included", "folder": [String](),
             "path": "frontend-uwp/\(name).milk", "hash": String(repeating: "0", count: 40)]
        }

        private static func library() throws -> PresetLibrary {
            let records: [[String: Any]] = ["Alpha", "Beta", "Gamma"].map(record)
            let packs: [[String: Any]] = [["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l",
                                           "presetCount": 3, "authors": [String](), "locked": false]]
            return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                     packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
        }

        func preset(_ name: String) throws -> IndexedPreset {
            try XCTUnwrap(presets.library?.presets.first { (preset: IndexedPreset) -> Bool in preset.name == name }, name)
        }

        /// Three cues, a folder, two collections (the first with three presets) and one smart collection.
        func load() throws {
            for index in 1...3 {
                let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false,
                                    glowIntensity: 0.5, glowRadius: 0.02, glowThreshold: 0.5, text: .default, photoID: nil, videoID: nil)
                XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Scene \(index)"),
                                            label: "Cue \(index)"))
            }
            XCTAssertNotNil(show.createFolder(named: "Set A", in: nil))
            let first = try XCTUnwrap(presets.createCollection(named: "Friday"))
            XCTAssertNotNil(presets.createCollection(named: "Saturday"))
            for name in ["Alpha", "Beta", "Gamma"] {
                XCTAssertEqual(presets.addToCollection(try preset(name), first.id), .added)
            }
            XCTAssertNotNil(presets.createSmartCollection(named: "Calm", match: .all,
                                                          conditions: [PresetSmartCondition(.pack, ["included"])]))
        }

        /// The state the lock protects: cue order, folders, collections with their order and members, smart collections.
        struct State: Equatable {
            var cues: [ShowCue]
            var folders: SceneFolderTree
            var collections: [PresetCollection]
            var smart: [PresetSmartCollection]
        }

        var state: State {
            State(cues: show.list.cues, folders: show.list.folders, collections: presets.collections, smart: presets.smartCollections)
        }

        /// SHOW-015-S1: the eight representative delete and reorder attempts.
        func attemptDeletesAndReorders() throws {
            let cues: [ShowCue] = show.list.cues
            let folder: SceneFolder = try XCTUnwrap(show.list.folders.children(of: nil).first)
            let friday: PresetCollection = try XCTUnwrap(presets.collections.first)
            let smart: PresetSmartCollection = try XCTUnwrap(presets.smartCollections.first)
            show.remove(cues[0].id)                                                       // 1. cue delete
            show.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)                     // 2. cue reorder
            _ = show.deleteFolder(folder.id)                                              // 3. folder delete
            presets.moveCollections(fromOffsets: IndexSet(integer: 0), toOffset: 2)       // 4. collection reorder
            presets.movePresets(in: friday.id, fromOffsets: IndexSet(integer: 0), toOffset: 3)   // 5. preset reorder
            presets.removeFromCollection([try preset("Beta")], friday.id)                 // 6. Remove from Collection
            presets.deleteSmartCollection(smart.id)                                       // 7. smart collection delete
            presets.deleteCollection(friday.id)                                           // 8. collection delete
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: "SHOW015-\(id)")
        }
    }

    /// S1, S2 (US1): locked, the eight delete/reorder attempts and Erase/Restore are refused and nothing changes; each
    /// refusal reaches the lock's choke point and the screens' messages.
    func testTheLockRefusesDeletesReordersEraseAndRestore() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        h.settings.sceneLock.lock()
        XCTAssertTrue(h.presets.isCollectionEditLocked, "the collection screens hide their gestures")
        XCTAssertTrue(h.show.isEditLocked, "the show editor and Scene Folders hide theirs")
        let before: Harness.State = h.state

        try h.attemptDeletesAndReorders()
        XCTAssertEqual(h.state, before, "cues, folders and collections are unchanged")
        XCTAssertEqual(h.presets.collectionsMessage, SceneLock.refusalMessage)
        XCTAssertEqual(h.show.editorMessage, SceneLock.refusalMessage)

        // Storage: Erase Data… and Restore from Backup… (R3).
        let erase: LibraryEraseCoordinator = h.backup.erase
        XCTAssertFalse(erase.canStart, "Erase Data… is disabled")
        erase.openSheet()
        XCTAssertFalse(erase.showSheet, "no erase sheet")
        erase.selection = [.scenes]
        erase.requestErase()   // a sheet left open when the lock turned on
        XCTAssertNil(erase.pending)
        XCTAssertNil(LibraryEraseRequestStore(root: h.backup.folders.root).pending, "no erase recorded")
        XCTAssertTrue(h.backup.isRestoreLocked, "Restore from Backup… is disabled")
        XCTAssertFalse(h.backup.restoreTapped(), "no file picker")
        h.backup.requestRestore()
        XCTAssertFalse(h.backup.isRestorePending, "no restore recorded")
        XCTAssertEqual(h.backup.message, SceneLock.refusalMessage)

        XCTAssertEqual(h.settings.sceneLock.refusals, 12, "8 gestures + 2 erase + 2 restore reached the choke point")
        XCTAssertEqual(h.announced.last, SceneLock.refusalMessage, "VoiceOver hears the refusal")
    }

    /// S1 (US3): unlocked, the same attempts succeed (and Erase/Restore open again).
    func testUnlockedTheSameDeletesAndReordersWork() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        h.settings.sceneLock.lock()
        h.settings.sceneLock.unlock()   // after the confirmation (SceneUnlockButtons)
        let before: Harness.State = h.state

        try h.attemptDeletesAndReorders()
        XCTAssertEqual(h.show.list.cues.count, before.cues.count - 1, "a cue was deleted")
        XCTAssertTrue(h.show.list.folders.children(of: nil).isEmpty, "the folder was deleted")
        XCTAssertEqual(h.presets.collections.map(\.name), ["Saturday"], "Friday was reordered and then deleted")
        XCTAssertTrue(h.presets.smartCollections.isEmpty, "the smart collection was deleted")
        XCTAssertTrue(h.backup.erase.canStart)
        h.backup.erase.openSheet()
        XCTAssertTrue(h.backup.erase.showSheet)
        XCTAssertTrue(h.backup.restoreTapped(), "the file picker opens")
        XCTAssertEqual(h.settings.sceneLock.refusals, 0)
        XCTAssertNil(h.presets.collectionsMessage)
    }

    /// The reorder alone, unlocked: proves the reorder attempts above really move things when allowed.
    func testUnlockedReordersMoveCuesCollectionsAndPresets() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        let cues: [ShowCue] = h.show.list.cues
        let friday: PresetCollection = try XCTUnwrap(h.presets.collections.first)
        h.show.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        h.presets.moveCollections(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        h.presets.movePresets(in: friday.id, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(h.show.list.cues.map(\.id), [cues[1].id, cues[2].id, cues[0].id])
        XCTAssertEqual(h.presets.collections.map(\.name), ["Saturday", "Friday"])
        XCTAssertEqual(h.presets.collectionListing(friday.id).map(\.name), ["Beta", "Gamma", "Alpha"])
    }

    /// S3 (US2; R5): locked, the emergency blackout and its restore, Go to cue and Next, Reduce flashing, additive
    /// collection edits and Cancel Erase all act, and none of them consults the lock.
    func testEmergencyControlsStillActWhileLocked() throws {
        let h = try Harness()
        defer { h.cleanUp() }
        try h.load()
        var applied: [String] = []
        h.show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            applied.append(document.id)
            return []
        }
        // A pending erase recorded before the lock (Cancel must stay).
        h.backup.erase.openSheet()
        h.backup.erase.selection = [.collections]
        h.backup.erase.requestErase()
        XCTAssertNotNil(h.backup.erase.pending)
        h.settings.sceneLock.lock()

        // Blackout (SHOW-014 emergency button, then OUT-010's Restore).
        let output = ExternalDisplayCoordinator()
        output.usesDisplayLink = false
        XCTAssertTrue(output.blackoutPhase.offersEmergencyBlackout, "the emergency button is offered while locked")
        EmergencyBlackoutButton.trigger(output)
        XCTAssertEqual(output.blackoutPhase, .blackedOut, "blacked out while locked")
        output.setBlackout(false)
        for _ in 0..<66 { output.advanceFrame(frameTime: 1.0 / 60) }
        XCTAssertEqual(output.blackoutPhase, .live, "restored while locked")

        // Go to cue and Next (the transport).
        let cues: [ShowCue] = h.show.list.cues
        h.show.go(to: cues[2].id)
        h.show.previous()
        XCTAssertEqual(applied, [cues[2].sceneID, cues[1].sceneID], "each step applied its scene")

        // Reduce flashing (the safety section is never disabled).
        let flashing: Bool = h.settings.reduceFlashing
        h.settings.reduceFlashing.toggle()
        XCTAssertNotEqual(h.settings.reduceFlashing, flashing, "Reduce flashing switched while locked")

        // Additive collection edits and Cancel Erase (research SHOW-015-D4, D5).
        let sunday = try XCTUnwrap(h.presets.createCollection(named: "Sunday"))
        XCTAssertEqual(h.presets.addToCollection(try h.preset("Alpha"), sunday.id), .added)
        h.backup.erase.cancelErase()
        XCTAssertNil(h.backup.erase.pending, "Cancel Erase works while locked")

        XCTAssertEqual(h.settings.sceneLock.refusals, 0, "no emergency control consults the lock")
        XCTAssertTrue(h.settings.sceneLock.isLocked)
    }
}
