// ACC-002-T11, T13, T16: the reduced flash preset policy (specs/030-acc-002-reduced-flash-preset-policy;
// ACC-002-R5-R10, R12; S3). With Reduce flashing on, Next, Previous, Random, the warm-up and the
// launch preset skip flagged presets; choosing one by name waits for Load Anyway or Cancel; rows
// say "may flash". With it off nothing changes. A fake loader records loads; nothing renders.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class FlashPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "FlashPolicyTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: collectionsDirectory)
    }

    private var collectionsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    }

    final class FakeLoader: PresetLoading {
        var loaded: [String] = []
        var prewarmed: [[String]] = []
        func load(_ preset: IndexedPreset) async throws { loaded.append(preset.name) }
        func prewarm(_ presets: [IndexedPreset]) { prewarmed.append(presets.map(\.name)) }
    }

    private static func record(_ name: String, source: String = "included", flash: [String]? = nil) -> [String: Any] {
        let id = source == "included" ? "frontend-uwp/\(name).milk" : "cream-of-the-crop/\(name).milk"
        var record: [String: Any] = ["id": id, "name": name, "author": "A", "source": source, "folder": [String](),
                                     "path": id, "hash": String(repeating: "0", count: 40)]
        if let flash { record["flash"] = flash }
        return record
    }

    /// Included: A (calm), B (flagged), C (calm), D (calm); locked pack: L (flagged).
    private func library(allFlagged: Bool = false) throws -> PresetLibrary {
        let flagged = ["toggle-driven"]
        let records = ["A", "B", "C", "D"].map { Self.record($0, flash: allFlagged || $0 == "B" ? flagged : nil) }
            + [Self.record("L", source: "cream-of-the-crop", flash: flagged)]
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 4, "authors": [String](), "locked": false],
            ["id": "cream-of-the-crop", "title": "Cream of the Crop", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 1, "authors": [String](), "locked": true],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func make(reduceFlashing: Bool, allFlagged: Bool = false,
                      loader: FakeLoader = FakeLoader()) throws -> (PresetCoordinator, AppSettings, FakeLoader) {
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        settings.reduceFlashing = reduceFlashing
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults), settings: settings, loader: loader,
                                            collections: PresetCollectionStore(directory: collectionsDirectory))
        coordinator.attach(try library(allFlagged: allFlagged))
        return (coordinator, settings, loader)
    }

    private func preset(_ coordinator: PresetCoordinator, _ name: String) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name })
    }

    // MARK: - US1: skipped automatically (R5, R8, R9, R10)

    func testNextAndPreviousSkipAFlaggedPresetOnlyWhileReduceFlashingIsOn() async throws {
        let (on, _, onLoader) = try make(reduceFlashing: true)
        await on.select(try preset(on, "A"))
        await on.next()
        XCTAssertEqual(on.current?.name, "C", "B is flagged and skipped")
        await on.previous()
        XCTAssertEqual(on.current?.name, "A")
        XCTAssertFalse(onLoader.loaded.contains("B"))
        XCTAssertEqual(on.walkable.map(\.name), ["A", "C", "D"])
        XCTAssertEqual(on.members.map(\.name), ["A", "B", "C", "D"], "lists and counts keep every member")

        defaults.removePersistentDomain(forName: suite)
        let (off, _, _) = try make(reduceFlashing: false)
        await off.select(try preset(off, "A"))
        await off.next()
        XCTAssertEqual(off.current?.name, "B", "R8: unchanged with Reduce flashing off")
        XCTAssertEqual(off.walkable, off.members)
    }

    func testRandomAndTheWarmUpNeverPickAFlaggedPreset() async throws {
        let (coordinator, _, loader) = try make(reduceFlashing: true)
        await coordinator.select(try preset(coordinator, "A"))
        for _ in 0..<200 { await coordinator.random() }
        XCTAssertEqual(loader.loaded.count, 201)
        XCTAssertFalse(loader.loaded.contains("B"), "S3: 0 of 200 Random picks")
        XCTAssertFalse(loader.prewarmed.joined().contains("B"), "flagged presets are never warmed")
        XCTAssertNotEqual(coordinator.plannedRandom?.name, "B")
    }

    func testAScopeOfOnlyFlaggedPresetsLoadsNothingAndSaysSo() async throws {
        let (coordinator, _, loader) = try make(reduceFlashing: true, allFlagged: true)
        await coordinator.next()
        await coordinator.random()
        await coordinator.previous()
        XCTAssertTrue(loader.loaded.isEmpty)
        XCTAssertEqual(coordinator.failureMessage, "Every preset here may flash.")
        XCTAssertFalse(coordinator.purchaseRequested)
        XCTAssertNil(coordinator.initialPreset, "R10: no flagged launch preset")
    }

    func testTheLaunchPresetIsNeverFlaggedWhileReduceFlashingIsOn() throws {
        FavoritesStore(defaults: defaults).lastPresetID = "frontend-uwp/B.milk"
        let (on, settings, _) = try make(reduceFlashing: true)
        XCTAssertEqual(on.initialPreset?.name, "A")
        settings.reduceFlashing = false
        XCTAssertEqual(on.initialPreset?.name, "B", "off: the last preset is restored as before")
    }

    func testAFlaggedPresetOnScreenKeepsPlayingWhenTheSettingTurnsOn() async throws {
        let (coordinator, settings, loader) = try make(reduceFlashing: false)
        await coordinator.select(try preset(coordinator, "B"))
        settings.reduceFlashing = true
        XCTAssertEqual(coordinator.current?.name, "B", "Edge Cases: no switch under the user")
        XCTAssertEqual(loader.loaded, ["B"])
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "C", "the walk continues forward from its place")
        await coordinator.select(try preset(coordinator, "B"))
        await coordinator.previous()
        XCTAssertEqual(coordinator.current?.name, "A")
    }

    // MARK: - US2: warned before load (R6, R12)

    func testChoosingAFlaggedPresetWaitsForTheUsersDecision() async throws {
        let (coordinator, _, loader) = try make(reduceFlashing: true)
        await coordinator.select(try preset(coordinator, "A"))
        let flagged = try preset(coordinator, "B")
        await coordinator.choose(flagged, from: .all)
        XCTAssertEqual(coordinator.flashWarning, PresetCoordinator.FlashWarning(preset: flagged, scope: .all))
        XCTAssertEqual(loader.loaded, ["A"], "nothing loads before the decision")
        XCTAssertEqual(coordinator.current?.name, "A")

        coordinator.cancelFlashWarning()
        XCTAssertNil(coordinator.flashWarning)
        XCTAssertEqual(loader.loaded, ["A"], "Cancel loads nothing")

        await coordinator.choose(flagged, from: .all)
        await coordinator.confirmFlashWarning()
        XCTAssertNil(coordinator.flashWarning)
        XCTAssertEqual(coordinator.current?.name, "B", "Load Anyway loads it")
        XCTAssertEqual(coordinator.scope, .all, "in the list it was chosen from (FR-116)")

        await coordinator.choose(try preset(coordinator, "C"), from: .included)
        XCTAssertNil(coordinator.flashWarning, "an unflagged preset loads at once")
        XCTAssertEqual(coordinator.current?.name, "C")
        let written = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        XCTAssertEqual(written, ["settings.reduceFlashing", "lastPresetID", "settings.presetScope"], "R12: nothing about the warning is stored")
    }

    func testTheAlertPassesTheWarningItShowed() async throws {
        let (coordinator, _, _) = try make(reduceFlashing: true)
        await coordinator.choose(try preset(coordinator, "B"), from: .included)
        let shown = try XCTUnwrap(coordinator.flashWarning)
        coordinator.cancelFlashWarning()   // SwiftUI may clear the binding before the button's action runs
        await coordinator.confirmFlashWarning(shown)
        XCTAssertEqual(coordinator.current?.name, "B")
    }

    func testWithReduceFlashingOffAFlaggedChoiceLoadsAtOnce() async throws {
        let (coordinator, _, loader) = try make(reduceFlashing: false)
        await coordinator.choose(try preset(coordinator, "B"), from: .included)
        XCTAssertNil(coordinator.flashWarning)
        XCTAssertEqual(loader.loaded, ["B"])
    }

    func testALockedFlaggedPresetAsksForThePurchaseFirstThenWarns() async throws {
        let (coordinator, _, loader) = try make(reduceFlashing: true)
        let locked = try preset(coordinator, "L")
        await coordinator.choose(locked, from: .pack("cream-of-the-crop"))
        XCTAssertTrue(coordinator.purchaseRequested)
        XCTAssertNil(coordinator.flashWarning)
        await coordinator.setUnlocked(true)
        XCTAssertEqual(coordinator.flashWarning?.preset, locked, "after the purchase it is warned, not loaded")
        XCTAssertFalse(loader.loaded.contains("L"))
    }

    // MARK: - US3: the row (R7)

    func testRowLabelsSayMayFlashOnlyWhileReduceFlashingIsOn() throws {
        let (coordinator, settings, _) = try make(reduceFlashing: true)
        let flagged = try preset(coordinator, "B")
        XCTAssertTrue(coordinator.isFlagged(flagged))
        XCTAssertEqual(coordinator.rowLabel(flagged, locked: false), "B, by A, may flash")
        XCTAssertEqual(coordinator.rowLabel(try preset(coordinator, "A"), locked: false), "A, by A")
        settings.reduceFlashing = false
        XCTAssertFalse(coordinator.isFlagged(flagged))
        XCTAssertEqual(coordinator.rowLabel(flagged, locked: false), "B, by A", "R8: the row is unchanged")
        XCTAssertEqual(PresetCoordinator.flashWarningMessage("B"), "“B” may contain fast flashing. Reduce flashing still limits flashes while it plays.")
    }
}
