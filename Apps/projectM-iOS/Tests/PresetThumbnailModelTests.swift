// PresetThumbnailModelTests.swift — PRE-001-T12, T13: the app side of the thumbnail cache. A playable
// preset's picture is made once through the renderer and served from the cache in Caches; a locked
// preset is never drawn; a renderer without thumbnails (the GLES fallback) or none at all leaves the
// placeholder without remembering a failure; PNG encoding round-trips; the cache folder lies in
// Storage's Caches category and outside every folder cache cleanup protects (research PRE-001-D7).
import Foundation
import ImageIO
import PresetLibrary
import Rendering
import UIKit
import XCTest
@testable import projectM_iOS

/// Counts drawings and returns a solid picture.
private final class FakeDrawing: PresetThumbnailDrawing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var result: (Int, Int) -> PresetThumbnailDrawResult = { width, height in
        .pixels(Data(repeating: 0x80, count: width * height * 4))
    }

    var drawCount: Int {
        lock.withLock { count }
    }

    func draw(_ contents: Data, width: Int, height: Int, frames: [[Float]], timeout: Duration) async -> PresetThumbnailDrawResult {
        lock.withLock { count += 1 }
        XCTAssertEqual(frames.count, PresetThumbnailSpec.standard.frames)
        return result(width, height)
    }
}

@MainActor
final class PresetThumbnailModelTests: XCTestCase {
    private func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PresetThumbnailModelTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let preset = IndexedPreset(id: "included/Test.milk", name: "Test", author: "", source: "included", folder: [],
                                       path: "Test.milk", hash: "abc")

    private func makeModel(_ drawing: FakeDrawing?, folder: URL) -> PresetThumbnailModel {
        let renderer = RendererThumbnailRenderer(drawing: { drawing })
        let cache = PresetThumbnailCache(directory: folder, renderer: renderer, sleep: { _ in })
        return PresetThumbnailModel(cache: cache) { (preset: IndexedPreset) async throws -> Data in Data(preset.id.utf8) }
    }

    func testAPlayablePresetIsDrawnOnceAndThenServedFromTheCache() async throws {
        let drawing = FakeDrawing()
        let folder = temporaryFolder()
        let model = makeModel(drawing, folder: folder)
        let first = await model.image(for: preset, playable: true)
        XCTAssertEqual(first?.size.width, 128)
        XCTAssertEqual(drawing.drawCount, 1)
        let key = PresetThumbnailKey(preset: preset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(key.fileName).path))
        XCTAssertNotNil(model.memoryImage(for: preset))

        let relaunched = makeModel(drawing, folder: folder)   // a new process: empty memory, same folder
        XCTAssertNil(relaunched.memoryImage(for: preset))
        let second = await relaunched.image(for: preset, playable: true)
        XCTAssertNotNil(second)
        XCTAssertEqual(drawing.drawCount, 1, "the second browse draws nothing")
    }

    func testALockedPresetIsNeverDrawn() async {
        let drawing = FakeDrawing()
        let model = makeModel(drawing, folder: temporaryFolder())
        let image = await model.image(for: preset, playable: false)
        XCTAssertNil(image)
        XCTAssertEqual(drawing.drawCount, 0)
        let renders = await model.cache.renderCount
        XCTAssertEqual(renders, 0)
    }

    func testNoThumbnailRendererLeavesThePlaceholderWithoutRememberingAFailure() async {
        let model = makeModel(nil, folder: temporaryFolder())   // the GLES fallback: no presetThumbnails
        let image = await model.image(for: preset, playable: true)
        XCTAssertNil(image)
        let failures = await model.cache.failureCount
        XCTAssertEqual(failures, 0, "unavailable is asked again when the row reappears")
    }

    func testAFailedDrawingIsRememberedForTheSession() async {
        let drawing = FakeDrawing()
        drawing.result = { _, _ in .failed("shader") }
        let model = makeModel(drawing, folder: temporaryFolder())
        _ = await model.image(for: preset, playable: true)
        _ = await model.image(for: preset, playable: true)
        XCTAssertEqual(drawing.drawCount, 1)
    }

    func testPNGEncodingRoundTrips() throws {
        var pixels = Data(count: 4 * 2 * 4)
        pixels[0] = 255   // top-left red
        let png = try XCTUnwrap(PNGThumbnailEncoder.png(rgba: pixels, width: 4, height: 2))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 2)
        XCTAssertNil(PNGThumbnailEncoder.png(rgba: Data(count: 3), width: 4, height: 2), "wrong byte count")
    }

    /// PRE-001-R9: counted in Storage's Caches, removed by Clear Caches, never a protected folder.
    func testTheCacheFolderIsInTheCachesCategoryAndNotProtected() throws {
        let folder = PresetThumbnailModel.defaultDirectory().standardizedFileURL.path
        let locations = StorageLocations.standard()
        let caches = try XCTUnwrap(locations.roots[.caches]?.first).standardizedFileURL.path
        XCTAssertTrue(folder.hasPrefix(caches + "/"), "\(folder) under \(caches)")
        for protected in locations.protectedRoots {
            XCTAssertFalse(folder.hasPrefix(protected.standardizedFileURL.path + "/"), "inside \(protected.path)")
        }
        XCTAssertTrue(folder.hasSuffix("/" + PresetThumbnailCache.folderName))
    }
}
