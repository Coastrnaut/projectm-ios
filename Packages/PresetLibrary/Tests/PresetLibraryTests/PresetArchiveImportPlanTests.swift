// FILE-003-T05: the fixture table of exact dry-run plans (contract C1; FILE-003-R3-R7, S3). Each
// archive is planned against a seeded library ("Bright Waves" playable, "Broken.milk" quarantined).
import Foundation
import LocalPortability
import XCTest
@testable import PresetLibrary

final class PresetArchiveImportPlanTests: XCTestCase {
    typealias A = PresetArchiveFixtures

    private func bytes(_ text: String) -> Int { text.utf8.count }

    // MARK: - The seven roadmap fixtures

    func testCleanArchive() async throws {
        let seeded = try await A.seededLibrary(self)
        let one = A.text("one"), two = A.text("two")
        let data = try A.archive([("aaaa-1", "Ocean One", one), ("aaaa-2", "Ocean Two", two)])
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertNil(plan.refusal)
        XCTAssertEqual(plan.archiveSHA256, ContentHash.sha256Hex([UInt8](data)))
        XCTAssertEqual(plan.policy, .keepBoth)
        XCTAssertEqual(plan.entries.map(\.kind), [.new, .new])
        XCTAssertEqual(plan.actions, [PresetArchiveAction(id: "user/aaaa-1", name: "Ocean One"),
                                      PresetArchiveAction(id: "user/aaaa-2", name: "Ocean Two")])
        let counts = plan.counts
        XCTAssertEqual([counts.new, counts.identical, counts.conflicts, counts.refused, counts.toInstall], [2, 0, 0, 0, 2])
        XCTAssertEqual(plan.missingLicense, [])
        XCTAssertEqual(plan.totalBytes, bytes(one) + bytes(two))
        XCTAssertTrue(plan.canInstall)
    }

    func testConflictingNamesKeepBothAndSkip() async throws {
        let seeded = try await A.seededLibrary(self)
        let other = A.text("other-bright"), twin = A.text("twin")
        let items: [(id: String, name: String, text: String)] = [("bbbb-1", "bright waves", other), ("bbbb-2", "BRIGHT WAVES", twin)]
        let data = try A.archive(items)
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.entries.map(\.kind), [.nameConflict(existingName: "Bright Waves"), .nameConflict(existingName: "Bright Waves")])
        // Copy names are chosen against the library and the earlier planned names (Clarifications).
        XCTAssertEqual(plan.actions, [PresetArchiveAction(id: "user/bbbb-1", name: "bright waves copy"),
                                      PresetArchiveAction(id: "user/bbbb-2", name: "BRIGHT WAVES copy 2")])
        XCTAssertEqual(plan.counts.nameConflicts, 2)
        XCTAssertTrue(plan.hasConflicts)

        let skip = await seeded.library.planArchiveImport(data, policy: .skip)
        XCTAssertEqual(skip.entries.map(\.kind), plan.entries.map(\.kind))
        XCTAssertEqual(skip.actions, [])
        XCTAssertEqual(skip.totalBytes, 0)
        XCTAssertFalse(skip.canInstall)
    }

    func testIdenticalContentIsSkipped() async throws {
        let seeded = try await A.seededLibrary(self)
        let data = try A.archive([("cccc-1", "Renamed Bright", A.text("bright")), ("cccc-2", "Fresh", A.text("fresh"))])
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.entries.map(\.kind), [.identical(existingName: "Bright Waves"), .new])
        XCTAssertEqual(plan.actions, [PresetArchiveAction(id: "user/cccc-2", name: "Fresh")])
        XCTAssertEqual(plan.counts.identical, 1)
        XCTAssertEqual(plan.totalBytes, bytes(A.text("fresh")))
    }

    func testMissingLicenceIsAWarningNotARefusal() async throws {
        let seeded = try await A.seededLibrary(self)
        let bare = A.text("bare", license: false)
        let data = try A.archive([("dddd-1", "Bare", bare), ("dddd-2", "Licensed", A.text("licensed"))])
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.entries.map(\.kind), [.new, .new])
        XCTAssertEqual(plan.entries.map(\.hasLicense), [false, true])
        XCTAssertEqual(plan.missingLicense, ["Bare"])
        XCTAssertEqual(plan.counts.toInstall, 2)
    }

    func testMalformedEntryRefusesTheWholeArchive() async throws {
        let seeded = try await A.seededLibrary(self)
        let data = try A.craftedArchive([("eeee-1", "Good", A.text("good"))]) { (manifest: inout UserPresetArchiveManifest) in
            manifest.presets[0].id = "user/NOT A VALID ID"
        }
        let expected = try XCTUnwrap(A.readerRefusal(data))
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.refusal, expected)
        XCTAssertEqual(plan.refusal, "A preset in the archive is not valid (user/NOT A VALID ID).")
        XCTAssertEqual(plan.entries, [])
        XCTAssertFalse(plan.canInstall)
    }

    func testNewerFormatVersionIsRefused() async throws {
        let seeded = try await A.seededLibrary(self)
        let data = try A.craftedArchive([("ffff-1", "Future", A.text("future"))]) { (manifest: inout UserPresetArchiveManifest) in
            manifest.formatVersion = 2
        }
        let expected = try XCTUnwrap(A.readerRefusal(data))
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.refusal, expected)
        XCTAssertEqual(plan.entries, [])
    }

    func testOversizeTextIsRefused() async throws {
        let seeded = try await A.seededLibrary(self)
        let filler: [String] = [String(repeating: "// padding line for size\n", count: 24_000)]
        let huge = ExportFixtures.text("huge", extra: filler)
        XCTAssertGreaterThan(huge.utf8.count, PresetImportLimits.maxFileBytes)
        let data = try A.archive([("gggg-1", "Huge", huge)])
        let expected = try XCTUnwrap(A.readerRefusal(data))
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.refusal, expected)
        XCTAssertEqual(plan.entries, [])
    }

    // MARK: - The other rows of the classification

    func testIDConflictGetsADerivedIdentifier() async throws {
        let seeded = try await A.seededLibrary(self)
        let suffix = String(seeded.bright.id.dropFirst(UserPreset.idPrefix.count))
        let data = try A.archive([(suffix, "Same ID", A.text("same-id"))])
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.entries.map(\.kind), [.idConflict(existingName: "Bright Waves")])
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.name, "Same ID")
        let seed = "FILE-003|" + seeded.bright.id + "|" + ContentHash.sha256Hex(Array(A.text("same-id").utf8)) + "|1"
        XCTAssertEqual(action.id, "user/" + String(ContentHash.sha256Hex(Array(seed.utf8)).prefix(32)))
        // Planning again gives the same plan (FILE-003-D3).
        let again = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(again, plan)
    }

    func testRefusalsQuarantinedBuiltInBlockedAndFailing() async throws {
        let seeded = try await A.seededLibrary(self)
        let builtInText = A.text("builtin"), blockedText = A.text("blocked")
        await seeded.library.setContext(PresetImportContext(
            builtIn: [ContentHash.gitBlobSHA1Hex(Array(builtInText.utf8)): .init(name: "Star", pack: "Included")],
            blockedHashes: [ContentHash.gitBlobSHA1Hex(Array(blockedText.utf8))], knownTextures: []))
        let data = try A.archive([("hhhh-1", "Quarantined Again", A.brokenText), ("hhhh-2", "Star Copy", builtInText),
                                  ("hhhh-3", "Taken Down", blockedText), ("hhhh-4", "No Header", A.F.preset(header: "", settings: ["zoom=1.2"]))])
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(plan.entries.map(\.kind), [
            .refused(.inQuarantine(name: "Broken.milk")),
            .refused(.builtIn(name: "Star", pack: "Included")),
            .refused(.blocked),
            .refused(.failsChecks(PresetQuarantineReason(.missingHeader).message)),
        ])
        XCTAssertEqual(plan.counts.refused, 4)
        XCTAssertFalse(plan.canInstall)
        XCTAssertEqual(PresetArchiveRefusal.inQuarantine(name: "x").message, "The same file is in Quarantine.")
    }

    func testLibraryFullRefusesTheExcessInArchiveOrder() {
        // The pure planner with 999 active records: one more fits.
        let records: [UserPreset] = (0..<999).map { (index: Int) -> UserPreset in
            A.record(id: "full-\(index)", name: "P\(index)", text: "t\(index)")
        }
        let data = (try? A.archive([("iiii-1", "Fits", A.text("fits")), ("iiii-2", "Too Many", A.text("too-many"))])) ?? Data()
        let plan = PresetArchiveImportPlanner.plan(archive: data, library: records, context: .empty)
        XCTAssertEqual(plan.entries.map(\.kind), [.new, .refused(.libraryFull)])
        XCTAssertEqual(plan.actions.map(\.name), ["Fits"])
    }

    func testWordsOfThePreview() async throws {
        let seeded = try await A.seededLibrary(self)
        let data = try A.archive([("jjjj-1", "Bright Waves", A.text("jjjj")), ("jjjj-2", "Echo", A.text("bright"))])
        let plan = await seeded.library.planArchiveImport(data)
        XCTAssertEqual(PresetArchiveText.previewAnnouncement(plan), "Import preview: 0 new, 1 already in My Presets, 1 conflict, 0 refused.")
        XCTAssertEqual(PresetArchiveText.installed(1), "Installed 1 preset. It is checked before it can play.")
        XCTAssertEqual(PresetArchiveText.installed(3), "Installed 3 presets. They are checked before they can play.")
    }
}
