// RecentPresetsAcceptanceTests.swift — PRE-006-T08, T10-T12 (specs/159-pre-006-recent-history; S1-S3):
// the roadmap acceptance "Clear deletes history and does not alter favorites", in the app. Favorites,
// the last preset, a tags file (written by the real tag store) and a history are seeded; Clear History
// empties the history while `favorites` and `lastPresetID` stay byte-identical and the tags file's bytes
// are unchanged. Also: the 3 s dwell through PresetCoordinator.select (fake loader, injected clock and
// scheduler; no wall-clock assertions), dedup, a relaunch, the opt-out, and the keys' backup and erase
// classification.
import LibraryBackup
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class RecentPresetsAcceptanceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var clock: Double = 1_000
    /// Scheduled timer work and when it fires (on the fake clock).
    private var scheduled: [(at: Double, work: @MainActor () -> Void)] = []
    private var spoken: [String] = []

    override func setUp() async throws {
        suite = "RecentPresetsAcceptanceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.set(true, forKey: RecentPresetsStore.enabledKey)   // the user turned history on (it is opt-in)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        clock = 1_000
        scheduled = []
        spoken = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    final class FakeLoader: PresetLoading {
        var failing: Set<String> = []
        func load(_ preset: IndexedPreset) async throws {
            if failing.contains(preset.name) { throw NSError(domain: "test", code: 1) }
        }
    }

    private static func record(_ name: String) -> [String: Any] {
        ["id": "frontend-uwp/\(name).milk", "name": name, "author": "A", "source": "included", "folder": [String](),
         "path": "frontend-uwp/\(name).milk", "hash": String(repeating: "0", count: 40)]
    }

    private func makeLibrary() throws -> PresetLibrary {
        let records: [[String: Any]] = ["Alpha", "Beta", "Gamma", "Delta"].map(Self.record)
        let packs: [[String: Any]] = [["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l",
                                       "presetCount": 4, "authors": [String](), "locked": false]]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func makeRecent() -> RecentPresetsCoordinator {
        let recent = RecentPresetsCoordinator(store: RecentPresetsStore(defaults: defaults),
                                              now: { [unowned self] () -> Double in self.clock },
                                              schedule: { [unowned self] (delay: Double, work: @escaping @MainActor () -> Void) in
                                                  self.scheduled.append((at: self.clock + delay, work: work))
                                              })
        recent.announce = { [unowned self] (text: String) in self.spoken.append(text) }
        return recent
    }

    private func makeCoordinator(loader: FakeLoader = FakeLoader()) throws -> PresetCoordinator {
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                            collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory))
        coordinator.attach(try makeLibrary())
        coordinator.recent = makeRecent()
        return coordinator
    }

    private func preset(_ name: String, _ coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    /// Moves the fake clock on and runs the timer work that comes due (what the real timer does).
    private func advance(_ seconds: Double) {
        clock += seconds
        let due = scheduled.filter { (item: (at: Double, work: @MainActor () -> Void)) -> Bool in item.at <= clock }
        scheduled.removeAll { (item: (at: Double, work: @MainActor () -> Void)) -> Bool in item.at <= clock }
        for item in due { item.work() }
    }

    /// Shows `name` (a select through PresetCoordinator) and lets `seconds` pass.
    private func show(_ name: String, for seconds: Double, _ coordinator: PresetCoordinator) async throws {
        await coordinator.select(try preset(name, coordinator))
        advance(seconds)
    }

    private func plist(_ key: String) throws -> Data {
        let value = try XCTUnwrap(defaults.object(forKey: key), key)
        return try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    // MARK: - S1: the roadmap acceptance

    func testClearDeletesHistoryAndDoesNotAlterFavoritesLastPresetOrTags() async throws {
        let coordinator = try makeCoordinator()
        coordinator.toggleFavorite(try preset("Alpha", coordinator))
        coordinator.toggleFavorite(try preset("Gamma", coordinator))
        XCTAssertTrue(coordinator.addTag("Calm", to: try preset("Beta", coordinator)))
        try await show("Beta", for: 3, coordinator)
        try await show("Delta", for: 3, coordinator)
        let recent = try XCTUnwrap(coordinator.recent)
        XCTAssertEqual(recent.ids, ["frontend-uwp/Delta.milk", "frontend-uwp/Beta.milk"])
        let favoritesBefore = try plist(FavoritesStore.favoritesKey)
        let lastBefore = try plist(FavoritesStore.lastPresetKey)
        let tagsURL = directory.appendingPathComponent(PresetTagStore.fileName)
        let tagsBefore = try Data(contentsOf: tagsURL)
        let scopeBefore = defaults.object(forKey: AppSettings.presetScopeKey) as? String

        recent.clear()

        XCTAssertEqual(recent.ids, [])
        XCTAssertNil(defaults.object(forKey: RecentPresetsStore.historyKey), "history is deleted")
        XCTAssertEqual(try plist(FavoritesStore.favoritesKey), favoritesBefore, "favorites byte-identical")
        XCTAssertEqual(try plist(FavoritesStore.lastPresetKey), lastBefore, "lastPresetID byte-identical")
        XCTAssertEqual(try Data(contentsOf: tagsURL), tagsBefore, "tags file unchanged")
        XCTAssertEqual(defaults.object(forKey: AppSettings.presetScopeKey) as? String, scopeBefore)
        XCTAssertEqual(coordinator.favoritesListing.map(\.name), ["Alpha", "Gamma"])
        XCTAssertEqual(spoken.last, RecentPresetsCoordinator.clearedText)
        XCTAssertTrue(recent.isEnabled, "clearing keeps recording on")
    }

    // MARK: - S2: the dwell rule, dedup and relaunch

    func testOnlyPresetsShownForThreeSecondsAreRecordedNewestFirstAndOnce() async throws {
        let loader = FakeLoader()
        loader.failing = ["Gamma"]
        let coordinator = try makeCoordinator(loader: loader)
        try await show("Alpha", for: 3, coordinator)
        try await show("Beta", for: 1, coordinator)      // a flick
        try await show("Delta", for: 2.5, coordinator)   // not yet
        try await show("Gamma", for: 5, coordinator)     // fails to load: Delta stays on screen
        try await show("Alpha", for: 3, coordinator)     // again: moves to the front
        let recent = try XCTUnwrap(coordinator.recent)
        XCTAssertEqual(recent.ids, ["frontend-uwp/Alpha.milk", "frontend-uwp/Delta.milk"],
                       "Beta (1 s) and the failed Gamma are not recorded; Delta stayed 7.5 s in all")
        XCTAssertEqual(recent.listing(in: coordinator.library).map(\.name), ["Alpha", "Delta"])

        let relaunched = makeRecent()   // a new store over the same defaults, as at launch
        XCTAssertEqual(relaunched.ids, recent.ids)
    }

    func testAPresetThatLeftTheLibraryIsNotListed() throws {
        defaults.set(["frontend-uwp/Gone.milk", "frontend-uwp/Beta.milk"], forKey: RecentPresetsStore.historyKey)
        let coordinator = try makeCoordinator()
        XCTAssertEqual(coordinator.recent?.listing(in: coordinator.library).map(\.name), ["Beta"])
        XCTAssertEqual(RecentPresetsCoordinator.rowLabel(count: 1), "Recently Played, 1 preset")
    }

    // MARK: - S3: opt-out

    func testTurningOffClearsAndStopsRecordingAndOnStartsEmpty() async throws {
        let coordinator = try makeCoordinator()
        let recent = try XCTUnwrap(coordinator.recent)
        try await show("Alpha", for: 3, coordinator)
        await coordinator.select(try preset("Beta", coordinator))   // still dwelling when the switch goes off
        recent.setEnabled(false)
        advance(10)
        XCTAssertEqual(recent.ids, [])
        XCTAssertNil(defaults.object(forKey: RecentPresetsStore.historyKey))
        XCTAssertEqual(defaults.object(forKey: RecentPresetsStore.enabledKey) as? Bool, false)
        try await show("Gamma", for: 5, coordinator)
        XCTAssertEqual(recent.ids, [], "nothing is recorded while off")
        XCTAssertEqual(spoken.last, RecentPresetsCoordinator.turnedOffText)

        recent.setEnabled(true)
        try await show("Delta", for: 3, coordinator)
        XCTAssertEqual(recent.ids, ["frontend-uwp/Delta.milk"])
        XCTAssertEqual(spoken.last, RecentPresetsCoordinator.turnedOnText)
    }

    func testAnOffSwitchFoundAtLaunchRemovesStoredHistory() {
        defaults.set(false, forKey: RecentPresetsStore.enabledKey)   // e.g. restored from a backup
        defaults.set(["frontend-uwp/Alpha.milk"], forKey: RecentPresetsStore.historyKey)
        let recent = makeRecent()
        XCTAssertFalse(recent.isEnabled)
        XCTAssertEqual(recent.ids, [])
        XCTAssertNil(defaults.object(forKey: RecentPresetsStore.historyKey))
    }

    // MARK: - Backup and erase policy (R7)

    func testTheKeysAgreeWithTheBackupAndErasePolicy() {
        XCTAssertEqual(RecentPresetsStore.historyKey, LibrarySettingsPolicy.recentPresetsKey)
        XCTAssertEqual(RecentPresetsStore.enabledKey, LibrarySettingsPolicy.recentPresetsEnabledKey)
        XCTAssertTrue(LibrarySettingsPolicy.excludedKeys.contains(RecentPresetsStore.historyKey), "never backed up")
        XCTAssertTrue(LibrarySettingsPolicy.isIncluded(RecentPresetsStore.enabledKey))
        XCTAssertTrue(LibraryErasePolicy.settingKeys(.collections).contains(RecentPresetsStore.historyKey))
        XCTAssertTrue(LibraryErasePolicy.settingKeys(.settings).contains(RecentPresetsStore.enabledKey))
        defaults.set(["frontend-uwp/Alpha.milk"], forKey: RecentPresetsStore.historyKey)
        let read = LibrarySettingsBridge.read(defaults, keys: LibrarySettingsPolicy.includedKeys)
        XCTAssertNil(read[RecentPresetsStore.historyKey], "a backup's settings never carry the history")
    }

    /// Opt-in (integrator decision 2026-11-14): with the switch never touched, a 3 s dwell records nothing.
    func testByDefaultHistoryIsOffAndNothingIsRecorded() async throws {
        defaults.removeObject(forKey: RecentPresetsStore.enabledKey)
        let coordinator = try makeCoordinator()
        let recent = try XCTUnwrap(coordinator.recent)
        XCTAssertFalse(recent.isEnabled, "off by default")
        try await show("Alpha", for: 3, coordinator)
        try await show("Beta", for: 10, coordinator)
        XCTAssertEqual(recent.ids, [])
        XCTAssertNil(defaults.object(forKey: RecentPresetsStore.historyKey), "nothing stored")
        XCTAssertNil(defaults.object(forKey: RecentPresetsStore.enabledKey), "the switch is not written either")
        XCTAssertEqual(scheduled.count, 0, "no dwell timer while off")
    }
}
