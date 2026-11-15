// FX-016-T10: the lens distortion through the golden scene renderer (SCN-001 decode → live state → layers → Compositor
// with the flash guard on → REC-001 capture; FX-016-S5): strength 0 and a disabled warp render exactly as no chain; a
// barrel scene saved and reloaded keeps its values and renders the same picture, which differs from the plain one; a
// barrel without zoom shows black corners while a pincushion fills them with picture. Uses the FX-020 plasma run of
// `EffectChainSceneTests`. Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneFormat
import SceneRenderHarness
import XCTest

final class LensDistortionSceneGoldenTests: XCTestCase {
    private let lensRun = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                         audio: .seededBands(count: 32))
    private let lensResolution = GoldenResolution(width: 128, height: 96)

    private func lensRenderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func lensPlasma(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(lensRun))
        document.effects = effects
        return document
    }

    private func lensFrame(_ r: GoldenSceneRenderer, _ document: SceneDocument) throws -> GoldenImage {
        let images = try r.render(run: lensRun, document: document, resolution: lensResolution)
        return try XCTUnwrap(images[7])
    }

    private func lensEntry(_ lens: LensDistortion) -> SceneEffectEntry {
        var entry = SceneEffectEntry(kind: OutputEffectKind.lensDistortion.rawValue, enabled: lens.isEnabled)
        entry.parameters["strength"] = .double(lens.strength)
        entry.parameters["zoomToFill"] = .double(lens.zoomToFill ? 1 : 0)
        return entry
    }

    private func lensCornerSum(_ image: GoldenImage) -> Int {
        var sum = 0
        for (x, y) in [(0, 0), (127, 0), (0, 95), (127, 95)] {
            let p = image.pixel(x: x, y: y)
            sum += Int(p.r) + Int(p.g) + Int(p.b)
        }
        return sum
    }

    func testLensDistortionZeroStrengthRendersExactlyAsNoChain() throws {
        let r = try lensRenderer()
        let plain = try lensFrame(r, try lensPlasma(nil))
        let zero = try lensFrame(r, try lensPlasma([lensEntry(LensDistortion(isEnabled: true, strength: 0, zoomToFill: false))]))
        let off = try lensFrame(r, try lensPlasma([lensEntry(LensDistortion(isEnabled: false, strength: 1, zoomToFill: false))]))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "zero strength or a disabled warp is the original frame: " + diff.summary)
        }
    }

    func testLensDistortionSaveReloadPersistsValuesAndWarpsThePicture() throws {
        let r = try lensRenderer()
        let barrel = LensDistortion(isEnabled: true, strength: 1, zoomToFill: false)
        let document = try lensPlasma([lensEntry(barrel)])
        let shown = try lensFrame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.lensDistortion, barrel)
        let again = ImageDiff.compare(expected: shown, actual: try lensFrame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = try lensFrame(r, try lensPlasma(nil))
        XCTAssertGreaterThan(ImageDiff.compare(expected: plain, actual: shown, tolerance: .exact).changedPixels, 100)
        XCTAssertEqual(lensCornerSum(shown), 0, "barrel without zoom: the corners outside the picture are black")
        let pinch = try lensFrame(r, try lensPlasma([lensEntry(LensDistortion(isEnabled: true, strength: -1))]))
        XCTAssertGreaterThan(ImageDiff.compare(expected: plain, actual: pinch, tolerance: .exact).changedPixels, 100)
        XCTAssertGreaterThan(lensCornerSum(pinch), 0, "pincushion: the corners show the picture")
        let filled = try lensFrame(r, try lensPlasma([lensEntry(LensDistortion(isEnabled: true, strength: 1, zoomToFill: true))]))
        XCTAssertGreaterThan(lensCornerSum(filled), 0, "barrel with zoom to fill: the corners show the picture")
    }
}
#endif
