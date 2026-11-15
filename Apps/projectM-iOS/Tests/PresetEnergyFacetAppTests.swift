// PresetEnergyFacetAppTests.swift — PRE-005-T13 (spec PRE-005-S4): motion scores travel from the drawing's
// samples through the real renderer adapter (score → PNG field), cache and decode into the coordinator's
// energy filter; classes combine with OR among themselves and AND with colours and search; announcements
// go to the search lane; the selection is not a scope (R12); a relaunch reads scores back without
// drawing; PRE-002 invalidation drops a changed preset's score.
import Foundation
import PresetLibrary
import Rendering
import XCTest
@testable import projectM_iOS

/// Alpha: still blue (Calm). Beta: black, black, then red (Energetic). Gamma: a lighter blue twice, then
/// blue (Moderate). Delta: no samples (no class, as a drawer without samples).
private final class MotionDrawing: PresetThumbnailDrawing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var drawCount: Int { lock.withLock { count } }

    private static func solid(_ rgb: (UInt8, UInt8, UInt8), width: Int, height: Int) -> Data {
        var pixels = Data(count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = rgb.0; pixels[offset + 1] = rgb.1; pixels[offset + 2] = rgb.2; pixels[offset + 3] = 255
        }
        return pixels
    }

    func draw(_ contents: Data, width: Int, height: Int, frames: [[Float]], timeout: Duration) async -> PresetThumbnailDrawResult {
        await drawSamples(contents, width: width, height: height, frames: frames, sampleFrames: [], timeout: timeout).picture
    }

    func drawSamples(_ contents: Data, width: Int, height: Int, frames: [[Float]], sampleFrames: [Int],
                     timeout: Duration) async -> PresetThumbnailSampleResult {
        lock.withLock { count += 1 }
        let id = String(decoding: contents, as: UTF8.self)
        let blue: Data = Self.solid((30, 60, 220), width: width, height: height)
        if id.contains("Alpha") { return PresetThumbnailSampleResult(picture: .pixels(blue), samples: [blue, blue]) }
        if id.contains("Beta") {
            let black: Data = Self.solid((0, 0, 0), width: width, height: height)
            return PresetThumbnailSampleResult(picture: .pixels(Self.solid((220, 30, 30), width: width, height: height)), samples: [black, black])
        }
        if id.contains("Gamma") {
            let light: Data = Self.solid((50, 80, 240), width: width, height: height)
            return PresetThumbnailSampleResult(picture: .pixels(blue), samples: [light, light])
        }
        return PresetThumbnailSampleResult(picture: .pixels(blue), samples: [])
    }
}

@MainActor
final class PresetEnergyFacetAppTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var directory: URL!
    private var search: [String] = []

    override func setUp() async throws {
        suite = "PresetEnergyFacetAppTests-\(UUID().uuidString)"
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

    private func makeCoordinator(_ drawing: MotionDrawing) async throws -> (PresetCoordinator, PresetMotionStore) {
        let cache = PresetThumbnailCache(directory: directory.appendingPathComponent("Thumbs"),
                                         renderer: RendererThumbnailRenderer(drawing: { drawing }), sleep: { _ in })
        let colors = PresetColorStore(directory: directory.appendingPathComponent("Colors"), sleep: { _ in })
        let motion = PresetMotionStore(directory: directory.appendingPathComponent("Motion"), sleep: { _ in })
        let model = PresetThumbnailModel(cache: cache, colors: colors, motion: motion) { (preset: IndexedPreset) async throws -> Data in
            Data(preset.id.utf8)
        }
        let coordinator = PresetCoordinator(store: FavoritesStore(defaults: defaults),
                                            settings: AppSettings(defaults: defaults, systemReduceMotion: false), loader: FakeLoader(),
                                            collections: PresetCollectionStore(directory: directory),
                                            tags: PresetTagStore(directory: directory))
        coordinator.thumbnails = model
        coordinator.announceSearch = { [weak self] (text: String) in self?.search.append(text) }
        coordinator.attach(try makeLibrary())
        await coordinator.thumbnailCollection?.value
        return (coordinator, motion)
    }

    private func preset(_ name: String, _ coordinator: PresetCoordinator) throws -> IndexedPreset {
        try XCTUnwrap(coordinator.library?.presets.first { $0.name == name }, name)
    }

    private func names(_ coordinator: PresetCoordinator) -> [String] { coordinator.filteredListing.map(\.name) }

    func testScoresFromThumbnailSamplesFilterTheBrowser() async throws {
        let drawing = MotionDrawing()
        let (coordinator, store) = try await makeCoordinator(drawing)
        let model = try XCTUnwrap(coordinator.thumbnails)
        XCTAssertEqual(coordinator.energyFilter.presetCount, 0)
        for name in ["Alpha", "Beta", "Gamma", "Delta"] { _ = await model.image(for: try preset(name, coordinator), playable: true) }
        XCTAssertEqual(drawing.drawCount, 4)
        let filter: PresetEnergyFilter = coordinator.energyFilter
        XCTAssertEqual(filter.chips.map(\.energy), [.calm, .moderate, .energetic])
        XCTAssertEqual(filter.presetCount, 3, "Delta's picture has no score")
        XCTAssertEqual(filter.energy(of: "frontend-uwp/Gamma.milk"), .moderate)

        coordinator.toggleEnergy(.calm)
        XCTAssertEqual(names(coordinator), ["Alpha"])
        XCTAssertEqual(coordinator.filteredScope, .all, "R12: not a scope")
        coordinator.toggleEnergy(.energetic)   // OR
        XCTAssertEqual(names(coordinator), ["Alpha", "Beta"])
        coordinator.toggleColor(.blue)   // AND with colours
        XCTAssertEqual(names(coordinator), ["Alpha"])
        XCTAssertEqual(search, ["1 preset matches", "2 presets match", "1 preset matches"])
        coordinator.clearColors()
        coordinator.clearEnergies()
        XCTAssertFalse(coordinator.hasActiveFilter)
        XCTAssertEqual(search.last, "Motion filter cleared")
        coordinator.toggleEnergy(.moderate)
        let results = coordinator.searchResults("a").groups.flatMap(\.presets).map(\.name)
        XCTAssertEqual(results, ["Gamma"], "search narrowed by the class")
        XCTAssertEqual(coordinator.filteredEmptyText, PresetCoordinator.filteredEmptyText)
        coordinator.clearEnergies()

        // A relaunch reads the scores back without drawing again.
        for _ in 0..<500 where await store.snapshot().count < 3 { try await Task.sleep(for: .milliseconds(10)) }   // up to 5 s (load)
        await store.flush()
        let (relaunched, _) = try await makeCoordinator(drawing)
        XCTAssertEqual(relaunched.energyFilter.matching(any: [.calm, .moderate]), ["frontend-uwp/Alpha.milk", "frontend-uwp/Gamma.milk"])
        XCTAssertEqual(drawing.drawCount, 4)

        // PRE-002: a changed preset loses its score.
        await relaunched.thumbnails?.invalidate(presetID: "frontend-uwp/Alpha.milk", keepingContentHash: "changed")
        XCTAssertEqual(relaunched.energyFilter.matching(any: [.calm]), [])
    }
}
