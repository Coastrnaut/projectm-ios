// PRE-008-T12 (spec PRE-008-S4): smart collections through PresetCoordinator. A smart collection's scope walks
// its members, a tag added later joins it at once, a rule edit updates it exactly, and deleting it makes the
// scope fall back. A synthetic library, a fake loader, stores in a temporary directory.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetSmartCollectionAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!

    override func setUp() async throws {
        suite = "PresetSmartCollectionAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    final class FakeLoader: PresetLoading {
        var loaded: [String] = []
        func load(_ preset: IndexedPreset) async throws { loaded.append(preset.name) }
    }

    private func library() throws -> PresetLibrary {
        func record(_ name: String, _ source: String) -> [String: Any] {
            let id = "\(source)/\(name).milk"
            return ["id": id, "name": name, "author": "A", "source": source, "folder": [String](), "path": id, "hash": "h-\(name)"]
        }
        let records: [[String: Any]] = ["Alpha", "Beta", "Gamma"].map { record($0, "included") } + [record("Zeta", "en-d")]
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 3, "authors": [], "locked": false],
            ["id": "en-d", "title": "En D", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 1, "authors": [], "locked": false],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func makeCoordinator(_ loader: FakeLoader) throws -> PresetCoordinator {
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                            collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory),
                                            smart: PresetSmartCollectionStore(directory: directory))
        coordinator.attach(try library())
        return coordinator
    }

    private func preset(_ name: String, _ coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    func testTheScopeWalksMembersAndFollowsTagsAndRuleEdits() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader)
        XCTAssertTrue(coordinator.addTag("Calm", to: try preset("Alpha", coordinator)))
        XCTAssertTrue(coordinator.addTag("Calm", to: try preset("Gamma", coordinator)))
        let smart = try XCTUnwrap(coordinator.createSmartCollection(named: "Calm", match: .all,
                                                                     conditions: [PresetSmartCondition(.tag, ["Calm"])]))
        XCTAssertTrue(PresetSmartCollection.isSmartID(smart.id))
        XCTAssertEqual(coordinator.smartListing(smart.id).map(\.name), ["Alpha", "Gamma"])

        // The scope walks the members.
        await coordinator.choose(try preset("Alpha", coordinator), from: .collection(smart.id))
        XCTAssertEqual(coordinator.scope, .collection(smart.id))
        XCTAssertEqual(coordinator.members.map(\.name), ["Alpha", "Gamma"])
        XCTAssertTrue(coordinator.scopeLine.hasPrefix("Calm · 2"), coordinator.scopeLine)
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "Gamma")

        // A tag added later joins at once; Zeta matches twice under Any (tag and pack) and is listed once.
        XCTAssertTrue(coordinator.addTag("calm", to: try preset("Zeta", coordinator)))
        XCTAssertEqual(coordinator.members.map(\.name), ["Alpha", "Gamma", "Zeta"])
        XCTAssertTrue(coordinator.updateSmartCollection(smart.id, match: .any,
                                                        conditions: [PresetSmartCondition(.tag, ["Calm"]), PresetSmartCondition(.pack, ["en-d"])]))
        XCTAssertEqual(coordinator.members.map(\.name), ["Alpha", "Gamma", "Zeta"])

        // Switch to All: only presets with the tag in En D.
        XCTAssertTrue(coordinator.updateSmartCollection(smart.id, match: .all,
                                                        conditions: [PresetSmartCondition(.tag, ["Calm"]), PresetSmartCondition(.pack, ["en-d"])]))
        XCTAssertEqual(coordinator.smartCount(smart.id), 1)
        XCTAssertEqual(coordinator.smartDraftCount(match: .any, conditions: [PresetSmartCondition(.pack, ["included"])]), 3)

        // Favorites join a favorite rule at once.
        coordinator.toggleFavorite(try preset("Beta", coordinator))
        XCTAssertEqual(coordinator.smartDraftCount(match: .all, conditions: [PresetSmartCondition(.favorite)]), 1)

        // Relaunch keeps the rules; deleting the scope's collection falls back.
        XCTAssertEqual(PresetSmartCollectionStore(directory: directory).collections, coordinator.smartCollections)
        coordinator.deleteSmartCollection(smart.id)
        XCTAssertNotEqual(coordinator.scope, .collection(smart.id))
        XCTAssertNil(coordinator.collectionsMessage)
    }

    func testSmartRowLabelAndDraftRules() {
        XCTAssertEqual(PresetCoordinator.smartRowLabel(name: "Calm", count: 1_234), "Calm, smart collection, 1,234 presets")
        var draft = SmartRulesDraft(PresetSmartCollection(id: "smart-x", name: "X", match: .any,
                                                          conditions: [PresetSmartCondition(kind: "bpm", values: ["1"]),
                                                                       PresetSmartCondition(.pack, ["en-d"])]))
        draft.toggle(.tag, "Calm")
        draft.toggle(.favorite, "")
        draft.toggle(.pack, "en-d")
        XCTAssertEqual(draft.conditions, [PresetSmartCondition(.tag, ["Calm"]), PresetSmartCondition(.favorite),
                                          PresetSmartCondition(kind: "bpm", values: ["1"])], "unknown kinds kept, last")
    }
}
