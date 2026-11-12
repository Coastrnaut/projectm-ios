// PRE-007-T10: preset collections through PresetCoordinator (specs/005-pre-007-preset-collections;
// PRE-007-R1-R15, S1-S5, S7). A synthetic library (two Included presets groups and a locked pack),
// a fake loader and a collections store in a temporary directory.
import PresetLibrary
import XCTest
@testable import projectM_iOS

@MainActor
final class PresetCollectionsCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!

    override func setUp() async throws {
        suite = "PresetCollectionsCoordinatorTests-\(UUID().uuidString)"
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

    private static func record(_ id: String, _ name: String, _ source: String, _ folder: [String] = []) -> [String: Any] {
        ["id": id, "name": name, "author": "A", "source": source, "folder": folder, "path": id,
         "hash": String(repeating: "0", count: 40)]
    }

    private static let includedNames = ["Alpha", "Beta", "Gamma", "Delta"]

    /// Included: Alpha, Beta, Gamma, Delta. Locked pack cream-of-the-crop: C1, C2.
    private func library(dropping dropped: Set<String> = []) throws -> PresetLibrary {
        var records = Self.includedNames.map { Self.record("frontend-uwp/\($0).milk", $0, "included") }
        records += [Self.record("cream-of-the-crop/F/c1.milk", "C1", "cream-of-the-crop", ["F"]),
                    Self.record("cream-of-the-crop/F/c2.milk", "C2", "cream-of-the-crop", ["F"])]
        records.removeAll { dropped.contains($0["name"] as? String ?? "") }
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 4, "authors": [], "locked": false],
            ["id": "cream-of-the-crop", "title": "Cream of the Crop", "sourceURL": "u", "commit": "c", "license": "l", "presetCount": 2, "authors": [], "locked": true],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func makeCoordinator(_ library: PresetLibrary? = nil, loader: FakeLoader = FakeLoader(),
                                 failingWrites: Bool = false) throws -> PresetCoordinator {
        let store = failingWrites
            ? PresetCollectionStore(directory: directory, write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
            : PresetCollectionStore(directory: directory)
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false),
                                            loader: loader, collections: store)
        coordinator.attach(try library ?? self.library())
        return coordinator
    }

    private func preset(_ name: String, in coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    /// A collection holding `names` in that order.
    @discardableResult
    private func fill(_ coordinator: PresetCoordinator, _ title: String, _ names: [String]) throws -> PresetCollection {
        let collection = try XCTUnwrap(coordinator.createCollection(named: title))
        for name in names {
            XCTAssertEqual(coordinator.addToCollection(try preset(name, in: coordinator), collection.id), .added)
        }
        return collection
    }

    private func names(_ coordinator: PresetCoordinator, _ collection: PresetCollection) -> [String] {
        coordinator.collectionListing(collection.id).map(\.name)
    }

    // MARK: - US1: create, fill, rename, delete

    func testCreateAddRemoveAndRename() throws {
        let coordinator = try makeCoordinator()
        XCTAssertEqual(coordinator.collections, [])
        let friday = try fill(coordinator, "  Friday set ", ["Gamma", "Alpha"])
        XCTAssertEqual(coordinator.collections.map(\.name), ["Friday set"])
        XCTAssertEqual(names(coordinator, friday), ["Gamma", "Alpha"], "appended in the order added, not alphabetical")
        XCTAssertEqual(coordinator.collectionCount(friday.id), 2)
        XCTAssertEqual(coordinator.addToCollection(try preset("Alpha", in: coordinator), friday.id), .alreadyThere)
        XCTAssertEqual(names(coordinator, friday), ["Gamma", "Alpha"])
        XCTAssertTrue(coordinator.isInCollection(try preset("Alpha", in: coordinator), friday.id))
        XCTAssertFalse(coordinator.isInCollection(try preset("Beta", in: coordinator), friday.id))
        coordinator.removeFromCollection([try preset("Gamma", in: coordinator)], friday.id)
        XCTAssertEqual(names(coordinator, friday), ["Alpha"])
        XCTAssertTrue(coordinator.renameCollection(friday.id, to: "Saturday"))
        XCTAssertEqual(coordinator.collections.map(\.name), ["Saturday"])
        XCTAssertEqual(names(coordinator, friday), ["Alpha"], "renaming changes nothing else")
        XCTAssertNil(coordinator.collectionsMessage)
    }

    func testRefusedNamesChangeNothingAndGiveTheReason() throws {
        let coordinator = try makeCoordinator()
        try fill(coordinator, "Chill", [])
        XCTAssertNil(coordinator.createCollection(named: "   "))
        XCTAssertEqual(coordinator.collectionsMessage, "Enter a name.")
        coordinator.collectionsMessage = nil
        XCTAssertNil(coordinator.createCollection(named: "chíll"))
        XCTAssertEqual(coordinator.collectionsMessage, "A collection with this name already exists.")
        XCTAssertNil(coordinator.createCollection(named: String(repeating: "x", count: 61)))
        XCTAssertEqual(coordinator.collectionsMessage, "Names can have up to 60 characters.")
        XCTAssertEqual(coordinator.collections.map(\.name), ["Chill"])
        // The live check the name sheet shows.
        XCTAssertEqual(coordinator.collectionNameProblem("", renaming: nil), "Enter a name.")
        XCTAssertEqual(coordinator.collectionNameProblem("CHILL", renaming: nil), "A collection with this name already exists.")
        XCTAssertNil(coordinator.collectionNameProblem("CHILL", renaming: coordinator.collections[0].id), "its own name is fine")
        XCTAssertNil(coordinator.collectionNameProblem("Other", renaming: nil))
    }

    func testDeletingACollectionPreservesPresetsFavoritesAndOtherCollections() throws {
        let coordinator = try makeCoordinator()
        let friday = try fill(coordinator, "Friday set", ["Alpha", "Beta", "C1"])
        let other = try fill(coordinator, "Other", ["Beta", "Delta"])
        coordinator.toggleFavorite(try preset("Beta", in: coordinator))
        coordinator.toggleFavorite(try preset("C1", in: coordinator))
        let libraryBefore = coordinator.library?.presets
        coordinator.deleteCollection(friday.id)
        XCTAssertEqual(coordinator.collections.map(\.name), ["Other"])
        XCTAssertEqual(names(coordinator, other), ["Beta", "Delta"], "S2: the other collection is as before")
        XCTAssertEqual(coordinator.favoritesListing.map(\.name), ["Beta", "C1"], "S2: favorites are untouched")
        XCTAssertEqual(coordinator.library?.presets, libraryBefore, "S2: every preset is still in the library")
        XCTAssertEqual(defaults.stringArray(forKey: FavoritesStore.favoritesKey)?.count, 2)
        XCTAssertNil(coordinator.collectionsMessage)
    }

    func testFavoritesAndCollectionsAreIndependent() throws {
        let coordinator = try makeCoordinator()
        let friday = try fill(coordinator, "Friday set", ["Alpha"])
        let alpha = try preset("Alpha", in: coordinator)
        coordinator.toggleFavorite(alpha)
        coordinator.toggleFavorite(alpha)
        XCTAssertEqual(names(coordinator, friday), ["Alpha"])
        coordinator.toggleFavorite(alpha)
        coordinator.removeFromCollection([alpha], friday.id)
        XCTAssertTrue(coordinator.isFavorite(alpha))
    }

    // MARK: - US2: manual order persists

    func testReorderingPresetsAndCollectionsPersistsAcrossANewCoordinator() throws {
        let coordinator = try makeCoordinator()
        let x = try fill(coordinator, "X", ["Alpha", "Beta", "Gamma"])
        try fill(coordinator, "Y", [])
        try fill(coordinator, "Z", ["Delta"])
        coordinator.movePresets(in: x.id, fromOffsets: [2], toOffset: 0)            // Gamma first
        XCTAssertEqual(names(coordinator, x), ["Gamma", "Alpha", "Beta"])
        coordinator.movePreset(try preset("Beta", in: coordinator), in: x.id, by: -1)   // Move Up
        XCTAssertEqual(names(coordinator, x), ["Gamma", "Beta", "Alpha"])
        coordinator.movePreset(try preset("Gamma", in: coordinator), in: x.id, by: 1)   // Move Down
        XCTAssertEqual(names(coordinator, x), ["Beta", "Gamma", "Alpha"])
        coordinator.movePreset(try preset("Beta", in: coordinator), in: x.id, by: -1)   // already first: nothing
        coordinator.movePreset(try preset("Alpha", in: coordinator), in: x.id, by: 1)   // already last: nothing
        XCTAssertEqual(names(coordinator, x), ["Beta", "Gamma", "Alpha"])
        coordinator.moveCollections(fromOffsets: [2], toOffset: 0)                  // Z first
        XCTAssertEqual(coordinator.collections.map(\.name), ["Z", "X", "Y"])
        coordinator.moveCollection(x.id, by: 1)
        XCTAssertEqual(coordinator.collections.map(\.name), ["Z", "Y", "X"])
        coordinator.moveCollection(x.id, by: 1)                                      // already last
        XCTAssertNil(coordinator.collectionsMessage)

        let relaunched = try makeCoordinator()   // S1: a new store over the same directory
        XCTAssertEqual(relaunched.collections.map(\.name), ["Z", "Y", "X"])
        XCTAssertEqual(names(relaunched, x), ["Beta", "Gamma", "Alpha"])
    }

    func testAFailedSaveIsReportedAndTheShownStateStaysAsSaved() throws {
        let good = try makeCoordinator()
        let x = try fill(good, "X", ["Alpha", "Beta"])
        try fill(good, "Y", [])
        let failing = try makeCoordinator(failingWrites: true)
        failing.movePresets(in: x.id, fromOffsets: [1], toOffset: 0)
        XCTAssertEqual(failing.collectionsMessage, "The change could not be saved. Your collections are unchanged.")
        XCTAssertEqual(names(failing, x), ["Alpha", "Beta"], "S5: what is shown is what is saved")
        failing.collectionsMessage = nil
        failing.moveCollections(fromOffsets: [1], toOffset: 0)
        XCTAssertNotNil(failing.collectionsMessage)
        XCTAssertEqual(failing.collections.map(\.name), ["X", "Y"])
        XCTAssertNil(failing.createCollection(named: "New"))
        XCTAssertEqual(failing.addToCollection(try preset("Gamma", in: failing), x.id), .failed)
        failing.deleteCollection(x.id)
        XCTAssertEqual(try makeCoordinator().collections.map(\.name), ["X", "Y"])
    }

    // MARK: - US3: a collection as the scope

    func testChoosingInACollectionMakesItTheScopeInManualOrder() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader: loader)
        var announced: [String] = []
        coordinator.onScopeChange { announced.append($0) }
        let friday = try fill(coordinator, "Friday set", ["Gamma", "Alpha", "Beta"])
        await coordinator.choose(try preset("Alpha", in: coordinator), from: .collection(friday.id))
        XCTAssertEqual(coordinator.scope, .collection(friday.id))
        XCTAssertEqual(coordinator.current?.name, "Alpha")
        XCTAssertEqual(coordinator.scopeLine, "Friday set · 3")
        XCTAssertEqual(announced, ["Friday set, 3 presets"])
        XCTAssertEqual(defaults.string(forKey: AppSettings.presetScopeKey), "collection:\(friday.id)")
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "Beta")
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "Gamma", "Next wraps to the first in the user's order")
        await coordinator.previous()
        XCTAssertEqual(coordinator.current?.name, "Beta", "Previous wraps to the last")
        for _ in 0..<200 {
            let before = coordinator.current
            await coordinator.random()
            XCTAssertNotEqual(coordinator.current, before)
            XCTAssertTrue(["Gamma", "Alpha", "Beta"].contains(coordinator.current?.name ?? ""), "S4: Random stays inside")
        }
    }

    func testReorderAndRemoveTakeEffectOnNavigationAtOnce() async throws {
        let coordinator = try makeCoordinator()
        let friday = try fill(coordinator, "Friday set", ["Gamma", "Alpha", "Beta"])
        await coordinator.choose(try preset("Gamma", in: coordinator), from: .collection(friday.id))
        coordinator.movePresets(in: friday.id, fromOffsets: [2], toOffset: 1)   // Gamma, Beta, Alpha
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "Beta")
        coordinator.removeFromCollection([try preset("Alpha", in: coordinator)], friday.id)
        XCTAssertEqual(coordinator.scopeLine, "Friday set · 2")
        await coordinator.next()
        XCTAssertEqual(coordinator.current?.name, "Gamma")
        coordinator.renameCollection(friday.id, to: "Saturday")
        XCTAssertEqual(coordinator.scopeLine, "Saturday · 2", "the scope follows the id, not the name")
    }

    func testTheCollectionScopeSurvivesARelaunch() async throws {
        let coordinator = try makeCoordinator()
        let friday = try fill(coordinator, "Friday set", ["Gamma", "Alpha"])
        await coordinator.choose(try preset("Alpha", in: coordinator), from: .collection(friday.id))
        let relaunched = try makeCoordinator()
        XCTAssertEqual(relaunched.scope, .collection(friday.id))
        XCTAssertEqual(relaunched.scopeLine, "Friday set · 2")
        XCTAssertEqual(relaunched.initialPreset?.name, "Alpha", "the last preset")
        XCTAssertEqual(relaunched.members.map(\.name), ["Gamma", "Alpha"])
    }

    func testDeletingTheScopeCollectionFallsBackAndKeepsThePlayingPreset() async throws {
        let coordinator = try makeCoordinator()
        let friday = try fill(coordinator, "Friday set", ["Gamma", "Alpha"])
        await coordinator.choose(try preset("Alpha", in: coordinator), from: .collection(friday.id))
        coordinator.deleteCollection(friday.id)
        XCTAssertEqual(coordinator.scope, .included, "locked library: back to Included")
        XCTAssertEqual(coordinator.current?.name, "Alpha", "the playing preset keeps playing")
        XCTAssertEqual(defaults.string(forKey: AppSettings.presetScopeKey), "included")

        await coordinator.setUnlocked(true)
        let second = try fill(coordinator, "Second", ["C1"])
        await coordinator.choose(try preset("C1", in: coordinator), from: .collection(second.id))
        coordinator.deleteCollection(second.id)
        XCTAssertEqual(coordinator.scope, .all, "unlocked library: back to All")
        XCTAssertEqual(coordinator.current?.name, "C1")
    }

    func testAStoredScopeForAMissingCollectionFallsBackOnAttach() throws {
        defaults.set("collection:does-not-exist", forKey: AppSettings.presetScopeKey)
        let coordinator = try makeCoordinator()
        XCTAssertEqual(coordinator.scope, .included)
        XCTAssertEqual(coordinator.members.map(\.name), ["Alpha", "Beta", "Delta", "Gamma"])
    }

    // MARK: - US4: lock state

    func testLockedEntriesAreListedButNeverPlayedThroughACollection() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader: loader)
        let mix = try fill(coordinator, "Mix", ["C1", "Alpha", "C2", "Beta"])
        XCTAssertEqual(names(coordinator, mix), ["C1", "Alpha", "C2", "Beta"], "locked presets can be added and are listed")
        XCTAssertEqual(coordinator.collectionCount(mix.id), 4, "the row counts listed presets")
        XCTAssertTrue(coordinator.isLocked(try preset("C1", in: coordinator)))

        await coordinator.choose(try preset("C1", in: coordinator), from: .collection(mix.id))
        XCTAssertTrue(coordinator.purchaseRequested, "a locked entry asks for the purchase (FR-106)")
        XCTAssertEqual(loader.loaded, [])
        XCTAssertNil(coordinator.current)
        XCTAssertEqual(coordinator.scope, .included, "and does not change the scope")
        coordinator.purchaseRequested = false

        await coordinator.choose(try preset("Alpha", in: coordinator), from: .collection(mix.id))
        XCTAssertEqual(coordinator.scopeLine, "Mix · 2", "the scope line counts playable presets")
        for _ in 0..<6 { await coordinator.next() }
        for _ in 0..<6 { await coordinator.previous() }
        for _ in 0..<1_000 { await coordinator.random() }
        XCTAssertEqual(Set(loader.loaded), ["Alpha", "Beta"], "S3: zero locked presets played")
        XCTAssertFalse(coordinator.purchaseRequested)
    }

    func testAfterUnlockTheSameEntriesPlayInTheirPositions() async throws {
        let coordinator = try makeCoordinator()
        let mix = try fill(coordinator, "Mix", ["C1", "Alpha", "C2"])
        await coordinator.setUnlocked(true)
        await coordinator.choose(try preset("C1", in: coordinator), from: .collection(mix.id))
        XCTAssertEqual(coordinator.current?.name, "C1")
        XCTAssertEqual(coordinator.members.map(\.name), ["C1", "Alpha", "C2"])
        // A refund: every scope returns to Included (FR-109); the collection is unchanged.
        await coordinator.setUnlocked(false)
        XCTAssertEqual(coordinator.scope, .included)
        XCTAssertEqual(coordinator.current?.name, "C1", "the playing preset keeps playing")
        XCTAssertEqual(names(coordinator, mix), ["C1", "Alpha", "C2"])
    }

    func testACollectionOfOnlyLockedEntriesAsTheScopeDoesNothing() async throws {
        let loader = FakeLoader()
        let coordinator = try makeCoordinator(loader: loader)
        let locked = try fill(coordinator, "Locked", ["C1", "C2"])
        defaults.set("collection:\(locked.id)", forKey: AppSettings.presetScopeKey)
        let relaunched = try makeCoordinator(loader: loader)
        XCTAssertEqual(relaunched.scope, .collection(locked.id))
        XCTAssertEqual(relaunched.members, [])
        await relaunched.next()
        await relaunched.previous()
        await relaunched.random()
        XCTAssertEqual(loader.loaded, [])
        XCTAssertFalse(relaunched.purchaseRequested)
        XCTAssertEqual(relaunched.scopeLine, "Locked · 0")
    }

    // MARK: - Missing presets and unusable saved data (R14, R15)

    func testEntriesMissingFromTheLibraryAreHiddenButKept() throws {
        let full = try makeCoordinator()
        let friday = try fill(full, "Friday set", ["Alpha", "Beta", "Gamma", "Delta"])
        // The next app version's library no longer has Beta.
        let coordinator = try makeCoordinator(try library(dropping: ["Beta"]))
        XCTAssertEqual(names(coordinator, friday), ["Alpha", "Gamma", "Delta"])
        XCTAssertEqual(coordinator.collectionCount(friday.id), 3)
        coordinator.movePresets(in: friday.id, fromOffsets: [2], toOffset: 0)   // Delta first
        XCTAssertEqual(names(coordinator, friday), ["Delta", "Alpha", "Gamma"])
        coordinator.renameCollection(friday.id, to: "Renamed")
        // Beta is back in a later version, in its old slot (second).
        let later = try makeCoordinator()
        XCTAssertEqual(names(later, friday), ["Delta", "Beta", "Alpha", "Gamma"], "S7: the missing entry was kept")
    }

    func testANewerFormatIsShownAsUnavailableAndNothingChanges() async throws {
        let newer = Data(#"{"schemaVersion":7,"collections":[{"id":"n1"}]}"#.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(PresetCollectionStore.fileName)
        try newer.write(to: file)
        defaults.set("collection:n1", forKey: AppSettings.presetScopeKey)
        let coordinator = try makeCoordinator()
        XCTAssertEqual(coordinator.collectionsUnavailableText,
                       "These collections were saved by a newer version of the app. Update the app to use them.")
        XCTAssertEqual(coordinator.collections, [])
        XCTAssertEqual(coordinator.scope, .included, "a stored collection scope falls back")
        XCTAssertNil(coordinator.createCollection(named: "A"))
        XCTAssertEqual(coordinator.collectionsMessage, coordinator.collectionsUnavailableText)
        XCTAssertEqual(coordinator.addToCollection(try preset("Alpha", in: coordinator), "n1"), .failed)
        coordinator.deleteCollection("n1")
        XCTAssertEqual(try Data(contentsOf: file), newer, "S6: byte-for-byte unchanged")
    }

    func testAnUnreadableFileGivesANoticeOnce() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: directory.appendingPathComponent(PresetCollectionStore.fileName))
        let coordinator = try makeCoordinator()
        XCTAssertEqual(coordinator.collectionsNotice, "Your collections could not be read and were set aside.")
        XCTAssertNil(coordinator.collectionsUnavailableText)
        coordinator.dismissCollectionsNotice()
        XCTAssertNil(coordinator.collectionsNotice)
        XCTAssertNotNil(coordinator.createCollection(named: "Fresh"))
        XCTAssertNil(try makeCoordinator().collectionsNotice)
    }

    // MARK: - Labels (R18)

    func testRowLabels() {
        XCTAssertEqual(PresetCoordinator.collectionRowLabel(name: "Friday set", count: 3), "Friday set, 3 presets")
        XCTAssertEqual(PresetCoordinator.collectionRowLabel(name: "Solo", count: 1), "Solo, 1 preset")
        XCTAssertEqual(PresetCoordinator.collectionRowLabel(name: "Big", count: 1_000), "Big, 1,000 presets")
        XCTAssertEqual(PresetCoordinator.collectionsRowLabel(count: 0), "Collections, 0 collections")
        XCTAssertEqual(PresetCoordinator.collectionsRowLabel(count: 1), "Collections, 1 collection")
    }
}
