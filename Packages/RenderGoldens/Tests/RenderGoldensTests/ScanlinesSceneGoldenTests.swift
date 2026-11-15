// FX-018-T09: the scanlines through the golden scene renderer (SCN-001 decode → live state → layers → Compositor with
// the flash guard on → REC-001 capture; FX-018-S1, S4): zero intensity and disabled scanlines render exactly as no
// chain; a scanline scene saved and reloaded keeps its values and renders the same picture, in which exactly the rows
// (columns) with index mod spacing < thickness are black (intensity 1) and every other pixel equals the plain frame.
// Uses the FX-020 plasma run of `EffectChainSceneTests`. Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneFormat
import SceneRenderHarness
import XCTest

final class ScanlinesSceneGoldenTests: XCTestCase {
    private let scanlinesRun = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                              audio: .seededBands(count: 32))
    private let scanlinesResolution = GoldenResolution(width: 128, height: 96)

    private func scanlinesRenderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func scanlinesPlasma(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(scanlinesRun))
        document.effects = effects
        return document
    }

    private func scanlinesFrame(_ r: GoldenSceneRenderer, _ document: SceneDocument) throws -> GoldenImage {
        let images = try r.render(run: scanlinesRun, document: document, resolution: scanlinesResolution)
        return try XCTUnwrap(images[7])
    }

    private func scanlinesEntry(_ s: Scanlines) -> SceneEffectEntry {
        var entry = SceneEffectEntry(kind: OutputEffectKind.scanlines.rawValue, enabled: s.isEnabled)
        entry.parameters["spacing"] = .double(Double(s.spacing))
        entry.parameters["thickness"] = .double(Double(s.thickness))
        entry.parameters["intensity"] = .double(s.intensity)
        entry.parameters["vertical"] = .double(s.isVertical ? 1 : 0)
        return entry
    }

    func testScanlinesZeroIntensityRendersExactlyAsNoChain() throws {
        let r = try scanlinesRenderer()
        let plain = try scanlinesFrame(r, try scanlinesPlasma(nil))
        let zero = try scanlinesFrame(r, try scanlinesPlasma([scanlinesEntry(Scanlines(isEnabled: true, spacing: 2, intensity: 0))]))
        let off = try scanlinesFrame(r, try scanlinesPlasma([scanlinesEntry(Scanlines(isEnabled: false, intensity: 1))]))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "zero intensity or disabled scanlines are the original frame: " + diff.summary)
        }
    }

    func testScanlinesSaveReloadPersistsValuesAndBlacksOutExactlyThePredictedLines() throws {
        let r = try scanlinesRenderer()
        let plain = try scanlinesFrame(r, try scanlinesPlasma(nil))
        for lines in [Scanlines(isEnabled: true, spacing: 3, thickness: 1, intensity: 1),
                      Scanlines(isEnabled: true, spacing: 7, thickness: 3, intensity: 1, isVertical: true)] {
            let document = try scanlinesPlasma([scanlinesEntry(lines)])
            let shown = try scanlinesFrame(r, document)
            let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
            XCTAssertEqual(reloaded.effectSettings?.scanlines, lines)
            let again = ImageDiff.compare(expected: shown, actual: try scanlinesFrame(r, reloaded), tolerance: .exact)
            XCTAssertTrue(again.identical, again.summary)
            var blackLines = 0
            for y in 0..<96 {
                for x in 0..<128 {
                    let index: Int = lines.isVertical ? x : y
                    let a = plain.pixel(x: x, y: y), b = shown.pixel(x: x, y: y)
                    if index % lines.spacing < lines.effectiveThickness {
                        XCTAssertEqual([b.r, b.g, b.b], [0, 0, 0], "\(lines): (\(x), \(y)) is in a line")
                        blackLines += 1
                    } else {
                        XCTAssertEqual([a.r, a.g, a.b, a.a], [b.r, b.g, b.b, b.a], "\(lines): (\(x), \(y)) unchanged")
                    }
                }
            }
            XCTAssertGreaterThan(blackLines, 0)
        }
    }
}
#endif
