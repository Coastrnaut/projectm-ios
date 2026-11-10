// Task T088: presets and favorites (FR-043, FR-044, FR-045, FR-065, FR-088). Favorites and the last
// preset persist under `favorites` and `lastPresetID` only; the list is alphabetical by display
// name; Random never returns the current preset; the favorites filter has its empty-state text; a
// failed load keeps the previous preset and reports "Preset could not be loaded".
import Rendering
import XCTest
@testable import ProjectMiOS

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

    private func preset(_ name: String) -> Preset {
        Preset(id: "pack/\(name).milk", name: name, fileURL: URL(fileURLWithPath: "/tmp/\(name).milk"))
    }

    /// Records loads; fails for the ids in `failing`.
    final class FakeLoader: PresetLoading {
        var failing: Set<String> = []
        var loaded: [String] = []
        func load(_ preset: Preset) async throws {
            if failing.contains(preset.id) { throw CocoaError(.fileReadCorruptFile) }
            loaded.append(preset.id)
        }
    }

    private func makeCoordinator(_ names: [String], loader: FakeLoader = FakeLoader()) -> PresetCoordinator {
        PresetCoordinator(presets: names.map(preset), store: FavoritesStore(defaults: defaults), loader: loader)
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

    func testOnlyTheFR065KeysAreWritten() {
        let store = FavoritesStore(defaults: defaults)
        store.toggle("pack/a.milk")
        store.lastPresetID = "pack/a.milk"
        let written = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        XCTAssertEqual(written, ["favorites", "lastPresetID"])
    }

    // MARK: - Order, navigation, random (FR-043, FR-088)

    func testPresetsAreAlphabeticalByDisplayName() {
        let coordinator = makeCoordinator(["Zeta", "alpha", "Beta 10", "Beta 2"])
        XCTAssertEqual(coordinator.browserItems.map(\.name), ["alpha", "Beta 2", "Beta 10", "Zeta"])
    }

    func testNextAndPreviousWrapAround() async {
        let coordinator = makeCoordinator(["a", "b", "c"])
        await coordinator.select(coordinator.presets[2])
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "a")
        await coordinator.previous()
        XCTAssertEqual(coordinator.current?.name, "c")
    }

    func testRandomNeverReturnsTheCurrentPreset() async {
        let coordinator = makeCoordinator(["a", "b", "c", "d"])
        await coordinator.select(coordinator.presets[0])
        for _ in 0..<200 {
            let before = coordinator.current
            await coordinator.random()
            XCTAssertNotEqual(coordinator.current, before)
        }
    }

    func testRandomWithOnePresetKeepsIt() async {
        let coordinator = makeCoordinator(["only"])
        await coordinator.select(coordinator.presets[0])
        await coordinator.random()
        XCTAssertEqual(coordinator.current?.name, "only")
    }

    func testSelectionIsRememberedAsTheLastPreset() async {
        let coordinator = makeCoordinator(["a", "b"])
        await coordinator.select(coordinator.presets[1])
        XCTAssertEqual(FavoritesStore(defaults: defaults).lastPresetID, "pack/b.milk")
        let reopened = makeCoordinator(["a", "b"])
        XCTAssertEqual(reopened.initialPreset?.name, "b")
    }

    // MARK: - Favorites filter (FR-044, FR-088)

    func testFavoritesFilterAndEmptyState() {
        let coordinator = makeCoordinator(["a", "b", "c"])
        coordinator.favoritesOnly = true
        XCTAssertEqual(coordinator.browserItems, [])
        XCTAssertEqual(coordinator.emptyStateText, "No favorites yet — tap the star on a preset to add one.")
        coordinator.toggleFavorite(coordinator.presets[2])
        XCTAssertEqual(coordinator.browserItems.map(\.name), ["c"])
        XCTAssertNil(coordinator.emptyStateText)
        coordinator.favoritesOnly = false
        XCTAssertEqual(coordinator.browserItems.count, 3)
    }

    // MARK: - Failures (FR-045)

    func testFailedLoadKeepsThePreviousPresetAndReports() async {
        let loader = FakeLoader()
        let coordinator = makeCoordinator(["a", "b"], loader: loader)
        await coordinator.select(coordinator.presets[0])
        loader.failing = ["pack/b.milk"]
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "a", "the running preset stays")
        XCTAssertEqual(coordinator.failureMessage, "Preset could not be loaded")
        XCTAssertEqual(FavoritesStore(defaults: defaults).lastPresetID, "pack/a.milk")
        loader.failing = []
        await coordinator.next()
        XCTAssertNil(coordinator.failureMessage, "a successful load clears the banner")
    }
}
