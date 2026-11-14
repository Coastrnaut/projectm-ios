// QA-002-T13 (US1; QA-002-R4-R12, S1; contract G4): every golden scene at both fixed resolutions,
// every captured frame compared with this platform class's golden. Failures attach and write expected,
// actual and diff images. `GOLDEN_RECORD=1` (simulator: `TEST_RUNNER_GOLDEN_RECORD=1`) records on
// purpose; with CI set it fails and writes nothing. Without a Metal device every test is skipped.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Foundation
import GoldenImages
import SceneRenderHarness
import XCTest

final class GoldenRenderSuiteTests: XCTestCase {
    func testPhotoGradient() throws { try check("photo-gradient") }
    func testMaterialPlasma() throws { try check("material-plasma") }
    func testGraphHueRings() throws { try check("graph-hue-rings") }
    func testSpectrumCircular() throws { try check("spectrum-circular") }
    func testStackComposite() throws { try check("stack-composite") }
    func testStrobeGuarded() throws { try check("strobe-guarded") }
    func testTextCaption() throws { try check("text-caption") }

    /// Every catalog scene has a test above.
    func testEveryCatalogSceneIsChecked() {
        let checked: Set<String> = ["photo-gradient", "material-plasma", "graph-hue-rings", "spectrum-circular", "stack-composite",
                                    "strobe-guarded", "text-caption"]
        XCTAssertEqual(Set(GoldenSceneCatalog.runs.map(\.name)), checked)
    }

    private func check(_ name: String) throws {
        let run = try XCTUnwrap(GoldenSceneCatalog.run(named: name))
        let renderer: GoldenSceneRenderer
        do {
            renderer = try GoldenSceneRenderer()
        } catch {
            throw XCTSkip("No Metal device; the golden logic is covered by the plain tests.")
        }
        let document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(run))
        let platform = GoldenPlatformClass.current
        let policy = GoldenRecordPolicy.current
        let store = platform.map { (p: GoldenPlatformClass) -> GoldenStore in GoldenStore(folder: GoldenPaths.goldens(p), platform: p) }
        for resolution in GoldenResolution.all {
            let frames = try renderer.render(run: run, document: document, resolution: resolution)
            for frame in run.capturedFrames {
                let actual = try XCTUnwrap(frames[frame])
                let capture = "\(run.name)-\(resolution)-f\(frame)"
                let manifest = store?.manifest()
                var expected: GoldenImage?
                var comparison: GoldenComparisonResult?
                if let entry = manifest?.entry(scene: run.name, width: resolution.width, frame: frame) {
                    let present = store.map { (s: GoldenStore) -> Bool in
                        FileManager.default.fileExists(atPath: s.folder.appendingPathComponent(entry.file).path)
                    } ?? false
                    if present, entry.pixelSHA256 == actual.pixelSHA256 {
                        comparison = GoldenComparison.compare(expected: actual, actual: actual, tolerance: .golden)
                    } else if let golden = store?.image(entry) {
                        expected = golden
                        comparison = GoldenComparison.compare(expected: golden, actual: actual, tolerance: .golden)
                    }
                }
                let verdict = GoldenDecision.decide(capture: capture, platform: platform, policy: policy, comparison: comparison,
                                                    osSensitive: run.osSensitive, recordedOS: manifest?.recordedOS,
                                                    currentOS: GoldenOS.currentVersion)
                switch verdict {
                case let .pass(note), let .notCompared(note), let .pending(note):
                    print("QA-002 golden: \(note)")
                case let .write(note):
                    let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                            osSensitive: run.osSensitive, gpu: renderer.device.name)
                    print("QA-002 golden: \(note)\(wrote ? "" : " (unchanged)")")
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
}
#endif
