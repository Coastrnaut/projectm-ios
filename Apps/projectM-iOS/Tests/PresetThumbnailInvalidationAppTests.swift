// PresetThumbnailInvalidationAppTests.swift — PRE-002-T06, T08 (specs/144-pre-002-thumbnail-invalidation;
// S5): the live path through the app's coordinators. Two user presets (copies of a synthetic library's
// presets) and a built-in preset are cached; saving an edit removes exactly the edited preset's old
// thumbnail and changes its row's request identity; a rename-only save keeps both; removing a user
// preset removes its thumbnail; the launch collection removes entries of presets no longer listed.
import PresetLibrary
import Rendering
import UIKit
import XCTest
@testable import projectM_iOS

/// Draws a solid picture instantly and counts drawings.
private final class CountingDrawing: PresetThumbnailDrawing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var drawCount: Int { lock.withLock { count } }

    func draw(_ contents: Data, width: Int, height: Int, frames: [[Float]], timeout: Duration) async -> PresetThumbnailDrawResult {
        lock.withLock { count += 1 }
        return .pixels(Data(repeating: 0x60, count: width * height * 4))
    }
}

@MainActor
final class PresetThumbnailInvalidationAppTests: XCTestCase {
    private typealias FakeRenderer = UserPresetsCoordinatorTests.FakeRenderer
    private typealias ScriptedTrial = UserPresetsCoordinatorTests.ScriptedTrial
    private var defaults: UserDefaults!
    private var suite: String!
    private var base: URL!

    override func setUp() async throws {
        suite = "PresetThumbnailInvalidationAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        base = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: base)
    }

    private struct Rig {
        let presets: PresetCoordinator
        let userPresets: UserPresetsCoordinator
        let thumbnails: PresetThumbnailModel
        let drawing: CountingDrawing
    }

    private static func text(zoom: String) -> String {
        ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "[preset00]", "fDecay=0.96", "zoom=\(zoom)", "per_frame_1=rot = 0.01;", ""]
            .joined(separator: "\n")
    }

    private func syntheticLibrary() throws -> PresetLibrary {
        func record(_ id: String, _ name: String, _ text: String) -> [String: Any] {
            ["id": id, "name": name, "author": "A", "source": "included", "folder": [], "path": id,
             "hash": ContentHash.gitBlobSHA1Hex(Array(text.utf8))]
        }
        let records = [record("included/Alpha.milk", "Alpha", Self.text(zoom: "1.0")),
                       record("included/Beta.milk", "Beta", Self.text(zoom: "2.0"))]
        let packs: [[String: Any]] = [
            ["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "Included license.", "presetCount": 2,
             "authors": [], "locked": false],
        ]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func launch(thumbnailFolder: URL) async throws -> Rig {
        let builtIn = try syntheticLibrary()
        let renderer = FakeRenderer()
        let loader = RendererPresetLoader()
        loader.renderer = renderer
        loader.library = builtIn
        let presets = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                        settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: loader,
                                        collections: PresetCollectionStore(directory: base.appendingPathComponent("collections")))
        let drawing = CountingDrawing()
        let cache = PresetThumbnailCache(directory: thumbnailFolder, renderer: RendererThumbnailRenderer(drawing: { drawing }), sleep: { _ in })
        let thumbnails = PresetThumbnailModel(cache: cache) { (preset: IndexedPreset) async throws -> Data in Data(preset.hash.utf8) }
        presets.thumbnails = thumbnails
        let userPresets = UserPresetsCoordinator(library: UserPresetLibrary(directory: base.appendingPathComponent("UserPresets")),
                                                 provingPeriod: .seconds(60)) { _ in }
        userPresets.connect(presets: presets, loader: loader)
        userPresets.bundledData = { (preset: IndexedPreset) throws -> Data in Data(Self.text(zoom: preset.name == "Alpha" ? "1.0" : "2.0").utf8) }
        await userPresets.load()
        await userPresets.prepare(library: builtIn, bundle: .main)
        presets.attach(builtIn)
        await presets.thumbnailCollection?.value
        await presets.setUnlocked(false)
        await userPresets.rendererReady(trial: ScriptedTrial(), presentedFrames: { [renderer] in renderer.presentedFrameCount })
        return Rig(presets: presets, userPresets: userPresets, thumbnails: thumbnails, drawing: drawing)
    }

    private func file(_ preset: IndexedPreset, in folder: URL) -> URL {
        folder.appendingPathComponent(PresetThumbnailKey(preset: preset).fileName)
    }

    private func listed(_ id: String, _ rig: Rig) throws -> IndexedPreset {
        try XCTUnwrap(rig.presets.library?.preset(id: id))
    }

    func testASavedEditInvalidatesExactlyThatPresetsThumbnailAndRefreshesItsRow() async throws {
        let folder = base.appendingPathComponent("Thumbs", isDirectory: true)
        let rig = try await launch(thumbnailFolder: folder)
        await rig.userPresets.duplicate(try listed("included/Alpha.milk", rig))
        await rig.userPresets.duplicate(try listed("included/Beta.milk", rig))
        XCTAssertEqual(rig.userPresets.playable.count, 2)
        let alphaCopy = try XCTUnwrap(rig.userPresets.playable.first { $0.duplicateOf?.presetID == "included/Alpha.milk" })
        let betaCopy = try XCTUnwrap(rig.userPresets.playable.first { $0.duplicateOf?.presetID == "included/Beta.milk" })
        let editedBefore = try listed(alphaCopy.id, rig)
        let neighbor = try listed(betaCopy.id, rig)
        let builtIn = try listed("included/Alpha.milk", rig)
        for preset in [editedBefore, neighbor, builtIn] {
            let image = await rig.thumbnails.image(for: preset, playable: true)
            XCTAssertNotNil(image)
        }
        XCTAssertEqual(rig.drawing.drawCount, 3)
        let neighborDate = try FileManager.default.attributesOfItem(atPath: file(neighbor, in: folder).path)[.modificationDate] as? Date

        // A rename-only save keeps the picture and the row's request.
        let maybeOpened = await rig.userPresets.editorText(for: alphaCopy)
        let opened = try XCTUnwrap(maybeOpened)
        let renamed = await rig.userPresets.saveEdit(alphaCopy, name: "Alpha renamed", text: opened.text, opened: opened)
        guard case .saved = renamed else { return XCTFail("\(renamed)") }
        let afterRename = try listed(alphaCopy.id, rig)
        XCTAssertEqual(afterRename.name, "Alpha renamed")
        XCTAssertEqual(PresetThumbnailView.requestID(for: afterRename, playable: true),
                       PresetThumbnailView.requestID(for: editedBefore, playable: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(editedBefore, in: folder).path))
        XCTAssertNotNil(rig.thumbnails.memoryImage(for: afterRename))

        // A new text: exactly that preset's old picture goes; the row asks again.
        let current = try XCTUnwrap(rig.userPresets.playable.first { $0.id == alphaCopy.id })
        let maybeReopened = await rig.userPresets.editorText(for: current)
        let reopened = try XCTUnwrap(maybeReopened)
        let edited = await rig.userPresets.saveEdit(current, name: current.name, text: Self.text(zoom: "1.7"), opened: reopened)
        guard case .saved = edited else { return XCTFail("\(edited)") }
        let editedAfter = try listed(alphaCopy.id, rig)
        XCTAssertNotEqual(editedAfter.hash, editedBefore.hash)
        XCTAssertNotEqual(PresetThumbnailView.requestID(for: editedAfter, playable: true),
                          PresetThumbnailView.requestID(for: editedBefore, playable: true), "the row's request restarts")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(editedBefore, in: folder).path), "old picture removed")
        XCTAssertNil(rig.thumbnails.memoryImage(for: editedBefore), "old picture left memory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(neighbor, in: folder).path), "neighbor kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(builtIn, in: folder).path), "built-in original kept")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file(neighbor, in: folder).path)[.modificationDate] as? Date, neighborDate)
        XCTAssertNotNil(rig.thumbnails.memoryImage(for: neighbor))

        let image = await rig.thumbnails.image(for: editedAfter, playable: true)
        XCTAssertNotNil(image)
        XCTAssertEqual(rig.drawing.drawCount, 4, "only the edited preset is drawn again")

        // Removing a user preset removes its picture; the others stay.
        let neighborRecord = try XCTUnwrap(rig.userPresets.playable.first { $0.id == betaCopy.id })
        await rig.userPresets.remove(neighborRecord)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file(neighbor, in: folder).path), "removed preset's picture gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(editedAfter, in: folder).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file(builtIn, in: folder).path))
        let entries = await rig.thumbnails.cache.entryCount
        XCTAssertEqual(entries, 2)
    }

    func testTheLaunchCollectionRemovesEntriesOfPresetsNoLongerListed() async throws {
        let folder = base.appendingPathComponent("Thumbs", isDirectory: true)
        // An earlier launch cached a preset that is gone and an older version of Alpha.
        let drawing = CountingDrawing()
        let earlier = PresetThumbnailCache(directory: folder, renderer: RendererThumbnailRenderer(drawing: { drawing }), sleep: { _ in })
        let gone = PresetThumbnailKey(presetID: "user/gone", contentHash: "aa", rendererVersion: 1)
        let oldAlpha = PresetThumbnailKey(presetID: "included/Alpha.milk", contentHash: "old", rendererVersion: 1)
        for key in [gone, oldAlpha] { _ = try await earlier.thumbnail(for: key) { Data(key.presetID.utf8) } }

        let rig = try await launch(thumbnailFolder: folder)
        let entries = await rig.thumbnails.cache.entryCount
        XCTAssertEqual(entries, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(gone.fileName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(oldAlpha.fileName).path))
    }
}
