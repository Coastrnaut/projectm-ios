// FILE-004-T05, T10, T11, T14 (specs/111-file-004-import-conflict-resolver): per-conflict choices
// (Skip, Keep both, Replace) for a preset archive. Mixed choices install exactly the plan; Replace keeps
// the identifier (collections stay valid) and is all or nothing at every file operation; Skip leaves
// the existing preset byte-identical; derived identifiers are fixed values; a changed library is
// detected. Each test uses a few presets (owner rule 7).
import Foundation
import LocalPortability
import XCTest
@testable import PresetLibrary

final class PresetArchiveConflictTests: XCTestCase {
    typealias A = PresetArchiveFixtures
    typealias Seeded = (library: UserPresetLibrary, directory: URL, bright: UserPreset, broken: UserPreset, calm: UserPreset, roots: [URL])

    /// FILE-003's seeded library ("Bright Waves" playable, "Broken.milk" quarantined) plus "Calm Sea"
    /// and a collection listing Bright Waves.
    private func seeded() async throws -> Seeded {
        let s = try await A.seededLibrary(self)
        let folder = s.directory.deletingLastPathComponent().appendingPathComponent("Picked", isDirectory: true)
        let calm = try await ExportFixtures.importFile(s.library, named: "Calm Sea.milk", text: A.text("calm"), in: folder)
        let roots = A.roots(s.directory)
        let collections = PresetCollectionStore(directory: roots[1], makeID: { () -> String in "collection-1" })
        let collection = try collections.create(name: "Favourites")
        _ = try collections.add(s.bright.id, to: collection.id)
        return (s.library, s.directory, s.bright, s.broken, calm, roots)
    }

    private func suffix(_ id: String) -> String { String(id.dropFirst(UserPreset.idPrefix.count)) }

    /// The record and the stored bytes of one preset, for byte-identity checks.
    private func stored(_ id: String, in directory: URL) -> (UserPreset?, Data?) {
        let store = UserPresetStore(directory: directory)
        return (store.preset(id: id), store.contents(of: id))
    }

    /// An archive with every kind of choice: ID conflict (Replace), name conflict (default Keep both),
    /// new, name conflict (Skip).
    private func mixedArchive(_ s: Seeded) throws -> Data {
        try A.archive([(suffix(s.bright.id), "Bright Waves", A.text("bright-v2")),
                       ("r-2", "calm sea", A.text("other-calm")),
                       ("r-3", "Ocean One", A.text("one")),
                       ("r-4", "Calm Sea", A.text("third-calm"))])
    }

    private func mixedOverrides(_ s: Seeded) -> [String: PresetArchiveConflictPolicy] {
        [s.bright.id: .replace, "user/r-4": .skip]
    }

    // MARK: - US1: mixed choices install exactly the plan

    func testMixedChoicesInstallExactlyThePlan() async throws {
        let s = try await seeded()
        let data = try mixedArchive(s)
        let calmBefore = stored(s.calm.id, in: s.directory)
        let plan = await s.library.planArchiveImport(data, policy: .keepBoth, overrides: mixedOverrides(s))
        XCTAssertEqual(plan.entries.map(\.choice), [.replace, .keepBoth, nil, .skip])
        XCTAssertEqual(plan.entries[0].replaces, PresetArchiveAction(id: s.bright.id, name: "Bright Waves"))
        XCTAssertEqual(plan.actions.map(\.name), ["Bright Waves", "calm sea copy", "Ocean One"])
        XCTAssertEqual(plan.actions[0], PresetArchiveAction(id: s.bright.id, name: "Bright Waves", replacesID: s.bright.id))
        XCTAssertEqual(plan.replaceCount, 1)
        XCTAssertEqual(plan.counts.toInstall, 3)

        let outcome = await s.library.installArchive(data, plan: plan)
        guard case .installed(let presets) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(presets.map(\.id), plan.actions.map(\.id))
        XCTAssertEqual(presets.map(\.state), [.pending, .pending, .pending])

        let store = UserPresetStore(directory: s.directory)
        XCTAssertEqual(store.presets.count, 3 + 2, "two added, one replaced in place")
        XCTAssertEqual(store.presets.first?.id, s.bright.id, "a replaced record keeps its place in the index")
        let replaced = try XCTUnwrap(store.preset(id: s.bright.id))
        XCTAssertEqual(replaced.sha256, ContentHash.sha256Hex(Array(A.text("bright-v2").utf8)))
        XCTAssertEqual(store.contents(of: s.bright.id), Data(A.text("bright-v2").utf8))
        let oldFile = s.directory.appendingPathComponent("files").appendingPathComponent(s.bright.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path), "the old text is gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.directory.appendingPathComponent("staging").path))
        // Skip and Keep both left "Calm Sea" byte-identical.
        let calmAfter = stored(s.calm.id, in: s.directory)
        XCTAssertEqual(calmAfter.0, calmBefore.0)
        XCTAssertEqual(calmAfter.1, calmBefore.1)
        // The collection still lists Bright Waves' identifier and it resolves (FILE-004-S4).
        let collection = try XCTUnwrap(PresetCollectionStore(directory: s.roots[1]).collection(id: "collection-1"))
        XCTAssertEqual(collection.presetIDs, [s.bright.id])
        XCTAssertNotNil(store.preset(id: collection.presetIDs[0]))
        // The replacement waits for its trial, then plays.
        await s.library.runPendingTrials()
        let playable = await s.library.snapshot.playable.map(\.id)
        XCTAssertTrue(playable.contains(s.bright.id))
    }

    func testReplaceByNameKeepsTheTargetIdentifierAndSkipChangesNothing() async throws {
        let s = try await seeded()
        let data = try A.archive([("s-1", "CALM SEA", A.text("calm-v2"))])
        let skip = await s.library.planArchiveImport(data, policy: .skip)
        let before = LibraryTreeSnapshot.take(s.roots)
        let skipped = await s.library.installArchive(data, plan: skip)
        XCTAssertEqual(skipped, .refused(PresetArchiveText.nothingToInstall))
        XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), before, "Skip leaves every byte as it was")

        let plan = await s.library.planArchiveImport(data, policy: .replace)
        XCTAssertEqual(plan.entries.map(\.kind), [.nameConflict(existingName: "Calm Sea")])
        XCTAssertEqual(plan.actions, [PresetArchiveAction(id: s.calm.id, name: "CALM SEA", replacesID: s.calm.id)])
        guard case .installed = await s.library.installArchive(data, plan: plan) else { return XCTFail() }
        let store = UserPresetStore(directory: s.directory)
        XCTAssertEqual(store.preset(id: s.calm.id)?.name, "CALM SEA")
        XCTAssertEqual(store.contents(of: s.calm.id), Data(A.text("calm-v2").utf8))
        XCTAssertEqual(store.presets.count, 3)
    }

    func testReplaceFallsBackToKeepBothWithoutALibraryTarget() async throws {
        let s = try await seeded()
        // Two incoming presets share a new name: the second clashes only with the first.
        // An incoming preset with Bright Waves' id and Calm Sea's name: Replace targets the id match.
        let data = try A.archive([("t-1", "Twin", A.text("twin-1")), ("t-2", "twin", A.text("twin-2")),
                                  (suffix(s.bright.id), "Calm Sea", A.text("bright-as-calm"))])
        let plan = await s.library.planArchiveImport(data, policy: .replace)
        // The archive lists presets by identifier: Bright Waves' id sorts first.
        XCTAssertEqual(plan.entries.map(\.fellBack), [false, false, true])
        XCTAssertEqual(plan.actions.map(\.name), ["Calm Sea copy", "Twin", "twin copy"])
        XCTAssertEqual(plan.actions[0].id, s.bright.id)
        XCTAssertEqual(plan.actions[0].replacesID, s.bright.id)
        XCTAssertNil(plan.actions[2].replacesID)
        guard case .installed(let presets) = await s.library.installArchive(data, plan: plan) else { return XCTFail() }
        XCTAssertEqual(presets.count, 3)
        XCTAssertEqual(UserPresetStore(directory: s.directory).presets.count, 3 + 2)
    }

    func testReplacingAQuarantinedPresetMovesItBackToWaiting() async throws {
        let s = try await seeded()
        XCTAssertEqual(s.broken.state, .quarantined)
        let data = try A.archive([(suffix(s.broken.id), "Mended", A.text("mended"))])
        let plan = await s.library.planArchiveImport(data, policy: .replace)
        XCTAssertEqual(plan.actions, [PresetArchiveAction(id: s.broken.id, name: "Mended", replacesID: s.broken.id)])
        guard case .installed = await s.library.installArchive(data, plan: plan) else { return XCTFail() }
        let store = UserPresetStore(directory: s.directory)
        XCTAssertEqual(store.preset(id: s.broken.id)?.state, .pending)
        XCTAssertNil(store.preset(id: s.broken.id)?.quarantine)
        let quarantined = s.directory.appendingPathComponent("quarantine").appendingPathComponent(s.broken.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantined.path))
    }

    func testAHeldReplaceTargetRefusesTheInstallWithNothingWritten() async throws {
        let s = try await seeded()
        // A leftover trial record whose quarantine cannot be saved makes Bright Waves held.
        try UserPresetStore(directory: s.directory).writeRecord(.trial, presetID: s.bright.id)
        let failing = UserPresetLibrary(directory: s.directory, now: { ExportFixtures.now },
                                        write: { @Sendable (_: Data, _: URL) throws -> Void in throw CocoaError(.fileWriteNoPermission) })
        _ = await failing.load()
        let data = try A.archive([(suffix(s.bright.id), "Bright Waves", A.text("bright-v3"))])
        let plan = await failing.planArchiveImport(data, policy: .replace)
        let before = LibraryTreeSnapshot.take(s.roots)
        let outcome = await failing.installArchive(data, plan: plan)
        XCTAssertEqual(outcome, .refused(PresetArchiveText.nothingInstalled(PresetArchiveText.heldTarget)))
        XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), before)
    }

    // MARK: - US2: no partial overwrite

    func testAMixedInstallFailingAtEveryFileOperationIsAllOrNothing() async throws {
        // The clean result, from an identical library without faults.
        let reference = try await seeded()
        let data = try mixedArchive(reference)
        let referencePlan = await reference.library.planArchiveImport(data, policy: .keepBoth, overrides: mixedOverrides(reference))
        guard case .installed = await reference.library.installArchive(data, plan: referencePlan) else { return XCTFail() }
        let clean = LibraryTreeSnapshot.take(reference.roots)

        var preCommit = 0
        var postCommit = 0
        for step in 0..<30 {
            let s = try await seeded()
            let plan = await s.library.planArchiveImport(data, policy: .keepBoth, overrides: mixedOverrides(s))
            XCTAssertEqual(plan, referencePlan, "equal libraries give equal plans")
            let before = LibraryTreeSnapshot.take(s.roots)
            let memoryBefore = await s.library.snapshot
            let fault = OneShotFault(failAt: step)
            await s.library.setStoreFault { (operation: UserPresetStore.FileOperation, url: URL) throws in try fault.check(operation, url) }
            let outcome = await s.library.installArchive(data, plan: plan)
            await s.library.setStoreFault(nil)
            guard fault.fired else {
                guard case .installed = outcome else { return XCTFail("step \(step): \(outcome)") }
                XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), clean, "step \(step): the clean install")
                break
            }
            switch outcome {
            case .refused(let message):
                preCommit += 1
                XCTAssertEqual(message, PresetArchiveText.nothingInstalled(PresetArchiveText.saveFailed))
                let after = LibraryTreeSnapshot.take(s.roots)
                XCTAssertEqual(after, before, "step \(step): \(after.differences(from: before))")
                let memoryAfter = await s.library.snapshot
                XCTAssertEqual(memoryAfter, memoryBefore, "step \(step): memory unchanged")
            case .installed:
                // A clean-up step after the commit failed: the next load finishes it.
                postCommit += 1
                let reopened = UserPresetLibrary(directory: s.directory, now: { ExportFixtures.now })
                _ = await reopened.load()
                let after = LibraryTreeSnapshot.take(s.roots)
                XCTAssertEqual(after, clean, "step \(step): \(after.differences(from: clean))")
            case .changed:
                XCTFail("step \(step): changed")
            }
        }
        // staging, 3 writes, the list, 3 moves, the index; then the old text and staging.
        XCTAssertGreaterThanOrEqual(preCommit, 9, "every write, move and the index were each failed once")
        XCTAssertGreaterThanOrEqual(postCommit, 2, "both clean-up steps were failed once")
    }

    func testAnInterruptedReplaceIsSettledByTheIndexAtLoad() async throws {
        let s = try await seeded()
        // A crash before the commit: staging lists Bright Waves' text, which the index still names.
        let staging = s.directory.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let list: [String] = ["files/" + s.bright.fileName, "files/../index.json", "elsewhere/" + s.calm.fileName]
        try JSONEncoder().encode(list).write(to: staging.appendingPathComponent("replaced.json"))
        try Data("half".utf8).write(to: staging.appendingPathComponent("x.milk"))
        let before = LibraryTreeSnapshot.take(s.roots)
        let reopened = UserPresetLibrary(directory: s.directory, now: { ExportFixtures.now })
        _ = await reopened.load()
        let after = LibraryTreeSnapshot.take(s.roots)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(after.differences(from: before).allSatisfy { (path: String) -> Bool in path.contains("staging") }, true,
                       "only staging went: \(after.differences(from: before))")
        XCTAssertNotNil(UserPresetStore(directory: s.directory).contents(of: s.bright.id), "a named text is never deleted")
    }

    // MARK: - US3: deterministic identifiers

    func testDerivedIdentifiersAreFixedValues() async throws {
        let s = try await seeded()
        let data = try A.archive([(suffix(s.bright.id), "Bright Waves", A.text("bright-v2"))])
        let first = await s.library.planArchiveImport(data)
        let second = await s.library.planArchiveImport(data)
        XCTAssertEqual(first, second, "planning twice gives the same plan")
        // Research FILE-003-D3 / FILE-004-D2: SHA-256("FILE-003|<id>|<text sha256>|1"), first 32 hex digits.
        let textHash = ContentHash.sha256Hex(Array(A.text("bright-v2").utf8))
        let seed = "FILE-003|" + s.bright.id + "|" + textHash + "|1"
        let expected = UserPreset.idPrefix + String(ContentHash.sha256Hex(Array(seed.utf8)).prefix(32))
        XCTAssertEqual(first.actions.map(\.id), [expected])
        XCTAssertEqual(first.actions.map(\.name), ["Bright Waves copy"])
        // A fixed input → a fixed value, so another process computes the same identifier.
        XCTAssertEqual(PresetArchiveImportPlanner.derivedID(for: try XCTUnwrap(ExportedUserPreset(
            A.record(id: "fixed", name: "Fixed", text: A.text("fixed")))), avoiding: []),
                       "user/" + String(ContentHash.sha256Hex(Array(("FILE-003|user/fixed|" + ContentHash.sha256Hex(Array(A.text("fixed").utf8)) + "|1").utf8)).prefix(32)))
        // Different content → a different identifier; Replace → the target's identifier.
        let other = try A.archive([(suffix(s.bright.id), "Bright Waves", A.text("bright-v9"))])
        let otherPlan = await s.library.planArchiveImport(other)
        XCTAssertNotEqual(otherPlan.actions.map(\.id), first.actions.map(\.id))
        let replace = await s.library.planArchiveImport(data, policy: .replace)
        XCTAssertEqual(replace.actions.map(\.id), [s.bright.id])
    }

    // MARK: - US5: re-validation

    func testARemovedReplaceTargetIsDetectedWithNothingWritten() async throws {
        let s = try await seeded()
        let data = try A.archive([("u-1", "Calm Sea", A.text("calm-v2"))])
        let plan = await s.library.planArchiveImport(data, policy: .replace)
        XCTAssertEqual(plan.replaceCount, 1)
        let removed = await s.library.remove(s.calm.id)
        XCTAssertTrue(removed)
        let before = LibraryTreeSnapshot.take(s.roots)
        guard case .changed(let fresh) = await s.library.installArchive(data, plan: plan) else { return XCTFail() }
        XCTAssertEqual(fresh.entries.map(\.kind), [.new])
        XCTAssertEqual(fresh.policy, .replace, "the choices are kept")
        XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), before)
    }

    func testWords() {
        XCTAssertEqual(PresetArchiveText.installed(3, replaced: 1), "Installed 3 presets (1 replaced). They are checked before they can play.")
        XCTAssertEqual(PresetArchiveText.installed(1, replaced: 1), "Installed 1 preset (1 replaced). It is checked before it can play.")
        XCTAssertEqual(PresetArchiveText.installed(2, replaced: 0), PresetArchiveText.installed(2))
    }
}
