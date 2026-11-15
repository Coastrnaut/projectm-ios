// FX-012-T10: the mosaic through the golden scene renderer (SCN-001 decode → live state → layers → Compositor with the
// flash guard on → REC-001 capture; FX-012-S1, S5): block size 1 and a disabled mosaic render exactly as no chain; a
// hexagon mosaic scene saved and reloaded keeps its values and renders the same picture, which differs from the plain
// one. Uses the FX-020 plasma run of `EffectChainSceneTests`. Skipped without Metal.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneFormat
import SceneRenderHarness
import XCTest

final class MosaicSceneGoldenTests: XCTestCase {
    private let mosaicRun = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                           audio: .seededBands(count: 32))
    private let mosaicResolution = GoldenResolution(width: 128, height: 96)

    private func mosaicRenderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func mosaicPlasma(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(mosaicRun))
        document.effects = effects
        return document
    }

    private func mosaicFrame(_ r: GoldenSceneRenderer, _ document: SceneDocument) throws -> GoldenImage {
        let images = try r.render(run: mosaicRun, document: document, resolution: mosaicResolution)
        return try XCTUnwrap(images[7])
    }

    private func mosaicEntry(_ mosaic: Mosaic) -> SceneEffectEntry {
        var entry = SceneEffectEntry(kind: OutputEffectKind.mosaic.rawValue, enabled: mosaic.isEnabled)
        entry.parameters["size"] = .double(Double(mosaic.blockSize))
        entry.parameters["shape"] = .double(mosaic.shape == .hexagon ? 1 : 0)
        return entry
    }

    func testMosaicSizeOneRendersExactlyAsNoChain() throws {
        let r = try mosaicRenderer()
        let plain = try mosaicFrame(r, try mosaicPlasma(nil))
        let one = try mosaicFrame(r, try mosaicPlasma([mosaicEntry(Mosaic(isEnabled: true, blockSize: 1, shape: .hexagon))]))
        let off = try mosaicFrame(r, try mosaicPlasma([mosaicEntry(Mosaic(isEnabled: false, blockSize: 16))]))
        for image in [one, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "block size 1 or a disabled mosaic is the original frame: " + diff.summary)
        }
    }

    func testMosaicSaveReloadPersistsValuesAndPicture() throws {
        let r = try mosaicRenderer()
        let mosaic = Mosaic(isEnabled: true, blockSize: 8, shape: .hexagon)
        let document = try mosaicPlasma([mosaicEntry(mosaic)])
        let shown = try mosaicFrame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.mosaic, mosaic)
        let again = ImageDiff.compare(expected: shown, actual: try mosaicFrame(r, reloaded), tolerance: .exact)
        XCTAssertTrue(again.identical, again.summary)
        let plain = ImageDiff.compare(expected: try mosaicFrame(r, try mosaicPlasma(nil)), actual: shown, tolerance: .exact)
        XCTAssertGreaterThan(plain.changedPixels, 100, "the mosaic changes the picture: " + plain.summary)
    }
}
#endif
