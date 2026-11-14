// LibraryIntegrityAcceptanceTests.swift — PRE-018-T12, T13, T15: the roadmap acceptance in the app
// ("Broken fixture is reported with actionable relink suggestion"; PRE-018-S1, S2, S5). A broken library
// with one issue of every kind and every reference store, through the real stores (favorites and recents
// in a UserDefaults suite, tags, adjustments and collections in a temporary folder, user presets in a
// UserPresetLibrary): one check reports each issue once with its suggestion; Fix All Safe removes the
// five dangling references and nothing else; a rescan lists only the three issues that need the user;
// the checksum relink, Restore from Library, Move to Quarantine and Remove Preset each settle theirs.
// Synthetic preset text written for this repository. Runs in about a second.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class LibraryIntegrityAcceptanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var base: URL!
    private var announcements: [String] = []

    override func setUp() async throws {
        suite = "LibraryIntegrityAcceptanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        base = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        announcements = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: - Fixture

    static func text(header: Bool = true, warp: [String] = [], zoom: String) -> String {
        var lines: [String] = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2"]
        if header { lines.append("[preset00]") }
        lines += ["fDecay=0.960000", "zoom=" + zoom, "per_frame_1=rot = 0.01*sin(time);"]
        for (index, line) in warp.enumerated() { lines.append("warp_\(index + 1)=`" + line) }
        return lines.joined(separator: "\n") + "\n"
    }

    static let textured = text(warp: ["shader_body", "{", "    ret = tex2D(sampler_absent, uv).xyz;", "}"], zoom: "1.01")
    static let lost = text(zoom: "1.02")
    static let broken = text(header: false, zoom: "1.03")
    static let clean = text(zoom: "1.04")
    static let alpha = text(zoom: "1.05")
    static let gone = "user/gone"

    static func record(_ name: String, _ text: String, id: String, duplicateOf: PresetDuplicateOrigin? = nil) -> UserPreset {
        let bytes: [UInt8] = Array(text.utf8)
        return UserPreset(id: id, name: name, author: "", originalFileName: name + ".milk", sha256: ContentHash.sha256Hex(bytes),
                          blobHash: ContentHash.gitBlobSHA1Hex(bytes), byteCount: bytes.count, importedAt: Date(timeIntervalSince1970: 0),
                          state: .playable, provenOnScreen: true,
                          license: PresetLicenseMetadata(origin: duplicateOf == nil ? .userImport : .bundledDuplicate,
                                                         authorFromFileName: false, linesFound: []),
                          duplicateOf: duplicateOf)
    }

    private var userDirectory: URL { base.appendingPathComponent("UserPresets", isDirectory: true) }

    private func storedURL(_ text: String) -> URL {
        userDirectory.appendingPathComponent("files/\(ContentHash.sha256Hex(Array(text.utf8))).milk")
    }

    private func builtIn() throws -> PresetLibrary {
        let records: [[String: Any]] = [["id": "included/Alpha.milk", "name": "Alpha", "author": "A", "source": "included",
                                         "folder": [String](), "path": "Alpha.milk", "hash": ContentHash.gitBlobSHA1Hex(Array(Self.alpha.utf8))]]
        let packs: [[String: Any]] = [["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l",
                                       "presetCount": 1, "authors": [String](), "locked": false]]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private struct Rig {
        let presets: PresetCoordinator
        let userPresets: UserPresetsCoordinator
        let integrity: LibraryIntegrityCoordinator
        let recents: RecentPresetsStore
    }

    /// `files`: (name, text, id, file kept). `references`: whether to add the five dangling entries.
    private func launch(files: [(String, String, String, Bool)], duplicate: Bool = false, references: Bool) async throws -> Rig {
        let store = UserPresetStore(directory: userDirectory)
        for (name, text, id, kept) in files {
            try store.add(Self.record(name, text, id: id), contents: Data(text.utf8))
            if !kept { try FileManager.default.removeItem(at: storedURL(text)) }
        }
        if duplicate {
            let bytes: [UInt8] = Array(Self.alpha.utf8)
            let origin = PresetDuplicateOrigin(presetID: "included/Alpha.milk", name: "Alpha", packID: "included", packTitle: "Included",
                                               sha256: ContentHash.sha256Hex(bytes), blobHash: ContentHash.gitBlobSHA1Hex(bytes),
                                               licenseStatement: "MIT", requiresLibraryUnlock: false)
            try store.add(Self.record("Alpha copy", Self.alpha, id: "user/copy", duplicateOf: origin), contents: Data(bytes))
            try FileManager.default.removeItem(at: storedURL(Self.alpha))
        }
        let loader = RendererPresetLoader()
        let collections = PresetCollectionStore(directory: base.appendingPathComponent("collections", isDirectory: true))
        let presets = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                        settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                        collections: collections, tags: PresetTagStore(directory: base.appendingPathComponent("tags")))
        let recents = RecentPresetsStore(defaults: defaults)
        presets.recent = RecentPresetsCoordinator(store: recents)
        let overrideStore = PresetOverrideStore(directory: base.appendingPathComponent("overrides", isDirectory: true))
        presets.overrides = PresetOverridesCoordinator(store: overrideStore, presets: presets) { (_: IndexedPreset) async throws -> Data in Data() }
        let userPresets = UserPresetsCoordinator(library: UserPresetLibrary(directory: userDirectory)) { (_: String) in }
        userPresets.connect(presets: presets, loader: loader)
        userPresets.bundledData = { (preset: IndexedPreset) throws -> Data in
            guard preset.id == "included/Alpha.milk" else { throw CocoaError(.fileNoSuchFile) }
            return Data(Self.alpha.utf8)
        }
        await userPresets.load()
        let library = try builtIn()
        await userPresets.prepare(library: library, blockedHashes: [], knownTextures: [])
        presets.attach(library)
        presets.store.toggle("included/Alpha.milk")   // a favorite that resolves
        if references {
            presets.store.toggle(Self.gone)
            _ = try presets.tagStore.add("broken", to: Self.gone)
            _ = try presets.tagStore.add("broken", to: "user/broken")
            _ = try overrideStore.set(1.05, for: "zoom", preset: Self.gone)
            let collection = try XCTUnwrap(presets.createCollection(named: "Party"))
            XCTAssertTrue(presets.changeCollections { _ = try collections.add(Self.gone, to: collection.id) })
            XCTAssertTrue(presets.changeCollections { _ = try collections.add("included/Alpha.milk", to: collection.id) })
            presets.recent?.replaceForUITests([Self.gone, "included/Alpha.milk"])
        }
        let integrity = LibraryIntegrityCoordinator(presets: presets, userPresets: userPresets)
        integrity.announce = { [weak self] (text: String) in self?.announcements.append(text) }
        return Rig(presets: presets, userPresets: userPresets, integrity: integrity, recents: recents)
    }

    private var brokenFiles: [(String, String, String, Bool)] {
        [("Textured", Self.textured, "user/textured", true), ("Lost", Self.lost, "user/lost", false),
         ("Broken", Self.broken, "user/broken", true), ("Clean", Self.clean, "user/clean", true)]
    }

    private func snapshot(_ directory: URL) -> [String: Data] {
        var result: [String: Data] = [:]
        guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return result }
        for case let url as URL in walk where !url.hasDirectoryPath { result[url.lastPathComponent] = try? Data(contentsOf: url) }
        return result
    }

    // MARK: - S1, S2

    func testBrokenFixtureIsReportedOnceEachAndFixAllSafeLeavesOnlyWhatNeedsTheUser() async throws {
        let rig = try await launch(files: brokenFiles, references: true)
        XCTAssertEqual(rig.integrity.resultText, PresetIntegrityText.notChecked)
        await rig.integrity.check()
        let issues = rig.integrity.issues
        XCTAssertEqual(issues.count, 8, issues.map(\.id).joined(separator: "\n"))
        XCTAssertEqual(Set(issues.map(\.id)).count, 8)
        XCTAssertEqual(announcements, ["Found 8 problems."])
        XCTAssertEqual(issues.filter { $0.kind == .missingTexture }.map(\.detail), ["absent"])
        XCTAssertEqual(issues.filter { $0.kind == .missingFile }.map(\.presetID), ["user/lost"])
        XCTAssertEqual(issues.filter { $0.kind == .missingFile }.first?.actions, [.relinkFile, .removePreset])
        XCTAssertEqual(issues.filter { $0.kind == .unparsable }.map(\.presetID), ["user/broken"])
        let dangling = issues.filter { $0.kind == .danglingReference }
        XCTAssertEqual(Set(dangling.compactMap(\.store)), Set(PresetReferenceStore.allCases))
        XCTAssertTrue(dangling.allSatisfy { $0.presetID == Self.gone && $0.actions == [.removeReference] })
        XCTAssertTrue(rig.integrity.hasSafeIssues)

        let filesBefore = snapshot(userDirectory)
        await rig.integrity.fixAllSafe()
        XCTAssertEqual(rig.integrity.resultText, "Removed 5 broken references. Found 3 problems.")
        XCTAssertEqual(rig.integrity.issues.map(\.kind), [.missingTexture, .missingFile, .unparsable])
        XCTAssertFalse(rig.integrity.hasSafeIssues)
        XCTAssertEqual(snapshot(userDirectory), filesBefore, "Fix All Safe never touches a user preset")
        // The stores no longer name the missing ID, and everything that resolves is kept.
        XCTAssertEqual(rig.presets.store.favorites, ["included/Alpha.milk"])
        XCTAssertTrue(rig.presets.tagStore.map.tags(of: Self.gone).isEmpty)
        XCTAssertEqual(rig.presets.tagStore.map.tags(of: "user/broken"), ["broken"])
        XCTAssertTrue(rig.presets.overrides?.store.overrides(for: Self.gone).isEmpty == true)
        XCTAssertEqual(rig.presets.collections.first?.presetIDs, ["included/Alpha.milk"])
        XCTAssertEqual(rig.recents.history.ids, ["included/Alpha.milk"])
        XCTAssertEqual(rig.presets.recent?.ids, ["included/Alpha.milk"])

        // A rescan (a new launch over the same stores) still lists the three until the user acts.
        await rig.integrity.check()
        XCTAssertEqual(rig.integrity.issues.map(\.kind), [.missingTexture, .missingFile, .unparsable])
    }

    func testCleanLibraryHasNoProblems() async throws {
        let rig = try await launch(files: [("Clean", Self.clean, "user/clean", true)], references: false)
        await rig.integrity.check()
        XCTAssertTrue(rig.integrity.issues.isEmpty)
        XCTAssertEqual(rig.integrity.resultText, "No problems found.")
        XCTAssertFalse(rig.integrity.hasSafeIssues)
    }

    // MARK: - S5 and the per-issue fixes

    func testEachUserFixSettlesItsIssue() async throws {
        let rig = try await launch(files: brokenFiles, duplicate: true, references: false)
        await rig.integrity.check()
        XCTAssertEqual(rig.integrity.issues.count, 4)
        let copy = try XCTUnwrap(rig.integrity.issues.first { $0.presetID == "user/copy" })
        XCTAssertEqual(copy.actions, [.relinkFile, .restoreFromLibrary, .removePreset])

        // Re-import with another file: refused, nothing written; with the original: restored byte for byte.
        let lostIssue = try XCTUnwrap(rig.integrity.issues.first { $0.presetID == "user/lost" })
        await rig.integrity.relink(lostIssue, with: Data(Self.clean.utf8))
        XCTAssertTrue(rig.integrity.resultText.hasPrefix(PresetIntegrityText.checksumMismatch))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL(Self.lost).path))
        await rig.integrity.relink(lostIssue, with: Data(Self.lost.utf8))
        XCTAssertTrue(rig.integrity.resultText.hasPrefix("Restored “Lost”."), rig.integrity.resultText)
        XCTAssertEqual(try Data(contentsOf: storedURL(Self.lost)), Data(Self.lost.utf8))

        await rig.integrity.apply(.restoreFromLibrary, to: copy)
        XCTAssertTrue(rig.integrity.resultText.hasPrefix("Restored “Alpha copy”."), rig.integrity.resultText)
        XCTAssertEqual(try Data(contentsOf: storedURL(Self.alpha)), Data(Self.alpha.utf8))

        let textured = try XCTUnwrap(rig.integrity.issues.first { $0.kind == .missingTexture })
        await rig.integrity.apply(.moveToQuarantine, to: textured)
        XCTAssertTrue(rig.userPresets.quarantined.contains { $0.id == "user/textured" && $0.quarantine?.kind == .movedByUser })

        let broken = try XCTUnwrap(rig.integrity.issues.first { $0.kind == .unparsable })
        await rig.integrity.apply(.removePreset, to: broken)
        XCTAssertFalse(rig.userPresets.allRecords.contains { $0.id == "user/broken" })
        XCTAssertTrue(rig.integrity.issues.isEmpty, rig.integrity.issues.map(\.id).joined(separator: "\n"))
        XCTAssertEqual(rig.integrity.resultText, "Removed “Broken”. No problems found.")
    }
}
