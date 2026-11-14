// LissajousGoldenTests.swift — VIS-004-T07 (VIS-004-R15, S5; research VIS-004-D7): generator-level golden
// images of the Lissajous scope drawing the in-phase (L = R) and quadrature (R = L shifted 90°) fixtures,
// compared with QA-002's rule (QA-003's `ImageDiff`), decision table, record policy (`GOLDEN_RECORD=1`;
// refused under CI) and diff artifacts, per platform class. The goldens live in
// `GeneratorGoldens/Lissajous/<class>/` with their own manifest, so the oscilloscope's one-scene integrity
// check is untouched; their integrity test runs everywhere, Linux included. No scene document: the
// Lissajous is not an SCN-001 layer kind (VIS-004-R12).
import Foundation
import GoldenImages
import XCTest

enum LissajousGoldenCatalog {
    /// Frame 0 warms the auto gain; frame 1 (735 frames later) is captured. X/Y, persistence off, glow off,
    /// Reduce flashing off; a 440 Hz sine of amplitude 0.8 at 44.1 kHz.
    static let inPhase = GoldenSceneRun(name: "lissajous-inphase", seed: 4_004, frameCount: 2, capturedFrames: [1],
                                        audio: .silent, reduceFlashing: false)
    static let quadrature = GoldenSceneRun(name: "lissajous-quadrature", seed: 4_005, frameCount: 2, capturedFrames: [1],
                                           audio: .silent, reduceFlashing: false)
    static let runs = [inPhase, quadrature]
    static let frequency = 440.0
    static let amplitude = 0.8
    static let advance = 735
    static let frames = 2_048

    /// The interleaved stereo history (L, R; oldest first) ending at absolute frame `end`.
    static func history(quadrature: Bool, endingAt end: Int) -> [Float] {
        var out = [Float](repeating: 0, count: 2 * frames)
        for i in 0..<frames {
            let n = Double(end - frames + i)
            let cycles: Double = n * frequency / 44_100
            let phase: Double = 2 * Double.pi * (cycles - cycles.rounded(.down))
            out[2 * i] = Float(amplitude * sin(phase))
            out[2 * i + 1] = Float(amplitude * (quadrature ? cos(phase) : sin(phase)))
        }
        return out
    }

    static var root: URL {
        GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true)
            .appendingPathComponent("Lissajous", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class LissajousGoldenIntegrityTests: XCTestCase {
    func testGeneratorGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: LissajousGoldenCatalog.root, runs: LissajousGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = LissajousGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "Lissajous goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: LissajousGoldenCatalog.root), 150_000)
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
import SceneRenderHarness
import VisualGenerators

final class LissajousGoldenTests: XCTestCase {
    /// Renders `run`'s frames at `resolution` and returns the captured frame as RGBA8.
    private func render(device: MTLDevice, run: GoldenSceneRun, quadrature: Bool, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let generator = try LissajousGenerator(device: device, pixelFormat: .bgra8Unorm_srgb)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
        let rowBytes = resolution.width * 4
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * resolution.height, options: .storageModeShared))
        var end = 60_000
        for frame in 0..<run.frameCount {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let history = LissajousGoldenCatalog.history(quadrature: quadrature, endingAt: end)
            let context = VisualFrameContext(timeNanoseconds: run.presentationNanoseconds(frame: frame), frameDuration: 1.0 / 60,
                                             reduceFlashing: run.reduceFlashing)
            let drawn = history.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn, "frame \(frame)")
            if run.capturedFrames.contains(frame) {
                let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
                blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                          sourceSize: MTLSize(width: resolution.width, height: resolution.height, depth: 1), to: buffer,
                          destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * resolution.height)
                blit.endEncoding()
            }
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertEqual(commands.status, .completed)
            end += LissajousGoldenCatalog.advance
        }
        let bytes = buffer.contents().bindMemory(to: UInt8.self, capacity: rowBytes * resolution.height)
        var rgba = [UInt8](repeating: 0, count: rowBytes * resolution.height)
        for p in 0..<(resolution.width * resolution.height) {
            rgba[p * 4] = bytes[p * 4 + 2]
            rgba[p * 4 + 1] = bytes[p * 4 + 1]
            rgba[p * 4 + 2] = bytes[p * 4]
            rgba[p * 4 + 3] = bytes[p * 4 + 3]
        }
        return try XCTUnwrap(GoldenImage(width: resolution.width, height: resolution.height, rgba: rgba))
    }

    private func check(_ run: GoldenSceneRun, quadrature: Bool) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device; the shape logic is covered by the VisualGenerators CPU tests.")
        }
        let platform = GoldenPlatformClass.current
        let policy = GoldenRecordPolicy.current
        let store = platform.map { (p: GoldenPlatformClass) -> GoldenStore in
            GoldenStore(folder: LissajousGoldenCatalog.folder(p), platform: p)
        }
        for resolution in GoldenResolution.all {
            let actual = try render(device: device, run: run, quadrature: quadrature, resolution: resolution)
            // Two renders from scratch give the same pixels (determinism, QA-002 S2).
            XCTAssertEqual(try render(device: device, run: run, quadrature: quadrature, resolution: resolution).pixelSHA256,
                           actual.pixelSHA256)
            let frame = run.capturedFrames[0]
            let capture = "\(run.name)-\(resolution)-f\(frame)"
            let manifest = store?.manifest()
            var expected: GoldenImage?
            var comparison: GoldenComparisonResult?
            if let entry = manifest?.entry(scene: run.name, width: resolution.width, frame: frame), let golden = store?.image(entry) {
                expected = golden
                comparison = GoldenComparison.compare(expected: golden, actual: actual, tolerance: .golden)
            }
            let verdict = GoldenDecision.decide(capture: capture, platform: platform, policy: policy, comparison: comparison,
                                                osSensitive: false, recordedOS: manifest?.recordedOS, currentOS: GoldenOS.currentVersion)
            switch verdict {
            case let .pass(note), let .notCompared(note), let .pending(note):
                print("VIS-004 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("VIS-004 golden: \(note)\(wrote ? "" : " (unchanged)")")
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

    func testInPhaseFixtureMatchesTheGolden() throws {
        try check(LissajousGoldenCatalog.inPhase, quadrature: false)
    }

    func testQuadratureFixtureMatchesTheGolden() throws {
        try check(LissajousGoldenCatalog.quadrature, quadrature: true)
    }

    /// The two goldens are far apart under QA-003's diff: the shapes are distinguishable in pixels too.
    func testTheTwoShapesDifferInPixels() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device.") }
        let resolution = GoldenResolution.all[0]
        let line = try render(device: device, run: LissajousGoldenCatalog.inPhase, quadrature: false, resolution: resolution)
        let circle = try render(device: device, run: LissajousGoldenCatalog.quadrature, quadrature: true, resolution: resolution)
        let result = GoldenComparison.compare(expected: line, actual: circle, tolerance: .golden)
        XCTAssertEqual(result.outcome, .exceedsTolerance, "a line and a circle must not pass as the same picture")
    }
}
#endif
