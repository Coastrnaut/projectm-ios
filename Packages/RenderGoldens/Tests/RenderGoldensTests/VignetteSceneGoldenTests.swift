// FX-015-T09: the vignette through the golden scene renderer (SCN-001 decode → live state → layers → Compositor with
// the flash guard on → REC-001 capture; FX-015-S1, S5): zero intensity and a disabled vignette render exactly as no
// chain; a vignette scene saved and reloaded keeps its values and renders the same picture, whose corners are darker
// than the plain one while its middle is unchanged. Uses the FX-020 plasma run of `EffectChainSceneTests`. Skipped
// without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneFormat
import SceneRenderHarness
import XCTest

final class VignetteSceneGoldenTests: XCTestCase {
    private let vignetteRun = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                             audio: .seededBands(count: 32))
    private let vignetteResolution = GoldenResolution(width: 128, height: 96)

    private func vignetteRenderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func vignettePlasma(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(vignetteRun))
        document.effects = effects
        return document
    }

    private func vignetteFrame(_ r: GoldenSceneRenderer, _ document: SceneDocument) throws -> GoldenImage {
        let images = try r.render(run: vignetteRun, document: document, resolution: vignetteResolution)
        return try XCTUnwrap(images[7])
    }

    private func vignetteEntry(_ v: Vignette) -> SceneEffectEntry {
        var entry = SceneEffectEntry(kind: OutputEffectKind.vignette.rawValue, enabled: v.isEnabled)
        entry.parameters["intensity"] = .double(v.intensity)
        entry.parameters["softness"] = .double(v.softness)
        entry.parameters["centerX"] = .double(v.centerX)
        entry.parameters["centerY"] = .double(v.centerY)
        return entry
    }

    /// Mean of r + g + b over a square of `size` at (x, y).
    private func vignetteLevel(_ image: GoldenImage, x: Int, y: Int, size: Int) -> Double {
        var sum = 0
        for j in y..<(y + size) {
            for i in x..<(x + size) {
                let p = image.pixel(x: i, y: j)
                sum += Int(p.r) + Int(p.g) + Int(p.b)
            }
        }
        return Double(sum) / Double(size * size)
    }

    func testVignetteZeroIntensityRendersExactlyAsNoChain() throws {
        let r = try vignetteRenderer()
        let plain = try vignetteFrame(r, try vignettePlasma(nil))
        let zero = try vignetteFrame(r, try vignettePlasma([vignetteEntry(Vignette(isEnabled: true, intensity: 0, softness: 0.1, centerX: 0.2))]))
        let off = try vignetteFrame(r, try vignettePlasma([vignetteEntry(Vignette(isEnabled: false, intensity: 1))]))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "zero intensity or a disabled vignette is the original frame: " + diff.summary)
        }
    }

    func testVignetteSaveReloadPersistsValuesAndDarkensOnlyTheEdges() throws {
        let r = try vignetteRenderer()
        let vignette = Vignette(isEnabled: true, intensity: 1, softness: 0.5)
        let document = try vignettePlasma([vignetteEntry(vignette)])
        let shown = try vignetteFrame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.vignette, vignette)
        let again = ImageDiff.compare(expected: shown, actual: try vignetteFrame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = try vignetteFrame(r, try vignettePlasma(nil))
        XCTAssertGreaterThan(ImageDiff.compare(expected: plain, actual: shown, tolerance: .exact).changedPixels, 100)
        for (x, y) in [(60, 44), (64, 48), (63, 47)] {
            let a = plain.pixel(x: x, y: y), b = shown.pixel(x: x, y: y)
            XCTAssertEqual([a.r, a.g, a.b, a.a], [b.r, b.g, b.b, b.a], "middle pixel (\(x), \(y)) unchanged")
        }
        for (x, y) in [(0, 0), (120, 0), (0, 88), (120, 88)] {
            XCTAssertLessThan(vignetteLevel(shown, x: x, y: y, size: 8), vignetteLevel(plain, x: x, y: y, size: 8) * 0.5,
                              "corner at (\(x), \(y)) is darker")
        }
    }
}
#endif
