// FX-011-T09: the pixel sort through the golden scene renderer (SCN-001 decode → live state → layers → Compositor with
// the flash guard on → REC-001 capture; FX-011-S5): a disabled sort renders exactly as no chain; a sort scene saved and
// reloaded keeps its values and renders the same picture, which differs from the plain one; two thresholds render
// different pictures. Uses the FX-020 plasma run of `EffectChainSceneTests`. Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneFormat
import SceneRenderHarness
import XCTest

final class PixelSortSceneGoldenTests: XCTestCase {
    private let sortRun = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                         audio: .seededBands(count: 32))
    private let sortResolution = GoldenResolution(width: 128, height: 96)

    private func sortRenderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func sortPlasma(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(sortRun))
        document.effects = effects
        return document
    }

    private func sortFrame(_ r: GoldenSceneRenderer, _ document: SceneDocument) throws -> GoldenImage {
        let images = try r.render(run: sortRun, document: document, resolution: sortResolution)
        return try XCTUnwrap(images[7])
    }

    private func sortEntry(_ sort: PixelSort) -> SceneEffectEntry {
        var entry = SceneEffectEntry(kind: OutputEffectKind.pixelSort.rawValue, enabled: sort.isEnabled)
        entry.parameters["threshold"] = .double(sort.threshold)
        entry.parameters["span"] = .double(Double(sort.span))
        entry.parameters["vertical"] = .double(sort.direction == .vertical ? 1 : 0)
        return entry
    }

    func testPixelSortOffRendersExactlyAsNoChain() throws {
        let r = try sortRenderer()
        let plain = try sortFrame(r, try sortPlasma(nil))
        let off = try sortFrame(r, try sortPlasma([sortEntry(PixelSort(isEnabled: false, threshold: 0, span: 64))]))
        let diff = ImageDiff.compare(expected: plain, actual: off, tolerance: .exact)
        XCTAssertTrue(diff.identical, "a disabled sort is the original frame: " + diff.summary)
    }

    func testPixelSortSaveReloadPersistsValuesAndThresholdChangesThePicture() throws {
        let r = try sortRenderer()
        let sort = PixelSort(isEnabled: true, threshold: 0.2, span: 32, direction: .vertical)
        let document = try sortPlasma([sortEntry(sort)])
        let shown = try sortFrame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.pixelSort, sort)
        let again = ImageDiff.compare(expected: shown, actual: try sortFrame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = try sortFrame(r, try sortPlasma(nil))
        XCTAssertGreaterThan(ImageDiff.compare(expected: plain, actual: shown, tolerance: .exact).changedPixels, 100)
        var higher = sort
        higher.threshold = 0.05
        let other = try sortFrame(r, try sortPlasma([sortEntry(higher)]))
        XCTAssertGreaterThan(ImageDiff.compare(expected: shown, actual: other, tolerance: .exact).changedPixels, 0,
                             "a different threshold gives a different ordering")
    }
}
#endif
