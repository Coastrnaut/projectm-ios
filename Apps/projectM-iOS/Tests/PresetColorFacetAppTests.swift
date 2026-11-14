// PresetColorFacetAppTests.swift — PRE-004-T09 (spec PRE-004-S3): colours are learned from thumbnails
// made through the real model (fake drawing → PNG encoder → cache → decode), the coordinator's colour
// filter lists exactly the matching presets, combines with tags and Favorites, announces on the search
// lane, survives a relaunch without drawing again, and PRE-002 invalidation drops a changed preset's colours.
import Foundation
import PresetLibrary
import Rendering
import XCTest
@testable import projectM_iOS

/// Draws a picture chosen by the preset's bytes (its ID): Alpha blue, Beta red, Gamma blue and yellow.
private final class ColorDrawing: PresetThumbnailDrawing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var drawCount: Int { lock.withLock { count } }

    func draw(_ contents: Data, width: Int, height: Int, frames: [[Float]], timeout: Duration) async -> PresetThumbnailDrawResult {
        lock.withLock { count += 1 }
        let id = String(decoding: contents, as: UTF8.self)
        var pixels = Data(count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let rgb: (UInt8, UInt8, UInt8)
                if id.contains("Alpha") { rgb = (30, 60, 220) }
                else if id.contains("Beta") { rgb = (220, 30, 30) }
                else { rgb = x < width / 2 ? (30, 60, 220) : (240, 220, 30) }
                pixels[offset] = rgb.0; pixels[offset + 1] = rgb.1; pixels[offset + 2] = rgb.2; pixels[offset + 3] = 255
            }
        }
        return .pixels(pixels)
    }
}

@MainActor
final class PresetColorFacetAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var search: [String] = []

    override func setUp() async throws {
        suite = "PresetColorFacetAppTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        search = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private final class FakeLoader: PresetLoading {
        func load(_ preset: IndexedPreset) async throws {}
    }

    private func makeLibrary() throws -> PresetLibrary {
        let records: [[String: Any]] = ["Alpha", "Beta", "Gamma", "Delta"].map { (name: String) -> [String: Any] in
            ["id": "frontend-uwp/\(name).milk", "name": name, "author": "A", "source": "included", "folder": [],
             "path": name, "hash": String(repeating: "0", count: 40)]
        }
        let packs: [[String: Any]] = [["id": "included", "title": "Included", "sourceURL": "u", "commit": "c", "license": "l",
                                       "presetCount": 4, "authors": [], "locked": false]]
        return try PresetLibrary(index: JSONSerialization.data(withJSONObject: ["version": 1, "presets": records]),
                                 packs: JSONSerialization.data(withJSONObject: ["version": 1, "packs": packs]))
    }

    private func makeCoordinator(_ drawing: ColorDrawing) async throws -> (PresetCoordinator, PresetColorStore) {
        let cache = PresetThumbnailCache(directory: directory.appendingPathComponent("Thumbs"),
                                         renderer: RendererThumbnailRenderer(drawing: { drawing }), sleep: { _ in })
        let store = PresetColorStore(directory: directory.appendingPathComponent("Colors"), sleep: { _ in })
        let model = PresetThumbnailModel(cache: cache, colors: store) { (preset: IndexedPreset) async throws -> Data in Data(preset.id.utf8) }
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: FakeLoader(),
                                            collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory))
        coordinator.thumbnails = model
        coordinator.announceSearch = { [weak self] (text: String) in self?.search.append(text) }
        coordinator.attach(try makeLibrary())
        await coordinator.thumbnailCollection?.value
        return (coordinator, store)
    }

    private func preset(_ name: String, _ coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    private func names(_ coordinator: PresetCoordinator) -> [String] { coordinator.filteredListing.map(\.name) }

    func testColoursLearnedFromThumbnailsFilterTheBrowser() async throws {
        let drawing = ColorDrawing()
        let (coordinator, store) = try await makeCoordinator(drawing)
        let model = try XCTUnwrap(coordinator.thumbnails)
        XCTAssertEqual(coordinator.colorFilter.presetCount, 0)
        for name in ["Alpha", "Beta", "Gamma"] { _ = await model.image(for: try preset(name, coordinator), playable: true) }
        XCTAssertEqual(drawing.drawCount, 3)
        XCTAssertEqual(coordinator.colorFilter.chips.map(\.family), [.red, .yellow, .blue])

        coordinator.toggleColor(.blue)
        XCTAssertEqual(names(coordinator), ["Alpha", "Gamma"])
        XCTAssertEqual(coordinator.filteredScope, .all)
        coordinator.toggleColor(.yellow)   // AND
        XCTAssertEqual(names(coordinator), ["Gamma"])
        XCTAssertEqual(search, ["2 presets match", "1 preset matches"])
        coordinator.toggleColor(.yellow)

        XCTAssertTrue(coordinator.addTag("Calm", to: try preset("Alpha", coordinator)))   // tags AND colours
        coordinator.toggleTag("Calm")
        XCTAssertEqual(names(coordinator), ["Alpha"])
        XCTAssertEqual(coordinator.filteredScope, .tagged(["Calm"]))
        coordinator.clearTags()
        let results = coordinator.searchResults("a").groups.flatMap(\.presets).map(\.name)
        XCTAssertEqual(results, ["Alpha", "Gamma"])   // search narrowed by the colour (Beta and Delta out)
        coordinator.clearColors()
        XCTAssertFalse(coordinator.hasActiveFilter)
        XCTAssertEqual(search.last, "Colour filter cleared")

        // A relaunch reads the colours back without drawing again.
        for _ in 0..<500 where await store.snapshot().count < 3 { await Task.yield() }
        await store.flush()
        let (relaunched, _) = try await makeCoordinator(drawing)
        XCTAssertEqual(relaunched.colorFilter.matching(all: [.blue]), ["frontend-uwp/Alpha.milk", "frontend-uwp/Gamma.milk"])
        XCTAssertEqual(drawing.drawCount, 3)

        // PRE-002: a changed preset loses its colours.
        await relaunched.thumbnails?.invalidate(presetID: "frontend-uwp/Alpha.milk", keepingContentHash: "changed")
        XCTAssertEqual(relaunched.colorFilter.matching(all: [.blue]), ["frontend-uwp/Gamma.milk"])
    }
}
