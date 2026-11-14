// LibraryEraseFaultTests.swift — FILE-011-T06 (FILE-011-S2, R6): never half-erased.
// * A fault at each file operation before the commit point leaves every library folder, the settings
//   and the work folder exactly as before, and reports the failure.
// * A fault after the commit leaves a committed journal that the next launch finishes.
// * A kill before the commit (a prepared journal, folders moved aside) is rolled back at the next launch
//   and the still-pending request then runs from a consistent library.
// * A request from a newer version, or naming an unknown category, erases nothing.
import Foundation
import PresetLibrary
import XCTest
@testable import LibraryBackup

final class LibraryEraseFaultTests: XCTestCase {
    private struct Injected: Error {}

    private let everything: Set<LibraryEraseCategory> = Set(LibraryEraseCategory.allCases)

    /// The operations of an uninterrupted erase of everything, in order.
    private func operations() throws -> [(LibraryEraser.FileOperation, String)] {
        let sandbox = try EraseFixtures.sandbox(self, "ops")
        var seen: [(LibraryEraser.FileOperation, String)] = []
        try EraseFixtures.erase(everything, in: sandbox, defaults: EraseFixtures.Defaults()) { (eraser: LibraryEraser) in
            eraser.observer = { (operation: LibraryEraser.FileOperation, url: URL) in seen.append((operation, url.lastPathComponent)) }
        }
        return seen
    }

    func testAFaultAtEveryOperationBeforeTheCommitChangesNothing() throws {
        let all = try operations()
        let commit = try XCTUnwrap(all.lastIndex { (entry: (LibraryEraser.FileOperation, String)) -> Bool in
            entry.0 == .write && entry.1 == LibraryEraser.journalFileName
        })
        XCTAssertGreaterThan(commit, 3, "journal, trash, folder moves, commit")
        for index in 0...commit {
            let sandbox = try EraseFixtures.sandbox(self, "fault\(index)")
            let defaults = EraseFixtures.Defaults()
            let before = LibraryTreeSnapshot.take(sandbox.erasableRoots + sandbox.untouchable)
            let records = try EraseFixtures.records(sandbox, defaults)
            var count = 0
            let note = try EraseFixtures.erase(everything, in: sandbox, defaults: defaults) { (eraser: LibraryEraser) in
                eraser.fault = { (_: LibraryEraser.FileOperation, _: URL) throws in
                    defer { count += 1 }
                    if count == index { throw Injected() }
                }
            }
            XCTAssertEqual(note, LibraryEraseResultNote(erased: false, message: LibraryEraseText.failed), "fault at \(index): \(all[index])")
            XCTAssertEqual(LibraryTreeSnapshot.take(sandbox.erasableRoots + sandbox.untouchable).differences(from: before), [], "fault at \(index)")
            XCTAssertEqual(try EraseFixtures.records(sandbox, defaults), records, "fault at \(index)")
            XCTAssertEqual(defaults.values, EraseFixtures.settings, "no key removed before the commit (fault at \(index))")
            XCTAssertFalse(LibraryEraser(root: sandbox.root).hasInterruptedErase)
            XCTAssertNil(LibraryEraseRequestStore(root: sandbox.root).pendingRequest, "the request is removed after the attempt")
        }
    }

    func testAFaultAfterTheCommitIsFinishedAtTheNextLaunch() throws {
        let sandbox = try EraseFixtures.sandbox(self, "after")
        let defaults = EraseFixtures.Defaults()
        let note = try EraseFixtures.erase([.scenes, .collections], in: sandbox, defaults: defaults) { (eraser: LibraryEraser) in
            eraser.fault = { (operation: LibraryEraser.FileOperation, url: URL) throws in
                if operation == .remove && url.lastPathComponent == LibraryEraser.trashFolderName { throw Injected() }
            }
        }
        XCTAssertEqual(note?.erased, true, "the commit point was passed")
        XCTAssertTrue(LibraryEraser(root: sandbox.root).hasInterruptedErase, "the committed journal stays")
        XCTAssertNil(defaults.values[LibrarySettingsPolicy.favoritesKey])
        let relaunch = LibraryEraseLaunch.run(root: sandbox.root, settings: defaults.values) { (keys: [String]) in defaults.remove(keys) }
        XCTAssertNil(relaunch, "no request was pending")
        XCTAssertFalse(LibraryEraser(root: sandbox.root).hasInterruptedErase)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.root.appendingPathComponent("LibraryErase/trash").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.folder("Show").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.folder("UserPresets").path))
    }

    func testAKillBeforeTheCommitIsRolledBackAndTheRequestRunsAgain() throws {
        let sandbox = try EraseFixtures.sandbox(self, "kill")
        let defaults = EraseFixtures.Defaults()
        let chosen: Set<LibraryEraseCategory> = [.presets, .media]
        try LibraryEraseRequestStore(root: sandbox.root).save(chosen)
        // The state a kill leaves after "prepared" and one folder move.
        let eraser = LibraryEraser(root: sandbox.root)
        let plan = LibraryErasePlanner.plan(chosen, root: sandbox.root, settings: defaults.values)
        try FileManager.default.createDirectory(at: eraser.trash, withIntermediateDirectories: true)
        let journal = try JSONEncoder().encode(LibraryEraser.Journal(phase: .prepared, plan: plan))
        try journal.write(to: eraser.journalFile)
        try FileManager.default.moveItem(at: sandbox.folder("UserPresets"), to: eraser.trash.appendingPathComponent("UserPresets"))
        XCTAssertTrue(eraser.recover { (keys: [String]) in defaults.remove(keys) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.folder("UserPresets").path), "rolled back")
        XCTAssertEqual(defaults.values, EraseFixtures.settings)
        // The next launch: the request still pending runs.
        let before = try EraseFixtures.records(sandbox, defaults)
        let note = LibraryEraseLaunch.run(root: sandbox.root, settings: defaults.values) { (keys: [String]) in defaults.remove(keys) }
        XCTAssertEqual(note, LibraryEraseResultNote(erased: true, message: "Erased: My Presets, photos and videos."))
        let after = try EraseFixtures.records(sandbox, defaults)
        XCTAssertTrue(after.digests.keys.allSatisfy { (key: String) -> Bool in !key.hasPrefix("preset/") && !key.hasPrefix("photo/") })
        XCTAssertEqual(after.digests["show"], before.digests["show"])
        XCTAssertEqual(LibraryEraseRequestStore(root: sandbox.root).takeResult(), note, "the result is read once")
        XCTAssertNil(LibraryEraseRequestStore(root: sandbox.root).takeResult())
    }

    func testNewerOrUnknownRequestsEraseNothing() throws {
        let sandbox = try EraseFixtures.sandbox(self, "newer")
        let defaults = EraseFixtures.Defaults()
        let before = LibraryTreeSnapshot.take(sandbox.erasableRoots)
        let store = LibraryEraseRequestStore(root: sandbox.root)
        let bodies: [String] = [#"{"schemaVersion":2,"categories":["scenes"]}"#, #"{"schemaVersion":1,"categories":["scenes","everything"]}"#,
                                #"{"schemaVersion":1,"categories":[]}"#, "not json"]
        for body in bodies {
            try EraseFixtures.write(body, to: store.requestFile)
            let note = LibraryEraseLaunch.run(root: sandbox.root, settings: defaults.values) { (keys: [String]) in defaults.remove(keys) }
            XCTAssertEqual(note, LibraryEraseResultNote(erased: false, message: LibraryEraseText.unreadable), body)
            XCTAssertFalse(store.hasPendingFile, body)
        }
        XCTAssertEqual(LibraryTreeSnapshot.take(sandbox.erasableRoots).differences(from: before), [])
        XCTAssertEqual(defaults.values, EraseFixtures.settings)
    }

    func testCancelRemovesOnlyTheRequest() throws {
        let sandbox = try EraseFixtures.sandbox(self, "cancel")
        let before = LibraryTreeSnapshot.take(sandbox.erasableRoots + sandbox.untouchable)
        let store = LibraryEraseRequestStore(root: sandbox.root)
        try store.save([.scenes])
        XCTAssertEqual(store.pending, [.scenes])
        store.cancel()
        XCTAssertNil(store.pending)
        XCTAssertNil(LibraryEraseLaunch.run(root: sandbox.root, settings: [:]) { (_: [String]) in XCTFail("nothing is removed") })
        XCTAssertEqual(LibraryTreeSnapshot.take(sandbox.erasableRoots + sandbox.untouchable).differences(from: before), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.root.appendingPathComponent(LibraryErasePolicy.workFolderName).path))
    }
}
