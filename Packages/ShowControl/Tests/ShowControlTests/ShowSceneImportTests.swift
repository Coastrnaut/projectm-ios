// ShowSceneImportTests.swift — FILE-004-T11, T13, T14 (specs/111-file-004-import-conflict-resolver;
// FILE-004-R1-R7, R10, S1-S5): importing scenes into the show's folder with Skip, Keep both or Replace
// per duplicate scene ID. Derived IDs are fixed values; Keep both rewrites the scene ID and adds a cue
// with a derived ID; Replace keeps every cue; Skip changes no byte; a fault at any file operation
// leaves the folder byte-for-byte as before; a simulated crash at any operation is recovered to the
// state before (prepared) or after (committed); a changed show is detected. A few scenes each.
import Foundation
import LocalPortability
import SceneFormat
import ShowControl
@testable import ShowStorage
import XCTest

/// Throws at the n-th file operation (0-based), once; `interrupt` makes it a simulated crash.
final class SceneImportFault: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let failAt: Int
    private let interrupt: Bool
    private(set) var fired = false
    /// Journal writes performed before the fault fired (2 = the commit was written).
    private(set) var journalWritesBefore = 0

    init(failAt: Int, interrupt: Bool = false) {
        self.failAt = failAt
        self.interrupt = interrupt
    }

    func check(_ operation: ShowSceneImportFileOperation, _ url: URL) throws {
        let shouldFail: Bool = lock.withLock {
            defer { count += 1 }
            if count == failAt && !fired {
                fired = true
                return true
            }
            if !fired && operation == .write && url.lastPathComponent == ShowStore.importJournalFileName { journalWritesBefore += 1 }
            return false
        }
        guard shouldFail else { return }
        if interrupt { throw ShowSceneImportInterruption() }
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

final class ShowSceneImportTests: XCTestCase {
    typealias Planner = ShowSceneImportPlanner

    // MARK: - Fixtures

    private func scene(_ n: Int, variant: Int = 0, name: String? = nil) -> SceneDocument {
        let content: SceneLayerContent = variant == 0 ? .linearSpectrum : .circularSpectrum
        return SceneDocument(id: ShowFixtures.sceneID(n), name: name ?? "Scene \(n)",
                             layers: [SceneLayer(instance: 1, content: content, values: variant > 1 ? ["rate": Double(variant)] : [:])])
    }

    /// The five-cue show with scenes 1…5 stored.
    private func makeStore() throws -> ShowStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShowSceneImportTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let store = ShowStore(directory: folder)
        for n in 1...5 { try store.saveScene(scene(n)) }
        try store.save(try ShowFixtures.fiveCues())
        return store
    }

    /// Relative path → SHA-256 of every file, plus every directory, under the show folder.
    private func snapshot(_ store: ShowStore) -> [String: String] {
        var result: [String: String] = [:]
        let root = store.directory.standardizedFileURL.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(atPath: root) else { return result }
        while let relative = walker.nextObject() as? String {
            let path = (root as NSString).appendingPathComponent(relative)
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            if isFolder.boolValue {
                result[relative + "/"] = "dir"
            } else {
                result[relative] = PortableSHA256.hex((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data())
            }
        }
        return result
    }

    /// Scene 3 changed (Replace), scene 4 changed (Skip by override), scene 5 changed (Keep both by
    /// default), scene 9 new.
    private func mixedIncoming() -> [SceneDocument] {
        [scene(3, variant: 1), scene(4, variant: 1), scene(5, variant: 2), scene(9)]
    }

    private let mixedOverrides: [String: ShowSceneImportChoice] = [ShowFixtures.sceneID(3): .replace, ShowFixtures.sceneID(4): .skip]

    // MARK: - Plan kinds

    func testPlanClassifiesNewIdenticalAndConflictingScenes() throws {
        let store = try makeStore()
        let plan = store.planSceneImport([scene(2), scene(3, variant: 1), scene(9)])
        XCTAssertNil(plan.refusal)
        XCTAssertEqual(plan.entries.map(\.kind), [.identical, .idConflict(existingName: "Scene 3", cueCount: 1), .new])
        XCTAssertEqual(plan.entries.map(\.choice), [nil, .keepBoth, nil])
        XCTAssertNil(plan.entries[0].install)
        XCTAssertEqual(plan.entries[2].install?.sceneID, ShowFixtures.sceneID(9))
        XCTAssertEqual(plan.conflictCount, 1)
    }

    // MARK: - Keep both rewrites the ID; Replace keeps the cues; Skip changes nothing

    func testKeepBothRewritesTheSceneIDAndAddsACueWithADerivedID() throws {
        let store = try makeStore()
        let incoming = scene(3, variant: 1)
        let storedBytes = try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(3)))
        let plan = store.planSceneImport([incoming])
        let sha = PortableSHA256.hex(incoming.encoded())
        let expectedID = Planner.derivedSceneID(incomingID: incoming.id, contentSHA256: sha, avoiding: [])
        XCTAssertEqual(plan.actions.map(\.sceneID), [expectedID])
        XCTAssertEqual(plan.actions.map(\.name), ["Scene 3 copy"])
        let cueID = Planner.derivedCueID(sceneID: expectedID, avoiding: [])
        XCTAssertEqual(plan.actions.first?.cueID, cueID)

        guard case let .installed(list, scenes) = store.installImportedScenes([incoming], plan: plan) else { return XCTFail() }
        XCTAssertEqual(scenes.map(\.id), [expectedID])
        XCTAssertEqual(try store.scene(expectedID).document.layers, incoming.layers, "everything but id and name kept")
        XCTAssertEqual(try store.scene(expectedID).document.name, "Scene 3 copy")
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(3))), storedBytes, "the stored scene is untouched")
        XCTAssertEqual(list.cues.count, 6)
        XCTAssertEqual(list.cues.last?.id, cueID)
        XCTAssertEqual(list.cues.last?.sceneID, expectedID, "the new cue refers to the rewritten ID")
        XCTAssertEqual(list.cues.last?.label, "Scene 3 copy")
        let loaded = store.load()
        XCTAssertEqual(loaded.list.encoded(), list.encoded())
        XCTAssertTrue(loaded.unreadableScenes.isEmpty, "every cue resolves")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.importStagingFolder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.importJournalFile.path))
    }

    func testReplaceKeepsTheSceneIDAndEveryCue() throws {
        let store = try makeStore()
        let showBefore = try Data(contentsOf: store.showFile)
        let incoming = scene(3, variant: 1, name: "Imported Three")
        let plan = store.planSceneImport([incoming], defaultChoice: .replace)
        XCTAssertEqual(plan.actions, [ShowSceneImportAction(sceneID: incoming.id, name: "Imported Three", replaces: true, cueID: nil)])
        XCTAssertEqual(plan.replaceCount, 1)
        guard case let .installed(list, _) = store.installImportedScenes([incoming], plan: plan) else { return XCTFail() }
        XCTAssertEqual(Data(list.encoded()), showBefore, "no cue added or changed")
        XCTAssertEqual(try Data(contentsOf: store.showFile), showBefore)
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(incoming.id)), Data(incoming.encoded()), "the whole new scene")
        XCTAssertEqual(store.load().list.cues.filter { (cue: ShowCue) -> Bool in cue.sceneID == incoming.id }.count, 1)
    }

    func testSkipLeavesEveryByteAsItWas() throws {
        let store = try makeStore()
        let before = snapshot(store)
        let plan = store.planSceneImport([scene(3, variant: 1)], defaultChoice: .skip)
        XCTAssertEqual(store.installImportedScenes([scene(3, variant: 1)], plan: plan), .refused(ShowSceneImportText.nothingToInstall))
        XCTAssertEqual(snapshot(store), before)
    }

    func testMixedChoicesInOneImport() throws {
        let store = try makeStore()
        let four = try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(4)))
        let five = try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(5)))
        let plan = store.planSceneImport(mixedIncoming(), overrides: mixedOverrides)
        XCTAssertEqual(plan.entries.map(\.choice), [.replace, .skip, .keepBoth, nil])
        guard case let .installed(list, scenes) = store.installImportedScenes(mixedIncoming(), plan: plan) else { return XCTFail() }
        XCTAssertEqual(scenes.count, 3)
        XCTAssertEqual(list.cues.count, 7, "Keep both and the new scene add one cue each")
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(4))), four)
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(ShowFixtures.sceneID(5))), five)
        XCTAssertEqual(try store.scene(ShowFixtures.sceneID(3)).document, scene(3, variant: 1))
        XCTAssertEqual(store.storedSceneIDs().count, 7)
    }

    func testReplaceFallsBackForASecondSceneWithTheSameID() throws {
        let store = try makeStore()
        let plan = store.planSceneImport([scene(3, variant: 1), scene(3, variant: 2)], defaultChoice: .replace)
        XCTAssertEqual(plan.entries.map(\.fellBack), [false, true])
        XCTAssertEqual(plan.actions.map(\.replaces), [true, false])
        XCTAssertEqual(plan.actions.map(\.name), ["Scene 3", "Scene 3 copy"])
    }

    // MARK: - No partial overwrite

    func testAFaultAtEveryFileOperationLeavesTheFolderUnchanged() throws {
        let reference = try makeStore()
        let referencePlan = reference.planSceneImport(mixedIncoming(), overrides: mixedOverrides)
        guard case .installed = reference.installImportedScenes(mixedIncoming(), plan: referencePlan) else { return XCTFail() }
        let success = snapshot(reference)
        var faults = 0
        for step in 0..<40 {
            let store = try makeStore()
            let before = snapshot(store)
            let plan = store.planSceneImport(mixedIncoming(), overrides: mixedOverrides)
            let fault = SceneImportFault(failAt: step)
            let outcome = store.installImportedScenes(mixedIncoming(), plan: plan, fault: { (op: ShowSceneImportFileOperation, url: URL) throws in
                try fault.check(op, url)
            })
            guard fault.fired else {
                guard case .installed = outcome else { return XCTFail("step \(step): \(outcome)") }
                XCTAssertEqual(snapshot(store), success)
                break
            }
            if fault.journalWritesBefore >= 2 {
                // A step after the commit failed: the scenes are in place; recovery finishes the rest.
                guard case .installed = outcome else { return XCTFail("step \(step): \(outcome)") }
                store.recoverInterruptedSceneImport()
                XCTAssertEqual(snapshot(store), success, "step \(step)")
                continue
            }
            faults += 1
            XCTAssertEqual(outcome, .refused(ShowSceneImportText.nothingInstalled(ShowSceneImportText.saveFailed)), "step \(step)")
            XCTAssertEqual(snapshot(store), before, "step \(step)")
        }
        // staging, 3 writes, backup folder, prepared journal, 1 backup move, 3 moves, the commit.
        XCTAssertGreaterThanOrEqual(faults, 11)
    }

    func testACrashAtEveryFileOperationIsRecoveredToBeforeOrAfter() throws {
        let reference = try makeStore()
        let referencePlan = reference.planSceneImport(mixedIncoming(), overrides: mixedOverrides)
        guard case .installed = reference.installImportedScenes(mixedIncoming(), plan: referencePlan) else { return XCTFail() }
        let success = snapshot(reference)
        var rolledBack = 0
        var rolledForward = 0
        for step in 0..<40 {
            let store = try makeStore()
            let before = snapshot(store)
            let plan = store.planSceneImport(mixedIncoming(), overrides: mixedOverrides)
            let fault = SceneImportFault(failAt: step, interrupt: true)
            _ = store.installImportedScenes(mixedIncoming(), plan: plan, fault: { (op: ShowSceneImportFileOperation, url: URL) throws in
                try fault.check(op, url)
            })
            guard fault.fired else { break }
            // The next launch.
            XCTAssertEqual(store.planSceneImport([scene(9)]).refusal == .interruptedImport,
                           FileManager.default.fileExists(atPath: store.importJournalFile.path))
            store.recoverInterruptedSceneImport()
            let after = snapshot(store)
            if fault.journalWritesBefore >= 2 {
                rolledForward += 1
                XCTAssertEqual(after, success, "step \(step)")
            } else {
                rolledBack += 1
                XCTAssertEqual(after, before, "step \(step)")
            }
            XCTAssertTrue(store.load().unreadableScenes.isEmpty, "step \(step): every cue resolves")
        }
        XCTAssertGreaterThanOrEqual(rolledBack, 11)
        XCTAssertGreaterThanOrEqual(rolledForward, 2)
    }

    // MARK: - Deterministic IDs

    func testDerivedIDsAreFixedValues() throws {
        // Fixed seeds → fixed UUIDs (the same in every process; version nibble 8, variant 10).
        let id = Planner.derivedUUID("FILE-004|scene|5CE7E000-0000-4000-8000-000000000003|abc|1").uuidString
        XCTAssertEqual(id, Planner.derivedUUID("FILE-004|scene|5CE7E000-0000-4000-8000-000000000003|abc|1").uuidString)
        XCTAssertEqual(id, Self.fixedSceneID)
        XCTAssertTrue(ShowCueList.isSceneID(id))
        XCTAssertEqual(Array(id)[14], "8")
        XCTAssertTrue(["8", "9", "A", "B"].contains(Array(id)[19]))

        let store = try makeStore()
        let first = store.planSceneImport([scene(3, variant: 1)])
        let second = store.planSceneImport([scene(3, variant: 1)])
        XCTAssertEqual(first, second)
        let other = store.planSceneImport([scene(3, variant: 2)])
        XCTAssertNotEqual(other.actions.map(\.sceneID), first.actions.map(\.sceneID), "different content, different ID")
        XCTAssertNotEqual(other.actions.map(\.cueID), first.actions.map(\.cueID))
    }

    static let fixedSceneID = "440A1BDB-628F-807C-A1B0-1875044D5EEB"

    // MARK: - Re-validation and refusals

    func testAChangedStoredSceneIsDetectedWithNothingWritten() throws {
        let store = try makeStore()
        let plan = store.planSceneImport([scene(3, variant: 1)], defaultChoice: .replace)
        try store.saveScene(scene(3, variant: 3))   // meanwhile
        let before = snapshot(store)
        guard case let .changed(fresh) = store.installImportedScenes([scene(3, variant: 1)], plan: plan) else { return XCTFail() }
        XCTAssertEqual(fresh.defaultChoice, .replace)
        XCTAssertEqual(snapshot(store), before)
    }

    func testAnUnreadableShowIsRefused() throws {
        let store = try makeStore()
        try Data("{not a show".utf8).write(to: store.showFile)
        let before = snapshot(store)
        let plan = store.planSceneImport([scene(9)])
        XCTAssertEqual(plan.refusal, .showUnreadable)
        XCTAssertEqual(store.installImportedScenes([scene(9)], plan: plan),
                       .refused(ShowSceneImportText.nothingInstalled(ShowSceneImportRefusal.showUnreadable.message)))
        XCTAssertEqual(snapshot(store), before)
    }
}
