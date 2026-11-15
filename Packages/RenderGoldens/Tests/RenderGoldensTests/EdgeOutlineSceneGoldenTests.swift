// FX-014-T10: the edge outline through the golden scene renderer (SCN-001 decode → live state → layers → Compositor
// with the flash guard on → REC-001 capture; FX-014-S4, S5): a disabled outline renders exactly as no chain; an outline
// scene saved and reloaded keeps its values and renders the same picture, which differs from the plain one. Uses the
// FX-020 plasma run of `EffectChainSceneTests`. Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneFormat
import SceneRenderHarness
import XCTest

final class EdgeOutlineSceneGoldenTests: XCTestCase {
    private let outlineRun = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                            audio: .seededBands(count: 32))
    private let outlineResolution = GoldenResolution(width: 128, height: 96)

    private func outlineRenderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func outlinePlasma(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(outlineRun))
        document.effects = effects
        return document
    }

    private func outlineFrame(_ r: GoldenSceneRenderer, _ document: SceneDocument) throws -> GoldenImage {
        let images = try r.render(run: outlineRun, document: document, resolution: outlineResolution)
        return try XCTUnwrap(images[7])
    }

    private func outlineEntry(_ outline: EdgeOutline) -> SceneEffectEntry {
        var entry = SceneEffectEntry(kind: OutputEffectKind.edgeOutline.rawValue, enabled: outline.isEnabled)
        entry.parameters["threshold"] = .double(outline.threshold)
        entry.parameters["width"] = .double(Double(outline.width))
        entry.parameters["red"] = .double(outline.color.red)
        entry.parameters["green"] = .double(outline.color.green)
        entry.parameters["blue"] = .double(outline.color.blue)
        entry.parameters["mode"] = .double(outline.mode == .outlineOnly ? 1 : 0)
        return entry
    }

    func testEdgeOutlineDisabledRendersExactlyAsNoChain() throws {
        let r = try outlineRenderer()
        let plain = try outlineFrame(r, try outlinePlasma(nil))
        let off = try outlineFrame(r, try outlinePlasma([outlineEntry(EdgeOutline(isEnabled: false, threshold: 0.02, width: 3))]))
        let diff = ImageDiff.compare(expected: plain, actual: off, tolerance: .exact)
        XCTAssertTrue(diff.identical, "a disabled outline is the original frame: " + diff.summary)
    }

    func testEdgeOutlineSaveReloadPersistsValuesAndPicture() throws {
        let r = try outlineRenderer()
        let outline = EdgeOutline(isEnabled: true, threshold: 0.05, width: 2, color: EdgeOutlineColor(red: 1, green: 0, blue: 0))
        let document = try outlinePlasma([outlineEntry(outline)])
        let shown = try outlineFrame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.edgeOutline, outline)
        let again = ImageDiff.compare(expected: shown, actual: try outlineFrame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = ImageDiff.compare(expected: try outlineFrame(r, try outlinePlasma(nil)), actual: shown, tolerance: .exact)
        XCTAssertGreaterThan(plain.changedPixels, 50, "the outline changes the picture: " + plain.summary)
    }
}
#endif
