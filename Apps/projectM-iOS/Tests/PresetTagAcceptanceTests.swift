// PresetTagAcceptanceTests.swift — PRE-003-T11, T15: the roadmap acceptance in the app ("Tag filter
// returns correct IDs after app relaunch"; PRE-003-S1, S2). Presets are tagged through
// PresetCoordinator, chips filter (AND) to the expected IDs, and a coordinator recreated over the same
// tag store directory (what a relaunch does) gives the same IDs. Also: the tagged scope walks its
// playable presets, edits and chip changes announce, refusals change nothing, search matches tags,
// the app bundle's preset index and packs are unchanged, and the preset and scene tag folds agree.
import PresetLibrary
import ShowControl
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetTagAcceptanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var library: [String] = []
    private var search: [String] = []

    override func setUp() async throws {
        suite = "PresetTagAcceptanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        library = []
        search = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    final class FakeLoader: PresetLoading {
        var loaded: [String] = []
        func load(_ preset: IndexedPreset) async throws { loaded.append(preset.name) }
    }

    private static func record(_ id: String, _ name: String, _ source: String) -> [String: Any] {
        ["id": id, "name": name, "author": "A", "source": source, "folder": source == "included" ? [] : ["F"], "path": id,
         "hash": String(repeating: "0", count: 40)]
    }

    /// Included: Alpha, Beta, Gamma, Delta. Locked pack cream-of-the-crop: C1.
    private func makeLibrary() throws -> PresetLibrary {
        var records = ["Alpha", "Beta", "Gamma", "Delta"].map { Self.record("frontend-uwp/\($0).milk", $0, "included") }
        records.append(Self.record("cream-of-the-crop/F/c1.milk", "C1", "cream-of-the-crop"))
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 4, "authors": [], "locked": false],
            ["id": "cream-of-the-crop", "title": "Cream of the Crop", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 1, "authors": [], "locked": true],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func makeCoordinator(loader: FakeLoader = FakeLoader()) throws -> PresetCoordinator {
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                            collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory))
        coordinator.attach(try makeLibrary())
        coordinator.announceLibrary = { [weak self] (text: String) in self?.library.append(text) }
        coordinator.announceSearch = { [weak self] (text: String) in self?.search.append(text) }
        return coordinator
    }

    private func preset(_ name: String, _ coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    private func ids(_ coordinator: PresetCoordinator) -> Set<String> { Set(coordinator.taggedListing.map(\.id)) }

    func testTagFilterReturnsTheSameIDsAfterRelaunch() throws {
        let first = try makeCoordinator()
        for name in ["Alpha", "Gamma", "C1"] { XCTAssertTrue(first.addTag("Calm", to: try preset(name, first))) }
        XCTAssertTrue(first.addTag("slow", to: try preset("Gamma", first)))
        XCTAssertEqual(library, ["Tagged Alpha Calm.", "Tagged Gamma Calm.", "Tagged C1 Calm.", "Tagged Gamma slow."])
        XCTAssertEqual(first.tagVocabulary, ["Calm", "slow"])

        let calm: Set<String> = ["frontend-uwp/Alpha.milk", "frontend-uwp/Gamma.milk", "cream-of-the-crop/F/c1.milk"]
        first.toggleTag("calm")
        XCTAssertEqual(ids(first), calm)
        XCTAssertEqual(first.taggedListing.map(\.name), ["Alpha", "C1", "Gamma"], "alphabetical, locked listed")
        first.toggleTag("Slow")
        XCTAssertEqual(ids(first), ["frontend-uwp/Gamma.milk"])
        XCTAssertEqual(search, ["3 presets with these tags", "1 preset with these tags"])

        // Relaunch: a new coordinator over the same files; chips are not stored, so select them again.
        let relaunched = try makeCoordinator()
        XCTAssertEqual(relaunched.selectedTags, [])
        XCTAssertNil(relaunched.tagsNotice)
        relaunched.toggleTag("Calm")
        XCTAssertEqual(ids(relaunched), calm)
        relaunched.toggleTag("slow")
        XCTAssertEqual(ids(relaunched), ["frontend-uwp/Gamma.milk"])
        XCTAssertEqual(relaunched.rowLabel(try preset("Gamma", relaunched), locked: false), "Gamma, by A, tags Calm, slow")
    }

    func testTaggedScopeSearchAndRefusals() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader: loader)
        for name in ["Delta", "Beta", "C1"] { coordinator.addTag("Ambient", to: try preset(name, coordinator)) }
        coordinator.toggleTag("Ambient")
        let scope = PresetScope.tagged(coordinator.activeTags)
        await coordinator.choose(try preset("Beta", coordinator), from: scope)
        XCTAssertEqual(coordinator.scopeLine, "Tagged: Ambient · 2", "locked C1 never plays from the tag scope")
        await coordinator.next()
        XCTAssertEqual(loader.loaded, ["Beta", "Delta"])

        // Search matches tags; chips narrow it.
        XCTAssertEqual(Set(coordinator.searchResults("ambi").groups.flatMap(\.presets).map(\.name)), ["Beta", "C1", "Delta"])
        XCTAssertEqual(coordinator.searchResults("a").groups.flatMap(\.presets).map(\.name), ["Beta", "Delta", "C1"])

        // Refusals change nothing and are announced.
        library = []
        XCTAssertFalse(coordinator.addTag("AMBIENT", to: try preset("Beta", coordinator)))
        XCTAssertFalse(coordinator.addTag(String(repeating: "x", count: 41), to: try preset("Beta", coordinator)))
        XCTAssertEqual(library, ["The preset is already tagged Ambient.", "A tag is 1 to 40 characters on one line."])
        XCTAssertEqual(coordinator.tags(of: try preset("Beta", coordinator)), ["Ambient"])

        // Removing the last carrier of a selected tag drops the chip.
        for name in ["Delta", "Beta", "C1"] { coordinator.removeTag("ambient", from: try preset(name, coordinator)) }
        XCTAssertEqual(coordinator.activeTags, [])
        XCTAssertEqual(coordinator.tagVocabulary, [])
        coordinator.pruneTags("frontend-uwp/Alpha.milk")   // nothing to prune: no change, no message
        XCTAssertNil(coordinator.tagsMessage)
    }

    /// PRE-003-S2: the app's bundled index and packs are byte-identical before and after tagging.
    func testBundledPresetIndexIsUnchanged() throws {
        let urls: [URL] = try ["PresetIndex", "PresetPacks"].map { (name: String) -> URL in
            try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"), name)
        }
        func hashes() throws -> [String] {
            try urls.map { (url: URL) -> String in ContentHash.sha256Hex([UInt8](try Data(contentsOf: url))) }
        }
        let before = try hashes()
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: FakeLoader(),
                                            collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory))
        coordinator.attach(try PresetLibrary(index: Data(contentsOf: urls[0]), packs: Data(contentsOf: urls[1])))
        for preset in coordinator.library?.presets.prefix(50) ?? [] { coordinator.addTag("Bundled", to: preset) }
        XCTAssertEqual(coordinator.tagVocabulary, ["Bundled"])
        XCTAssertEqual(try hashes(), before)
    }

    /// Preset tags and SCN-005 scene tags use one identity (case, accents, width).
    func testPresetAndSceneTagFoldsAgree() {
        for sample in ["Calm", "ÇALM", "Ｃａｌｍ", "naïve Ünïcode", "Straße"] {
            XCTAssertEqual(PresetTagMap.fold(sample), SceneTagMap.fold(sample), sample)
        }
    }
}
