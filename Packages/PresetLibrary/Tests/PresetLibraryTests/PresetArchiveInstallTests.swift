// FILE-003-T06, T10, T13, T14: the install executes exactly the plan; the dry run and Cancel leave
// the library byte-for-byte unchanged for every fixture (the row's acceptance); an install that
// fails at any file operation rolls back to the same bytes; Keep both and Skip; a library changed
// between the preview and Install is detected with nothing written.
import Foundation
import LocalPortability
import XCTest
@testable import PresetLibrary

/// Throws at the n-th store file operation (0-based), once.
final class OneShotFault: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let failAt: Int
    private(set) var fired = false

    init(failAt: Int) { self.failAt = failAt }

    func check(_ operation: UserPresetStore.FileOperation, _ url: URL) throws {
        let shouldFail: Bool = lock.withLock {
            defer { count += 1 }
            if count == failAt && !fired {
                fired = true
                return true
            }
            return false
        }
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
    }
}

final class PresetArchiveInstallTests: XCTestCase {
    typealias A = PresetArchiveFixtures

    /// The seeded library plus a collections file beside it (PRE-007's folder, never touched).
    private func seeded() async throws -> (library: UserPresetLibrary, directory: URL, bright: UserPreset, roots: [URL]) {
        let seeded = try await A.seededLibrary(self)
        let roots = A.roots(seeded.directory)
        try FileManager.default.createDirectory(at: roots[1], withIntermediateDirectories: true)
        try Data("{\"collections\":[]}".utf8).write(to: roots[1].appendingPathComponent("collections.json"))
        return (seeded.library, seeded.directory, seeded.bright, roots)
    }

    /// Every fixture of the plan table, by name.
    private func fixtures() throws -> [(name: String, data: Data)] {
        let filler: [String] = [String(repeating: "// padding line for size\n", count: 24_000)]
        return [
            ("clean", try A.archive([("k-1", "Ocean One", A.text("one")), ("k-2", "Ocean Two", A.text("two"))])),
            ("conflicting names", try A.archive([("k-3", "bright waves", A.text("other-bright"))])),
            ("identical content", try A.archive([("k-4", "Renamed", A.text("bright"))])),
            ("missing licence", try A.archive([("k-5", "Bare", A.text("bare", license: false))])),
            ("malformed entry", try A.craftedArchive([("k-6", "Good", A.text("good"))]) { (m: inout UserPresetArchiveManifest) in
                m.presets[0].id = "user/NOT VALID"
            }),
            ("newer version", try A.craftedArchive([("k-7", "Future", A.text("future"))]) { (m: inout UserPresetArchiveManifest) in
                m.formatVersion = 2
            }),
            ("oversize", try A.archive([("k-8", "Huge", ExportFixtures.text("huge", extra: filler))])),
        ]
    }

    // MARK: - The acceptance: Cancel leaves the library byte-for-byte unchanged (S1)

    func testDryRunThenCancelLeavesTheLibraryByteForByteUnchangedForEveryFixture() async throws {
        let s = try await seeded()
        let before = LibraryTreeSnapshot.take(s.roots)
        XCTAssertGreaterThanOrEqual(before.files.count, 4, "index, two texts, collections")
        for fixture in try fixtures() {
            for policy in PresetArchiveConflictPolicy.allCases {
                let plan = await s.library.planArchiveImport(fixture.data, policy: policy)
                _ = plan   // Cancel: the plan is discarded; nothing else happens.
                let after = LibraryTreeSnapshot.take(s.roots)
                XCTAssertEqual(after, before, "\(fixture.name), \(policy): \(after.differences(from: before))")
            }
        }
    }

    // MARK: - An install failing midway rolls back to the same bytes (S2)

    func testAnInstallFailingAtEveryFileOperationLeavesTheLibraryUnchanged() async throws {
        let s = try await seeded()
        let data = try A.archive([("m-1", "Ocean One", A.text("one")), ("m-2", "bright waves", A.text("other")),
                                  ("m-3", "Ocean Three", A.text("three"))])
        let plan = await s.library.planArchiveImport(data)
        XCTAssertEqual(plan.counts.toInstall, 3)
        let before = LibraryTreeSnapshot.take(s.roots)
        let snapshotBefore = await s.library.snapshot
        var failures = 0
        for step in 0..<40 {
            let fault = OneShotFault(failAt: step)
            await s.library.setStoreFault { (operation: UserPresetStore.FileOperation, url: URL) throws in try fault.check(operation, url) }
            let outcome = await s.library.installArchive(data, plan: plan)
            await s.library.setStoreFault(nil)
            guard fault.fired else {
                // Every operation passed: the install succeeded. All earlier steps were faults.
                guard case .installed(let presets) = outcome else { return XCTFail("step \(step): \(outcome)") }
                XCTAssertEqual(presets.count, 3)
                break
            }
            failures += 1
            XCTAssertEqual(outcome, .refused("Nothing was installed. The presets could not be saved."), "step \(step)")
            let after = LibraryTreeSnapshot.take(s.roots)
            XCTAssertEqual(after, before, "step \(step): \(after.differences(from: before))")
            let snapshotAfter = await s.library.snapshot
            XCTAssertEqual(snapshotAfter, snapshotBefore, "step \(step): memory unchanged")
        }
        // staging dir, 3 writes, files dir exists, 3 moves, staging removal, index write.
        XCTAssertGreaterThanOrEqual(failures, 8, "every write, move and the index were each failed once")
    }

    func testALeftoverStagingFolderIsRemovedAtLoad() async throws {
        let s = try await seeded()
        let staging = s.directory.appendingPathComponent(UserPresetStore.stagingFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("half an install".utf8).write(to: staging.appendingPathComponent("x.milk"))
        let reopened = UserPresetLibrary(directory: s.directory)
        _ = await reopened.load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    // MARK: - Install executes exactly the plan (S4)

    func testInstallAddsExactlyThePlannedPresetsAsWaiting() async throws {
        let s = try await seeded()
        let one = A.text("one"), other = A.text("other-bright"), bare = A.text("bare", license: false)
        let data = try A.archive([("n-1", "Ocean One", one), ("n-2", "bright waves", other), ("n-3", "Bare", bare),
                                  ("n-4", "Again", A.text("bright"))])
        let plan = await s.library.planArchiveImport(data)
        let outcome = await s.library.installArchive(data, plan: plan)
        guard case .installed(let presets) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(presets.map(\.id), plan.actions.map(\.id))
        XCTAssertEqual(presets.map(\.name), ["Ocean One", "bright waves copy", "Bare"])
        XCTAssertEqual(presets.map(\.state), [.pending, .pending, .pending])
        XCTAssertEqual(presets.map(\.importedAt), [ExportFixtures.now, ExportFixtures.now, ExportFixtures.now])
        XCTAssertEqual(presets[0].license.linesFound, ["// License: CC-BY 4.0, Example Author"])
        XCTAssertEqual(presets[2].license.linesFound, [])
        XCTAssertFalse(presets.contains(where: \.license.rightsVerified))

        // The stored record and texts are exactly the plan's.
        let reopened = UserPresetStore(directory: s.directory)
        XCTAssertEqual(reopened.presets.count, 2 + 3)
        for (preset, text) in zip(presets, [one, other, bare]) {
            XCTAssertEqual(reopened.preset(id: preset.id), preset)
            XCTAssertEqual(reopened.contents(of: preset.id), Data(text.utf8))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.directory.appendingPathComponent("staging").path))
        // The trial then makes them playable like any import.
        await s.library.runPendingTrials()
        let playable = await s.library.snapshot.playable.map(\.name)
        XCTAssertEqual(Set(playable), ["Bright Waves", "Ocean One", "bright waves copy", "Bare"])
    }

    // MARK: - Keep both and Skip (US3)

    func testKeepBothLeavesTheExistingPresetUntouchedAndSkipInstallsNothing() async throws {
        let s = try await seeded()
        let suffix = String(s.bright.id.dropFirst(UserPreset.idPrefix.count))
        let data = try A.archive([(suffix, "Bright Waves", A.text("same-id-and-name"))])
        let existingText = try XCTUnwrap(UserPresetStore(directory: s.directory).contents(of: s.bright.id))

        let skip = await s.library.planArchiveImport(data, policy: .skip)
        let before = LibraryTreeSnapshot.take(s.roots)
        let skipped = await s.library.installArchive(data, plan: skip)
        XCTAssertEqual(skipped, .refused(PresetArchiveText.nothingToInstall))
        XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), before)

        let keep = await s.library.planArchiveImport(data, policy: .keepBoth)
        XCTAssertEqual(keep.entries.map(\.kind), [.idConflict(existingName: "Bright Waves")])
        guard case .installed(let presets) = await s.library.installArchive(data, plan: keep) else { return XCTFail() }
        XCTAssertNotEqual(presets[0].id, s.bright.id)
        XCTAssertEqual(presets[0].name, "Bright Waves copy")
        let store = UserPresetStore(directory: s.directory)
        XCTAssertEqual(store.preset(id: s.bright.id), s.bright)
        XCTAssertEqual(store.contents(of: s.bright.id), existingText)
    }

    // MARK: - Re-validation (US4, S5)

    func testALibraryChangedAfterThePreviewIsDetectedWithNothingWritten() async throws {
        let s = try await seeded()
        let data = try A.archive([("p-1", "Ocean One", A.text("one")), ("p-2", "bright waves", A.text("other"))])
        let plan = await s.library.planArchiveImport(data)
        XCTAssertEqual(plan.entries.map(\.kind), [.new, .nameConflict(existingName: "Bright Waves")])

        // Meanwhile "Bright Waves" is removed: the conflict is gone.
        let removed = await s.library.remove(s.bright.id)
        XCTAssertTrue(removed)
        let before = LibraryTreeSnapshot.take(s.roots)
        let outcome = await s.library.installArchive(data, plan: plan)
        guard case .changed(let fresh) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(fresh.entries.map(\.kind), [.new, .new])
        XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), before, "nothing written")

        // A different archive under the old plan is also a change.
        let otherData = try A.archive([("p-3", "Else", A.text("else"))])
        guard case .changed = await s.library.installArchive(otherData, plan: fresh) else { return XCTFail() }
        XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), before)

        // The fresh plan installs.
        guard case .installed(let presets) = await s.library.installArchive(data, plan: fresh) else { return XCTFail() }
        XCTAssertEqual(presets.map(\.name), ["Ocean One", "bright waves"])
    }

    func testARefusedArchiveInstallsNothing() async throws {
        let s = try await seeded()
        let data = try A.craftedArchive([("q-1", "Future", A.text("future"))]) { (m: inout UserPresetArchiveManifest) in m.formatVersion = 2 }
        let plan = await s.library.planArchiveImport(data)
        let before = LibraryTreeSnapshot.take(s.roots)
        let outcome = await s.library.installArchive(data, plan: plan)
        XCTAssertEqual(outcome, .refused(PresetArchiveText.nothingInstalled(try XCTUnwrap(plan.refusal))))
        XCTAssertEqual(LibraryTreeSnapshot.take(s.roots), before)
    }
}
