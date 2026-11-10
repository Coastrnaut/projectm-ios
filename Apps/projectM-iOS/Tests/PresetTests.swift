// Feature 001 T088 and feature 002 T216, T230, T245, T246: presets, favorites and scopes over the
// library (FR-043-FR-045, FR-065, FR-088; feature 002 FR-104, FR-106-FR-109, FR-114-FR-119,
// FR-123). Favorites and the last preset persist under `favorites` and `lastPresetID`; the scope
// under `settings.presetScope`; lists are alphabetical; Next/Previous wrap within the scope; Random
// never repeats; locked presets never play; a failed load keeps the previous preset, reports it and
// is excluded for the session.
import PresetLibrary
import Rendering
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "PresetTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    /// Records loads; fails for the ids in `failing`.
    final class FakeLoader: PresetLoading {
        var failing: Set<String> = []
        var loaded: [String] = []
        func load(_ preset: IndexedPreset) async throws {
            if failing.contains(preset.id) { throw CocoaError(.fileReadCorruptFile) }
            loaded.append(preset.id)
        }
    }

    private static func record(_ id: String, _ name: String, _ source: String, _ folder: [String] = []) -> [String: Any] {
        ["id": id, "name": name, "author": "A", "source": source, "folder": folder, "path": id,
         "hash": String(repeating: "0", count: 40)]
    }

    /// Included presets named `included`, plus a small cream-of-the-crop pack with two folders.
    private func library(included: [String] = ["Zeta", "alpha", "Beta 10", "Beta 2"]) throws -> PresetLibrary {
        var records = included.map { Self.record("frontend-uwp/\($0).milk", $0, "included") }
        records += [Self.record("cream-of-the-crop/F/S/c1.milk", "C1", "cream-of-the-crop", ["F", "S"]),
                    Self.record("cream-of-the-crop/F/S/c2.milk", "C2", "cream-of-the-crop", ["F", "S"]),
                    Self.record("cream-of-the-crop/F/S/c3.milk", "C3", "cream-of-the-crop", ["F", "S"]),
                    Self.record("cream-of-the-crop/G/g1.milk", "G1", "cream-of-the-crop", ["G"])]
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": included.count, "authors": [], "locked": false],
            ["id": "cream-of-the-crop", "title": "Cream of the Crop", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 4, "authors": [], "locked": true],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func makeCoordinator(_ library: PresetLibrary, loader: FakeLoader = FakeLoader()) -> PresetCoordinator {
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader)
        coordinator.attach(library)
        return coordinator
    }

    // MARK: - FavoritesStore (FR-044, FR-065)

    func testFavoritesPersistUnderTheFavoritesKey() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle("pack/b.milk")
        store.toggle("pack/a.milk")
        XCTAssertTrue(store.isFavorite("pack/a.milk"))
        let reopened = FavoritesStore(defaults: defaults)
        XCTAssertEqual(reopened.favorites, ["pack/a.milk", "pack/b.milk"])
        XCTAssertEqual(Set(defaults.stringArray(forKey: "favorites") ?? []), ["pack/a.milk", "pack/b.milk"])
        reopened.toggle("pack/a.milk")
        XCTAssertFalse(FavoritesStore(defaults: defaults).isFavorite("pack/a.milk"))
    }

    func testLastPresetPersistsUnderLastPresetID() {
        let store = FavoritesStore(defaults: defaults)
        store.lastPresetID = "pack/x.milk"
        XCTAssertEqual(defaults.string(forKey: "lastPresetID"), "pack/x.milk")
        XCTAssertEqual(FavoritesStore(defaults: defaults).lastPresetID, "pack/x.milk")
    }

    func testOnlyTheFR065KeysAreWritten() async throws {
        let coordinator = makeCoordinator(try library())
        coordinator.toggleFavorite(coordinator.members[0])
        await coordinator.select(coordinator.members[1], in: .favorites)
        let written = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        XCTAssertEqual(written, ["favorites", "lastPresetID", "settings.presetScope"], "feature 002 FR-123")
    }

    // MARK: - Included behaves as release 1.0 (SC-107, FR-104)

    func testIncludedOrderIsAlphabeticalAsIn1_0() throws {
        let coordinator = makeCoordinator(try library())
        XCTAssertEqual(coordinator.scope, .included)
        XCTAssertEqual(coordinator.members.map(\.name), ["alpha", "Beta 2", "Beta 10", "Zeta"])
    }

    /// SC-107 against the real bundled index: before purchase the scope is exactly the 28 Included
    /// presets, in the order release 1.0's PresetRepository gives.
    func testBundledIncludedScopeMatchesRelease1_0() async throws {
        let lib = try await PresetLibrary.load(from: .main)
        let coordinator = makeCoordinator(lib)
        let names = coordinator.members.map(\.name)
        XCTAssertEqual(names.count, 28)
        XCTAssertTrue(coordinator.members.allSatisfy(\.isIncluded))
        let release1_0 = try PresetRepository(presetsFolder: XCTUnwrap(Bundle.main.url(forResource: "Presets", withExtension: nil))).load()
        XCTAssertEqual(names, release1_0.presets.map(\.name), "release 1.0's catalog order")
        XCTAssertGreaterThan(lib.presets.count, 12_000, "the whole library is indexed")
    }

    func testNextAndPreviousWrapAround() async throws {
        let coordinator = makeCoordinator(try library(included: ["a", "b", "c"]))
        await coordinator.select(coordinator.members[2])
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "a")
        await coordinator.previous()
        XCTAssertEqual(coordinator.current?.name, "c")
    }

    func testRandomNeverReturnsTheCurrentPreset() async throws {
        let coordinator = makeCoordinator(try library(included: ["a", "b", "c", "d"]))
        await coordinator.select(coordinator.members[0])
        for _ in 0..<200 {
            let before = coordinator.current
            await coordinator.random()
            XCTAssertNotEqual(coordinator.current, before)
            XCTAssertTrue(coordinator.current?.isIncluded == true, "never a locked preset")
        }
    }

    func testRandomWithOnePresetKeepsIt() async throws {
        let coordinator = makeCoordinator(try library(included: ["only"]))
        await coordinator.select(coordinator.members[0])
        await coordinator.random()
        XCTAssertEqual(coordinator.current?.name, "only")
    }

    func testSelectionIsRememberedAndA1_0FavoriteStillResolves() async throws {
        let store = FavoritesStore(defaults: defaults)
        store.toggle("frontend-uwp/b.milk")                          // saved by release 1.0
        store.toggle("frontend-uwp/gone.milk")                       // no longer in the library
        let coordinator = makeCoordinator(try library(included: ["a", "b"]))
        XCTAssertEqual(coordinator.favoritesListing.map(\.name), ["b"])
        XCTAssertEqual(FavoritesStore(defaults: defaults).favorites, ["frontend-uwp/b.milk"], "missing favorites dropped at launch")
        await coordinator.select(coordinator.members[1])
        XCTAssertEqual(FavoritesStore(defaults: defaults).lastPresetID, "frontend-uwp/b.milk")
        XCTAssertEqual(makeCoordinator(try library(included: ["a", "b"])).initialPreset?.name, "b")
    }

    // MARK: - Favorites (FR-044, FR-088, FR-114)

    func testFavoritesFilterAcrossPacksAndEmptyState() throws {
        let lib = try library(included: ["a", "b"])
        let coordinator = makeCoordinator(lib)
        coordinator.favoritesOnly = true
        XCTAssertEqual(coordinator.emptyStateText, "No favorites yet — tap the star on a preset to add one.")
        coordinator.toggleFavorite(try XCTUnwrap(lib.preset(id: "cream-of-the-crop/G/g1.milk")))
        coordinator.toggleFavorite(coordinator.members[0])
        XCTAssertEqual(coordinator.favoritesListing.map(\.name), ["a", "G1"], "alphabetical across packs, locked listed")
        XCTAssertNil(coordinator.emptyStateText)
    }

    // MARK: - Failures (FR-045, FR-118)

    func testFailedLoadKeepsThePreviousPresetReportsAndExcludesIt() async throws {
        let loader = FakeLoader()
        let coordinator = makeCoordinator(try library(included: ["a", "b", "c"]), loader: loader)
        await coordinator.select(coordinator.members[0])
        loader.failing = ["frontend-uwp/b.milk"]
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "a", "the running preset stays")
        XCTAssertEqual(coordinator.failureMessage, "Preset could not be loaded")
        XCTAssertEqual(coordinator.members.map(\.name), ["a", "c"], "excluded for the session")
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "c")
        XCTAssertNil(coordinator.failureMessage, "a successful load clears the banner")
    }

    // MARK: - Scopes, locks, purchase transitions (FR-106-FR-109, FR-116-FR-119)

    func testChoosingFromAFolderSetsTheScopeAndNextWrapsInside() async throws {
        let lib = try library()
        let coordinator = makeCoordinator(lib)
        await coordinator.setUnlocked(true)
        let folder = PresetScope.folder("cream-of-the-crop", ["F", "S"])
        await coordinator.choose(try XCTUnwrap(lib.preset(id: "cream-of-the-crop/F/S/c3.milk")), from: folder)
        XCTAssertEqual(coordinator.scope, folder)
        XCTAssertEqual(coordinator.scopeLine, "F › S · 3")
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "C1", "wraps inside the folder")
        for _ in 0..<50 {
            await coordinator.random()
            XCTAssertTrue(coordinator.current?.folder == ["F", "S"], "Random stays in the scope")
        }
        XCTAssertEqual(defaults.string(forKey: AppSettings.presetScopeKey), "folder:cream-of-the-crop/F/S")
    }

    func testLockedPresetAsksForThePurchaseAndPlaysAfterUnlock() async throws {
        let lib = try library()
        let loader = FakeLoader()
        let coordinator = makeCoordinator(lib, loader: loader)
        let locked = try XCTUnwrap(lib.preset(id: "cream-of-the-crop/G/g1.milk"))
        await coordinator.choose(locked, from: .pack("cream-of-the-crop"))
        XCTAssertTrue(coordinator.purchaseRequested)
        XCTAssertTrue(loader.loaded.isEmpty, "nothing locked plays")
        await coordinator.setUnlocked(true)
        XCTAssertEqual(coordinator.scope, .pack("cream-of-the-crop"), "FR-119")
        XCTAssertEqual(coordinator.current, locked, "the tapped preset plays (FR-107)")
    }

    func testRefundFallsBackToIncludedAndTheCurrentPresetKeepsPlaying() async throws {
        let lib = try library()
        let coordinator = makeCoordinator(lib)
        await coordinator.setUnlocked(true)
        await coordinator.select(try XCTUnwrap(lib.preset(id: "cream-of-the-crop/G/g1.milk")))
        await coordinator.setUnlocked(false)
        XCTAssertEqual(coordinator.scope, .included)
        XCTAssertEqual(coordinator.current?.name, "G1", "keeps playing (FR-109)")
        await coordinator.next()
        XCTAssertTrue(coordinator.current?.isIncluded == true)
    }

    func testSearchScopeIsStoredAsAllAndAStaleScopeFallsBack() async throws {
        let lib = try library()
        let coordinator = makeCoordinator(lib)
        await coordinator.setUnlocked(true)
        await coordinator.choose(try XCTUnwrap(lib.preset(id: "cream-of-the-crop/G/g1.milk")), from: .search("g1"))
        XCTAssertEqual(defaults.string(forKey: AppSettings.presetScopeKey), "all", "no search text stored")
        defaults.set("pack:removed-pack", forKey: AppSettings.presetScopeKey)
        XCTAssertEqual(makeCoordinator(lib).scope, .included, "unresolvable stored scope falls back before purchase")
    }

    func testNextInALockedPackRequestsThePurchase() async throws {
        let coordinator = makeCoordinator(try library())
        defaults.set("pack:cream-of-the-crop", forKey: AppSettings.presetScopeKey)
        let locked = makeCoordinator(try library())
        XCTAssertTrue(locked.members.isEmpty)
        await locked.next()
        XCTAssertTrue(locked.purchaseRequested)
        _ = coordinator
    }
}
