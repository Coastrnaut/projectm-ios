// QA-002-T09, T14, T15 (US2, US1, US3; QA-002-R10, R13, S2, S3, S5; contracts G2, G6): renders are
// deterministic; a deliberately changed renderer parameter fails comparison and produces the three images
// and the summary; record mode writes missing goldens and leaves unchanged ones untouched. Scratch output
// goes to temporary folders. Without a Metal device every test is skipped.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Foundation
import GoldenImages
import ParameterGraph
import SceneFormat
import SceneRenderHarness
import XCTest

final class GoldenGPUTests: XCTestCase {
    private var scratch: URL?

    override func tearDownWithError() throws {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
    }

    private func makeScratch() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("qa002-\(UUID().uuidString)", isDirectory: true)
        scratch = url
        return url
    }

    private func renderer() throws -> GoldenSceneRenderer {
        do {
            return try GoldenSceneRenderer()
        } catch {
            throw XCTSkip("No Metal device; the golden logic is covered by the plain tests.")
        }
    }

    private let small = GoldenResolution.all[0]

    /// S2: every scene twice, identical pixels (fresh compositor and layers each time).
    func testRendersAreDeterministic() throws {
        let renderer = try renderer()
        for run in GoldenSceneCatalog.runs {
            let document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(run))
            let a = try renderer.render(run: run, document: document, resolution: small)
            let b = try renderer.render(run: run, document: document, resolution: small)
            XCTAssertEqual(Set(a.keys), Set(run.capturedFrames), run.name)
            for frame in run.capturedFrames {
                XCTAssertEqual(a[frame]?.pixelSHA256, b[frame]?.pixelSHA256, "\(run.name) frame \(frame)")
            }
        }
    }

    /// The flash guard is part of what is captured: the strobe's bright frame is dimmed by it.
    func testStrobeIsCapturedAfterTheGuard() throws {
        let renderer = try renderer()
        let run = try XCTUnwrap(GoldenSceneCatalog.run(named: "strobe-guarded"))
        let document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(run))
        let unguardedRun = GoldenSceneRun(name: run.name, seed: run.seed, capturedFrames: run.capturedFrames, audio: run.audio,
                                          reduceFlashing: false)
        let guarded = try renderer.render(run: run, document: document, resolution: small)
        let unguarded = try renderer.render(run: unguardedRun, document: document, resolution: small)
        let g = try XCTUnwrap(guarded[6]), u = try XCTUnwrap(unguarded[6])
        XCTAssertFalse(GoldenComparison.compare(expected: u, actual: g).passed, "reduce flashing changes the strobe frame")
    }

    /// QA-002-R13, S3 (contract G6): material.plasma.scale 3 → 3.5 fails against the committed golden
    /// and writes expected, actual, diff and the summary.
    func testDeliberateRegressionProducesReviewableDiffs() throws {
        guard let platform = GoldenPlatformClass.current else { throw XCTSkip("No golden class on this device (pending)") }
        let renderer = try renderer()
        let run = try XCTUnwrap(GoldenSceneCatalog.run(named: "material-plasma"))
        var document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(run))
        XCTAssertEqual(document.parameters[ParameterID("material.plasma.scale")], .continuous(3))
        document.parameters[ParameterID("material.plasma.scale")] = .continuous(3.5)
        let actual = try XCTUnwrap(renderer.render(run: run, document: document, resolution: small)[7])
        let store = GoldenStore(folder: GoldenPaths.goldens(platform), platform: platform)
        let entry = try XCTUnwrap(store.manifest()?.entry(scene: run.name, width: small.width, frame: 7))
        let expected = try XCTUnwrap(store.image(entry))
        let comparison = GoldenComparison.compare(expected: expected, actual: actual)
        XCTAssertEqual(comparison.outcome, .exceedsTolerance)
        let verdict = GoldenDecision.decide(capture: "regression", platform: platform, policy: .compare, comparison: comparison,
                                            osSensitive: false, recordedOS: nil, currentOS: GoldenOS.currentVersion)
        XCTAssertTrue(verdict.isFailure)
        let root = makeScratch()
        let written = GoldenArtifacts.write(capture: "material-plasma-128x96-f7", expected: expected, actual: actual,
                                            comparison: comparison, root: root, platform: platform, test: nil)
        XCTAssertNil(written.problem)
        XCTAssertEqual(Set(written.files.map(\.lastPathComponent)), ["expected.png", "actual.png", "diff.png", "summary.txt"])
        let diff = try XCTUnwrap(GoldenPNG.decode(Data(contentsOf: written.folder.appendingPathComponent("diff.png"))))
        let red = stride(from: 0, to: diff.rgba.count, by: 4).filter { (i: Int) -> Bool in diff.rgba[i] >= 128 && diff.rgba[i + 1] == 0 }.count
        XCTAssertEqual(red, comparison.exceedingPixels, "every pixel above the threshold is red in the diff")
        let summary = try String(contentsOf: root.appendingPathComponent("\(platform.rawValue)/summary.txt"), encoding: .utf8)
        XCTAssertTrue(summary.contains("exceedsTolerance"))
    }

    /// QA-002-R10 (US3): record writes a missing golden and its entry, and leaves an unchanged one untouched.
    func testRecordWritesMissingAndKeepsUnchanged() throws {
        let renderer = try renderer()
        let run = try XCTUnwrap(GoldenSceneCatalog.run(named: "photo-gradient"))
        let document = try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(run))
        let image = try XCTUnwrap(renderer.render(run: run, document: document, resolution: small)[7])
        let store = GoldenStore(folder: makeScratch(), platform: .macOS)
        XCTAssertTrue(try store.record(image, scene: run.name, resolution: small, frame: 7, osSensitive: false, gpu: "test"))
        let file = store.folder.appendingPathComponent(GoldenSceneCatalog.goldenFileName(scene: run.name, resolution: small, frame: 7))
        let before = try Data(contentsOf: file)
        let manifestBefore = try Data(contentsOf: store.manifestURL)
        XCTAssertFalse(try store.record(image, scene: run.name, resolution: small, frame: 7, osSensitive: false, gpu: "test"),
                       "unchanged pixels: nothing written")
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try Data(contentsOf: store.manifestURL), manifestBefore)
        let entry = try XCTUnwrap(store.manifest()?.entry(scene: run.name, width: small.width, frame: 7))
        XCTAssertEqual(entry.pixelSHA256, image.pixelSHA256)
        XCTAssertEqual(entry.fileSHA256, GoldenSHA256.hex([UInt8](before)))
        XCTAssertEqual(store.image(entry), image, "the PNG reads back to the same pixels")
    }
}
#endif
