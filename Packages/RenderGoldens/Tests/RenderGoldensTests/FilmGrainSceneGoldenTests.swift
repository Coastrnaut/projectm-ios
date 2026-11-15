// FX-017-T10: film grain through the golden scene renderer (SCN-001 decode → live state → layers → Compositor with the
// flash guard on → REC-001 capture; FX-017-S1, S2, S5): opacity 0 and a disabled grain render exactly as no chain; a
// grain scene saved and reloaded keeps its values and renders the same picture twice; a different seed gives another
// picture; and the grain picture (plasma run, opacity 0.6, size 2, colour, seed 7, static) matches its stored golden per
// platform class (`GeneratorGoldens/FilmGrain/<class>/`, QA-002's rule, `GOLDEN_RECORD=1` to record, refused under CI).
// The integrity test runs everywhere, Linux included. Skipped without Metal.
import Foundation
import GoldenImages
import XCTest

enum FilmGrainGoldenCatalog {
    /// The manifest's scene name (the picture is the FX-020 plasma run with grain).
    static let scene = "film-grain"
    static let manifestRun = GoldenSceneRun(name: scene, seed: 1_002, intervalNanoseconds: 100_000_000, audio: .seededBands(count: 32))
    static let runs = [manifestRun]

    static var root: URL {
        GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true)
            .appendingPathComponent("FilmGrain", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class FilmGrainGoldenIntegrityTests: XCTestCase {
    func testFilmGrainGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: FilmGrainGoldenCatalog.root, runs: FilmGrainGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = FilmGrainGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "film grain goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: FilmGrainGoldenCatalog.root), 400_000)   // noise compresses poorly
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Metal
import SceneFormat
import SceneRenderHarness

final class FilmGrainSceneGoldenTests: XCTestCase {
    private let grainRun = GoldenSceneRun(name: "material-plasma", seed: 1_002, intervalNanoseconds: 100_000_000,
                                          audio: .seededBands(count: 32))
    private let grainGolden = FilmGrain(isEnabled: true, opacity: 0.6, size: 2, isColor: true, seed: 7)

    private func grainRenderer() throws -> GoldenSceneRenderer {
        do { return try GoldenSceneRenderer() } catch { throw XCTSkip("No Metal device: \(error)") }
    }

    private func grainPlasma(_ effects: [SceneEffectEntry]?) throws -> SceneDocument {
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(grainRun))
        document.effects = effects
        return document
    }

    private func grainFrame(_ r: GoldenSceneRenderer, _ document: SceneDocument,
                            resolution: GoldenResolution = GoldenResolution(width: 128, height: 96)) throws -> GoldenImage {
        let images = try r.render(run: grainRun, document: document, resolution: resolution)
        return try XCTUnwrap(images[7])
    }

    private func grainEntry(_ g: FilmGrain) -> [SceneEffectEntry] {
        var live = SceneEffectSettings()
        live.filmGrain = g
        var entry = SceneEffectEntry(kind: OutputEffectKind.filmGrain.rawValue, enabled: g.isEnabled)
        if g.isEnabled { entry = live.entries(over: nil)[0] }
        return [entry]
    }

    func testFilmGrainZeroOpacityRendersExactlyAsNoChain() throws {
        let r = try grainRenderer()
        let plain = try grainFrame(r, try grainPlasma(nil))
        let zero = try grainFrame(r, try grainPlasma(grainEntry(FilmGrain(isEnabled: true, opacity: 0, size: 3, isColor: true, isAnimated: true))))
        let off = try grainFrame(r, try grainPlasma(grainEntry(FilmGrain(isEnabled: false, opacity: 1))))
        for image in [zero, off] {
            let diff = ImageDiff.compare(expected: plain, actual: image, tolerance: .exact)
            XCTAssertTrue(diff.identical, "opacity 0 or a disabled grain is the original frame: " + diff.summary)
        }
    }

    func testFilmGrainSaveReloadIsStableAndSeedsDiffer() throws {
        let r = try grainRenderer()
        let document = try grainPlasma(grainEntry(grainGolden))
        let shown = try grainFrame(r, document)
        let reloaded = try GoldenSceneRenderer.document(from: document.encoded())
        XCTAssertEqual(reloaded.effectSettings?.filmGrain, grainGolden)
        XCTAssertEqual(shown.pixelSHA256, try grainFrame(r, reloaded).pixelSHA256, "the same seed renders the same picture")
        let plain = try grainFrame(r, try grainPlasma(nil))
        XCTAssertGreaterThan(ImageDiff.compare(expected: plain, actual: shown, tolerance: .exact).changedPixels, 128 * 96 / 2)
        var other = grainGolden
        other.seed = 8
        XCTAssertNotEqual(try grainFrame(r, try grainPlasma(grainEntry(other))).pixelSHA256, shown.pixelSHA256, "seeds differ")
    }

    func testFilmGrainMatchesTheGolden() throws {
        let r = try grainRenderer()
        let platform = GoldenPlatformClass.current
        let policy = GoldenRecordPolicy.current
        let store = platform.map { (p: GoldenPlatformClass) -> GoldenStore in
            GoldenStore(folder: FilmGrainGoldenCatalog.folder(p), platform: p)
        }
        let frame = 7
        for resolution in GoldenResolution.all {
            let actual = try grainFrame(r, try grainPlasma(grainEntry(grainGolden)), resolution: resolution)
            let scene = FilmGrainGoldenCatalog.scene
            let capture = "\(scene)-\(resolution)-f\(frame)"
            let manifest = store?.manifest()
            var expected: GoldenImage?
            var comparison: GoldenComparisonResult?
            if let entry = manifest?.entry(scene: scene, width: resolution.width, frame: frame), let golden = store?.image(entry) {
                expected = golden
                comparison = GoldenComparison.compare(expected: golden, actual: actual, tolerance: .golden)
            }
            let verdict = GoldenDecision.decide(capture: capture, platform: platform, policy: policy, comparison: comparison,
                                                osSensitive: false, recordedOS: manifest?.recordedOS, currentOS: GoldenOS.currentVersion)
            switch verdict {
            case let .pass(note), let .notCompared(note), let .pending(note):
                print("FX-017 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: scene, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: MTLCreateSystemDefaultDevice()?.name ?? "unknown")
                print("FX-017 golden: \(note)\(wrote ? "" : " (unchanged)")")
            case let .fail(message):
                var detail = message
                if let platform, policy != .refused {
                    let written = GoldenArtifacts.write(capture: capture, expected: expected, actual: actual, comparison: comparison,
                                                        root: GoldenPaths.diffRoot, platform: platform, test: self)
                    detail += "; artifacts: " + (written.problem ?? written.folder.path)
                }
                XCTFail(detail)
            }
        }
    }
}
#endif
