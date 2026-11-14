// PRE-018-T07 (specs/194-pre-018-integrity-scanner; S1-S5): the library check on a broken fixture
// library, a clean one, its bounds, the checksum relink and the user quarantine. Synthetic preset text
// written for this repository.
import Foundation
import XCTest
@testable import PresetLibrary

final class PresetIntegrityTests: XCTestCase {
    private typealias F = UserPresetFixtures

    static let texturedText = F.preset(warp: ["shader_body", "{", "    ret = tex2D(sampler_clouds, uv).xyz * 0.97;", "}"],
                                       comp: F.compShader)
    static let headerless = F.preset(header: "")

    /// A well-formed record for `text` (the store does not check it).
    static func record(_ name: String, _ text: String, id: String, state: UserPresetState = .playable,
                       duplicateOf: PresetDuplicateOrigin? = nil) -> UserPreset {
        let bytes = Array(text.utf8)
        return UserPreset(id: id, name: name, author: "", originalFileName: name + ".milk", sha256: ContentHash.sha256Hex(bytes),
                          blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count, importedAt: Date(timeIntervalSince1970: 0),
                          state: state, quarantine: state == .quarantined ? PresetQuarantineReason(.missingHeader) : nil,
                          license: PresetLicenseMetadata(origin: duplicateOf == nil ? .userImport : .bundledDuplicate,
                                                         authorFromFileName: false, linesFound: []),
                          duplicateOf: duplicateOf)
    }

    struct Broken {
        let directory: URL
        let library: UserPresetLibrary
        let references: PresetReferenceSnapshot
        let lostText: String
    }

    /// One issue of every kind and every reference store (spec US1 scenario 1), plus a clean preset, a
    /// quarantined one and references that resolve.
    func brokenLibrary() async throws -> Broken {
        let directory = try F.tempDirectory(self)
        let store = UserPresetStore(directory: directory)
        let lost = F.preset(settings: ["fDecay=0.950000", "zoom=1.020000"])
        try store.add(Self.record("Textured", Self.texturedText, id: "user/textured"), contents: Data(Self.texturedText.utf8))
        try store.add(Self.record("Lost", lost, id: "user/lost"), contents: Data(lost.utf8))
        try store.add(Self.record("Broken", Self.headerless, id: "user/broken"), contents: Data(Self.headerless.utf8))
        try store.add(Self.record("Clean", F.valid, id: "user/clean"), contents: Data(F.valid.utf8))
        let quarantined = F.preset(settings: ["zoom=0.990000"])
        try store.add(Self.record("Held", quarantined, id: "user/held", state: .quarantined), contents: Data(quarantined.utf8))
        let lostURL = directory.appendingPathComponent("files/\(ContentHash.sha256Hex(Array(lost.utf8))).milk")
        try FileManager.default.removeItem(at: lostURL)

        let references = PresetReferenceSnapshot(
            favorites: ["user/clean", "user/gone-favorite", "included/a.milk"],
            tags: ["user/gone-tag", "user/broken"],
            overrides: ["user/gone-adjusted", "user/held"],
            collections: [.init(id: "C1", name: "Party", presetIDs: ["user/held", "user/gone-collected", "included/a.milk"])],
            recents: ["user/gone-recent", "user/lost"])
        let library = UserPresetLibrary(directory: directory)
        await library.load()
        return Broken(directory: directory, library: library, references: references, lostText: lost)
    }

    static let builtIn: @Sendable (String) -> Bool = { (id: String) -> Bool in id == "included/a.milk" }

    func testBrokenFixtureReportsEachIssueOnceWithItsSuggestion() async throws {
        let broken = try await brokenLibrary()
        let report = PresetIntegrityScanner.scan(inventory: await broken.library.integrityInventory(), references: broken.references,
                                                 isBuiltIn: Self.builtIn)
        XCTAssertEqual(report.issues.count, 8, report.issues.map(\.id).joined(separator: "\n"))
        XCTAssertEqual(Set(report.issues.map(\.id)).count, 8, "each issue once")
        XCTAssertFalse(report.incomplete)
        XCTAssertEqual(report.presetsChecked, 4, "quarantined records are not read")

        let texture = try XCTUnwrap(report.issues(of: .missingTexture).first)
        XCTAssertEqual(report.issues(of: .missingTexture).count, 1)
        XCTAssertEqual(texture.presetID, "user/textured")
        XCTAssertEqual(texture.detail, "clouds")
        XCTAssertEqual(texture.actions, [.moveToQuarantine, .removePreset])
        XCTAssertTrue(texture.suggestion.contains("cannot import textures"))
        XCTAssertTrue(texture.suggestion.contains("“clouds”"))

        let file = try XCTUnwrap(report.issues(of: .missingFile).first)
        XCTAssertEqual(report.issues(of: .missingFile).count, 1)
        XCTAssertEqual(file.presetID, "user/lost")
        XCTAssertEqual(file.actions, [.relinkFile, .removePreset], "not a library copy: no Restore from Library")
        XCTAssertTrue(file.suggestion.contains("Re-import the original .milk file"))
        XCTAssertEqual(file.title(of: .relinkFile), "Re-import…")

        let unparsable = try XCTUnwrap(report.issues(of: .unparsable).first)
        XCTAssertEqual(report.issues(of: .unparsable).count, 1)
        XCTAssertEqual(unparsable.presetID, "user/broken")
        XCTAssertEqual(unparsable.detail, PresetQuarantineReason(.missingHeader).message)
        XCTAssertEqual(unparsable.actions, [.moveToQuarantine, .removePreset])

        let dangling = report.issues(of: .danglingReference)
        let byStore: [PresetReferenceStore: String] = Dictionary(uniqueKeysWithValues: dangling.map { ($0.store!, $0.presetID) })
        XCTAssertEqual(byStore, [.favorites: "user/gone-favorite", .tags: "user/gone-tag", .overrides: "user/gone-adjusted",
                                 .collections: "user/gone-collected", .recents: "user/gone-recent"])
        XCTAssertTrue(dangling.allSatisfy { $0.actions == [.removeReference] && $0.isSafe })
        let collection = try XCTUnwrap(dangling.first { $0.store == .collections })
        XCTAssertEqual(collection.collectionID, "C1")
        XCTAssertEqual(collection.title(of: .removeReference), "Remove from Collection")
        XCTAssertEqual(collection.title, "“Party” names a preset that no longer exists")
        XCTAssertEqual(dangling.first { $0.store == .favorites }?.title(of: .removeReference), "Remove from Favorites")
        XCTAssertEqual(report.summary, "Found 8 problems.")

        // Applying the safe fixes (the stores without those IDs) resolves every dangling reference; the
        // other three stay until the user acts.
        let gone = Set(report.safeIssues.map(\.presetID))
        var fixed = broken.references
        fixed.favorites.removeAll { gone.contains($0) }
        fixed.tags.removeAll { gone.contains($0) }
        fixed.overrides.removeAll { gone.contains($0) }
        fixed.collections[0].presetIDs.removeAll { gone.contains($0) }
        fixed.recents = RecentPresetHistory(ids: fixed.recents).removing(gone).ids
        let again = PresetIntegrityScanner.scan(inventory: await broken.library.integrityInventory(), references: fixed,
                                                isBuiltIn: Self.builtIn)
        XCTAssertEqual(again.issues(of: .danglingReference).count, 0)
        XCTAssertEqual(again.issues.map(\.kind), [.missingTexture, .missingFile, .unparsable])
    }

    func testCleanLibraryHasNoIssuesAndTheInventoryWritesNothing() async throws {
        let directory = try F.tempDirectory(self)
        let store = UserPresetStore(directory: directory)
        try store.add(Self.record("Clean", F.valid, id: "user/clean"), contents: Data(F.valid.utf8))
        let before = F.snapshot(directory)
        let library = UserPresetLibrary(directory: directory)
        await library.load()
        let report = PresetIntegrityScanner.scan(inventory: await library.integrityInventory(),
                                                 references: PresetReferenceSnapshot(favorites: ["user/clean", "included/a.milk"],
                                                                                     recents: ["user/clean"]),
                                                 isBuiltIn: Self.builtIn)
        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.summary, "No problems found.")
        XCTAssertEqual(report.referencesChecked, 3)
        XCTAssertEqual(F.snapshot(directory), before, "R2: the check changes nothing")
    }

    func testBoundsStopTheCheckAndMarkItIncomplete() async throws {
        let broken = try await brokenLibrary()
        let one = await broken.library.integrityInventory(limits: PresetIntegrityLimits(maxRecords: 1))
        XCTAssertEqual(one.entries.count, 1)
        XCTAssertTrue(one.incomplete)
        let small = await broken.library.integrityInventory(limits: PresetIntegrityLimits(maxTextBytes: 10))
        XCTAssertEqual(small.entries.count, 0)
        XCTAssertTrue(small.incomplete)

        let inventory = await broken.library.integrityInventory()
        let refs = PresetIntegrityScanner.scan(inventory: inventory, references: broken.references, isBuiltIn: Self.builtIn,
                                               limits: PresetIntegrityLimits(maxReferences: 2))
        XCTAssertEqual(refs.referencesChecked, 2)
        XCTAssertTrue(refs.incomplete)
        XCTAssertEqual(refs.issues(of: .danglingReference).count, 1, "only the first two references were read")
        let capped = PresetIntegrityScanner.scan(inventory: inventory, references: broken.references, isBuiltIn: Self.builtIn,
                                                 limits: PresetIntegrityLimits(maxIssues: 2))
        XCTAssertEqual(capped.issues.count, 2)
        XCTAssertTrue(capped.incomplete)
        XCTAssertTrue(capped.summary.hasSuffix("The check was incomplete."))

        let many = UserPresetIntegrityEntry(id: "user/t", name: "T", fileIntact: true, missingTextures: ["b", "a", "c", "a"])
        let textures = PresetIntegrityScanner.scan(inventory: UserPresetIntegrityInventory(entries: [many], knownIDs: ["user/t"]),
                                                   references: .empty, isBuiltIn: { (_: String) -> Bool in false },
                                                   limits: PresetIntegrityLimits(maxTexturesPerPreset: 2))
        XCTAssertEqual(textures.issues.map(\.detail), ["a", "b"])
    }

    func testRelinkRestoresByChecksumAndRefusesOtherBytes() async throws {
        let broken = try await brokenLibrary()
        let before = F.snapshot(broken.directory)
        let missing = await broken.library.data(for: "user/lost")
        XCTAssertNil(missing)
        let wrong = await broken.library.relink("user/lost", with: Data(F.valid.utf8))
        XCTAssertEqual(wrong, .checksumMismatch)
        XCTAssertEqual(F.snapshot(broken.directory), before, "a different file writes nothing")

        let restored = await broken.library.relink("user/lost", with: Data(broken.lostText.utf8))
        XCTAssertEqual(restored, .restored(name: "Lost"))
        let data = await broken.library.data(for: "user/lost")
        XCTAssertEqual(data, Data(broken.lostText.utf8), "byte for byte, playable again")
        let twice = await broken.library.relink("user/lost", with: Data(broken.lostText.utf8))
        XCTAssertEqual(twice, .notMissing)
        let unknown = await broken.library.relink("user/none", with: Data())
        XCTAssertEqual(unknown, .unknownPreset)
        let report = PresetIntegrityScanner.scan(inventory: await broken.library.integrityInventory(), references: .empty,
                                                 isBuiltIn: Self.builtIn)
        XCTAssertTrue(report.issues(of: .missingFile).isEmpty)
    }

    func testAnUneditedLibraryCopyOffersRestoreFromLibrary() async throws {
        let directory = try F.tempDirectory(self)
        let bytes = Array(F.valid.utf8)
        let origin = PresetDuplicateOrigin(presetID: "included/a.milk", name: "A", packID: "included", packTitle: "Included",
                                           sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes),
                                           licenseStatement: "MIT", requiresLibraryUnlock: false)
        let store = UserPresetStore(directory: directory)
        try store.add(Self.record("A copy", F.valid, id: "user/copy", duplicateOf: origin), contents: Data(bytes))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("files/\(origin.sha256).milk"))
        let library = UserPresetLibrary(directory: directory)
        await library.load()
        let inventory = await library.integrityInventory()
        let offered = PresetIntegrityScanner.scan(inventory: inventory, references: .empty, isBuiltIn: Self.builtIn)
        XCTAssertEqual(offered.issues.first?.actions, [.relinkFile, .restoreFromLibrary, .removePreset])
        XCTAssertTrue(offered.issues.first?.suggestion.contains("restore it from the library") == true)
        let gone = PresetIntegrityScanner.scan(inventory: inventory, references: .empty, isBuiltIn: { (_: String) -> Bool in false })
        XCTAssertEqual(gone.issues.first?.actions, [.relinkFile, .removePreset], "the bundled original no longer exists")
    }

    func testQuarantineByUserRecordsTheIssueAndSettlesIt() async throws {
        let broken = try await brokenLibrary()
        let moved = await broken.library.quarantineByUser("user/broken", detail: "Does not start with the header.")
        XCTAssertTrue(moved)
        let again = await broken.library.quarantineByUser("user/broken", detail: "again")
        XCTAssertFalse(again)
        let quarantined = await broken.library.snapshot.quarantined.first { $0.id == "user/broken" }
        XCTAssertEqual(quarantined?.quarantine?.kind, .movedByUser)
        XCTAssertEqual(quarantined?.quarantine?.message, "You moved this preset to Quarantine. (Does not start with the header.)")
        let report = PresetIntegrityScanner.scan(inventory: await broken.library.integrityInventory(), references: broken.references,
                                                 isBuiltIn: Self.builtIn)
        XCTAssertTrue(report.issues(of: .unparsable).isEmpty)
        XCTAssertFalse(report.issues.contains { $0.store == .tags && $0.presetID == "user/broken" }, "its tags still name a record")
    }

    func testUnreadableUserListJudgesNoUserPresetID() {
        let report = PresetIntegrityScanner.scan(inventory: UserPresetIntegrityInventory(entries: [], knownIDs: [], available: false),
                                                 references: PresetReferenceSnapshot(favorites: ["user/x", "pack/gone.milk"]),
                                                 isBuiltIn: Self.builtIn)
        XCTAssertEqual(report.issues.map(\.presetID), ["pack/gone.milk"])
        XCTAssertTrue(report.userPresetsUnavailable)
        XCTAssertTrue(report.summary.contains(UserPresetText.newerFormat))
    }

    func testRecentHistoryRemovingKeepsOrder() {
        XCTAssertEqual(RecentPresetHistory(ids: ["a", "b", "c"]).removing(["b"]).ids, ["a", "c"])
    }
}
