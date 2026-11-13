// PRE-015-T08, T13, T18, T19: duplicating and editing through the app's coordinators
// (specs/010-pre-015-user-preset-duplication; PRE-015-R1-R20; S1, S2, S4). The bundled presets
// are the test host's own 28 Included files and its generated PresetIndex.json, read at run time;
// a scripted trial stands in for the off-screen engine and a fake renderer records loads.
import PresetLibrary
import Rendering
import XCTest
@testable import projectM_iOS

@MainActor
final class UserPresetDuplicationAppTests: XCTestCase {
    private typealias FakeRenderer = UserPresetsCoordinatorTests.FakeRenderer
    private typealias ScriptedTrial = UserPresetsCoordinatorTests.ScriptedTrial
    private var defaults: UserDefaults!
    private var suite: String!
    private var base: URL!
    private var announcements: [String] = []

    override func setUp() async throws {
        suite = "UserPresetDuplicationAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        base = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        announcements = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: base)
    }

    private struct Rig {
        let presets: PresetCoordinator
        let userPresets: UserPresetsCoordinator
        let renderer: FakeRenderer
        let loader: RendererPresetLoader
    }

    private func launch(_ builtIn: PresetLibrary, unlocked: Bool = false) async -> Rig {
        let renderer = FakeRenderer()
        let loader = RendererPresetLoader()
        loader.renderer = renderer
        loader.library = builtIn
        let presets = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                        settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                        collections: PresetCollectionStore(directory: base.appendingPathComponent("collections")))
        let userPresets = UserPresetsCoordinator(library: UserPresetLibrary(directory: base.appendingPathComponent("UserPresets")),
                                                 provingPeriod: .seconds(60)) { [weak self] in self?.announcements.append($0) }
        userPresets.connect(presets: presets, loader: loader)
        await userPresets.load()
        await userPresets.prepare(library: builtIn, bundle: .main)
        presets.attach(builtIn)
        await presets.setUnlocked(unlocked)
        await userPresets.rendererReady(trial: ScriptedTrial(), presentedFrames: { [renderer] in renderer.presentedFrameCount })
        return Rig(presets: presets, userPresets: userPresets, renderer: renderer, loader: loader)
    }

    /// The bundled file of an Included preset and its git blob hash, read straight from the app.
    private func bundled(_ preset: IndexedPreset) throws -> (data: Data, hash: String) {
        let url = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent(preset.path)
        let data = try Data(contentsOf: url)
        return (data, ContentHash.gitBlobSHA1Hex([UInt8](data)))
    }

    private func copies(of preset: IndexedPreset, in rig: Rig) -> [UserPreset] {
        (rig.userPresets.playable + rig.userPresets.pending + rig.userPresets.quarantined + rig.userPresets.needsUnlock)
            .filter { $0.duplicateOf?.presetID == preset.id }
    }

    // MARK: - S1, S2 with the app's real Included presets

    func testEveryIncludedPresetDuplicatesAndEditsWithoutChangingTheBundle() async throws {
        let builtIn = try await PresetLibrary.load(from: .main)
        let included = builtIn.presets.filter(\.isIncluded)
        XCTAssertEqual(included.count, 28)
        let rig = await launch(builtIn)
        let favorite = try XCTUnwrap(included.first)
        rig.presets.toggleFavorite(favorite)
        let collection = try XCTUnwrap(rig.presets.createCollection(named: "Set"))
        XCTAssertEqual(rig.presets.addToCollection(favorite, collection.id), .added)

        var edited = 0
        // Two Included files ("UWP" and a Stahlregen preset) are byte-identical, so each edit
        // appends its own line; otherwise the second edit would equal the first (sameAsUserPreset).
        for (index, preset) in included.enumerated() {
            let before = try bundled(preset)
            XCTAssertEqual(before.hash, preset.hash, "\(preset.name): the bundled file is what the index describes")

            await rig.userPresets.duplicate(preset)
            let message = try XCTUnwrap(rig.userPresets.duplicateMessage, preset.name)
            rig.userPresets.duplicateMessage = nil
            let afterDuplicate = try bundled(preset)
            XCTAssertEqual(afterDuplicate.data, before.data, preset.name)
            XCTAssertEqual(builtIn.preset(id: preset.id)?.hash, before.hash, preset.name)

            guard let copy = copies(of: preset, in: rig).first(where: { $0.state == .playable }) else {
                // Only the import checks may refuse a built-in preset; the message says why.
                XCTAssertTrue(message.contains("does not pass the checks"), "\(preset.name): \(message)")
                continue
            }
            XCTAssertEqual(copy.sha256, ContentHash.sha256Hex([UInt8](before.data)))
            XCTAssertEqual(copy.duplicateOf?.blobHash, before.hash)
            XCTAssertEqual(copy.duplicateOf?.packID, PresetLibrary.includedSource)
            XCTAssertEqual(copy.duplicateOf?.licenseStatement, builtIn.pack(id: PresetLibrary.includedSource)?.license)

            // Edit the copy: append a comment line.
            let maybeOpened = await rig.userPresets.editorText(for: copy)
            let opened = try XCTUnwrap(maybeOpened)
            let outcome = await rig.userPresets.saveEdit(copy, name: copy.name, text: opened.text + "\n// edited on this device \(index)\n", opened: opened)
            guard case .saved(let saved) = outcome else {
                XCTFail("\(preset.name): \(outcome)")
                continue
            }
            edited += 1
            XCTAssertNotEqual(saved.sha256, copy.sha256, "the copy's file changed")
            let maybeStored = await rig.userPresets.editorText(for: saved)
            let stored = try XCTUnwrap(maybeStored)
            XCTAssertTrue(stored.text.hasSuffix("// edited on this device \(index)\n"))
            let afterEdit = try bundled(preset)
            XCTAssertEqual(afterEdit.data, before.data, "\(preset.name): bundled bytes unchanged after the edit")
            XCTAssertEqual(afterEdit.hash, preset.hash, "\(preset.name): bundled hash unchanged after the edit")
        }
        print("PRE-015-S1: \(edited) of \(included.count) Included presets duplicated and edited")
        XCTAssertGreaterThanOrEqual(edited, 26, "the built-in presets almost all pass the import checks")

        // The bundled preset still plays from the bundle, not from a copy.
        await rig.presets.select(favorite)
        let loaded = try XCTUnwrap(rig.renderer.loaded.last)
        XCTAssertEqual(loaded.id, favorite.id)
        XCTAssertNil(loaded.data, "an Included preset loads from its bundle file")
        XCTAssertEqual(loaded.fileURL, Bundle.main.resourceURL?.appendingPathComponent(favorite.path))

        // Favorites and collections still name the bundled preset (R20).
        XCTAssertTrue(rig.presets.isFavorite(favorite))
        XCTAssertEqual(rig.presets.favoritesListing.map(\.id), [favorite.id])
        XCTAssertEqual(rig.presets.collectionListing(collection.id).map(\.id), [favorite.id])
        XCTAssertEqual(rig.presets.library?.preset(id: favorite.id)?.source, PresetLibrary.includedSource)
    }

    // MARK: - Synthetic library: lock boundary, refusals, reload (R7, R8, R17)

    private static func text(zoom: String) -> String {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=\(zoom)", "per_frame_1=rot = 0.01;", ""]
            .joined(separator: "\n")
    }

    private func syntheticLibrary() throws -> PresetLibrary {
        func record(_ id: String, _ name: String, _ source: String, _ text: String) -> [String: Any] {
            ["id": id, "name": name, "author": "A", "source": source, "folder": [], "path": id,
             "hash": ContentHash.gitBlobSHA1Hex(Array(text.utf8))]
        }
        let records = [record("included/Alpha.milk", "Alpha", "included", Self.text(zoom: "1.0")),
                       record("cream-of-the-crop/Locked.milk", "Locked", "cream-of-the-crop", Self.text(zoom: "2.0"))]
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "Included license.", "presetCount": 1,
             "authors": [], "locked": false],
            ["id": "cream-of-the-crop", "title": "Cream of the Crop", "sourceURL": "u", "commit": "c",
             "license": "Assumed public domain.", "presetCount": 1, "authors": [], "locked": true],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func launchSynthetic(unlocked: Bool) async throws -> Rig {
        let rig = await launch(try syntheticLibrary(), unlocked: unlocked)
        rig.userPresets.bundledData = { preset in Data(Self.text(zoom: preset.name == "Alpha" ? "1.0" : "2.0").utf8) }
        return rig
    }

    func testALockedPresetAsksForThePurchaseAndStoresNothing() async throws {
        let rig = try await launchSynthetic(unlocked: false)
        let locked = try XCTUnwrap(rig.presets.library?.preset(id: "cream-of-the-crop/Locked.milk"))
        await rig.userPresets.duplicate(locked)
        XCTAssertTrue(rig.presets.purchaseRequested)
        XCTAssertNil(rig.userPresets.duplicateMessage)
        XCTAssertEqual(rig.userPresets.playable + rig.userPresets.needsUnlock, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("UserPresets/index.json").path))
    }

    func testCopiesOfLockedPacksAreHeldAfterARefundAndComeBack() async throws {
        var rig = try await launchSynthetic(unlocked: true)
        let locked = try XCTUnwrap(rig.presets.library?.preset(id: "cream-of-the-crop/Locked.milk"))
        await rig.userPresets.duplicate(locked)
        let copy = try XCTUnwrap(rig.userPresets.playable.first)
        XCTAssertEqual(rig.userPresets.duplicateMessage, "Duplicated “Locked” to My Presets as “Locked copy”.")
        let indexed = try XCTUnwrap(rig.presets.library?.preset(id: copy.id))
        rig.presets.toggleFavorite(indexed)
        await rig.presets.choose(indexed, from: .user)
        XCTAssertEqual(rig.presets.current?.id, copy.id)

        // Refund: the copy leaves the library and every scope; the picture keeps playing (FR-109).
        await rig.presets.setUnlocked(false)
        XCTAssertEqual(rig.userPresets.needsUnlock.map(\.id), [copy.id])
        XCTAssertEqual(rig.userPresets.playable, [])
        XCTAssertNil(rig.presets.library?.preset(id: copy.id))
        XCTAssertEqual(rig.presets.current?.id, copy.id, "the playing picture stays")
        let text = await rig.userPresets.editorText(for: copy)
        XCTAssertNil(text)
        rig.userPresets.chooseHeld(copy)
        XCTAssertTrue(rig.presets.purchaseRequested)
        rig.presets.purchaseRequested = false

        // A relaunch without the entitlement keeps the copy and its favorite.
        await rig.userPresets.abandonProving()
        rig = try await launchSynthetic(unlocked: false)
        XCTAssertEqual(rig.userPresets.needsUnlock.map(\.id), [copy.id])
        XCTAssertTrue(FavoritesStore(defaults: defaults).isFavorite(copy.id), "nothing is deleted, not even the star")

        // Restored.
        await rig.presets.setUnlocked(true)
        XCTAssertEqual(rig.userPresets.playable.map(\.id), [copy.id])
        XCTAssertNotNil(rig.presets.library?.preset(id: copy.id))
        XCTAssertTrue(rig.presets.favoritesListing.contains { $0.id == copy.id })
    }

    func testAPresetThatFailedThisSessionIsNotDuplicated() async throws {
        let rig = try await launchSynthetic(unlocked: false)
        let alpha = try XCTUnwrap(rig.presets.library?.preset(id: "included/Alpha.milk"))
        rig.renderer.failing = []
        rig.loader.renderer = nil   // the next load throws
        await rig.presets.select(alpha)
        rig.loader.renderer = rig.renderer
        await rig.userPresets.duplicate(alpha)
        XCTAssertEqual(rig.userPresets.duplicateMessage, "“Alpha” was not duplicated. It could not be loaded in this session.")
        XCTAssertEqual(rig.userPresets.playable, [])
    }

    func testASavedEditOfThePresetOnScreenIsReloaded() async throws {
        let rig = try await launchSynthetic(unlocked: false)
        let alpha = try XCTUnwrap(rig.presets.library?.preset(id: "included/Alpha.milk"))
        await rig.userPresets.duplicate(alpha)
        let copy = try XCTUnwrap(rig.userPresets.playable.first)
        await rig.presets.choose(try XCTUnwrap(rig.presets.library?.preset(id: copy.id)), from: .user)
        let loads = rig.renderer.loaded.count
        let maybeOpened = await rig.userPresets.editorText(for: copy)
        let opened = try XCTUnwrap(maybeOpened)
        let newText = Self.text(zoom: "1.5")
        let outcome = await rig.userPresets.saveEdit(copy, name: "Alpha remix", text: newText, opened: opened)
        guard case .saved = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(rig.renderer.loaded.count, loads + 1)
        XCTAssertEqual(rig.renderer.loaded.last?.data, Data(newText.utf8))
        XCTAssertEqual(rig.presets.current?.name, "Alpha remix")
        XCTAssertEqual(announcements.last, "Saved “Alpha remix”.")

        // A failing edit changes nothing and is reported.
        let current = try XCTUnwrap(rig.userPresets.playable.first)
        let maybeReopened = await rig.userPresets.editorText(for: current)
        let reopened = try XCTUnwrap(maybeReopened)
        let failing = await rig.userPresets.saveEdit(current, name: "Alpha remix",
                                                     text: "zoom=1\n", opened: reopened)
        guard case .refused = failing else { return XCTFail("\(failing)") }
        XCTAssertEqual(rig.renderer.loaded.count, loads + 1)
        let still = await rig.userPresets.editorText(for: current)
        XCTAssertEqual(still?.text, newText)
    }

    // MARK: - Words (R18, US4)

    func testOriginWords() {
        let origin = PresetDuplicateOrigin(presetID: "cream-of-the-crop/x.milk", name: "Example", packID: "cream-of-the-crop",
                                           packTitle: "Cream of the Crop", sha256: String(repeating: "a", count: 64),
                                           blobHash: String(repeating: "b", count: 40), licenseStatement: "Assumed public domain.",
                                           requiresLibraryUnlock: true)
        XCTAssertEqual(UserPresetsCoordinator.originText(origin), "Duplicated from “Example” in Cream of the Crop.")
        XCTAssertEqual(UserPresetsCoordinator.heldLabel(name: "Example copy"), "Example copy, needs the full library")
        XCTAssertEqual(UserPresetsCoordinator.duplicateRightsText,
                       "projectM-iOS has not verified any rights beyond the pack's statement. You can edit this copy on this device.")
    }
}
