// OscilloscopeGoldenTests.swift — VIS-003-T10 (VIS-003-R14, S4; research VIS-003-D4): a generator-level
// golden image of the oscilloscope drawing the sine fixture, compared with QA-002's rule, decision
// table, record policy (`GOLDEN_RECORD=1`; refused under CI) and diff artifacts, per platform class.
// The goldens live in `GeneratorGoldens/<class>/` with their own manifest, beside the scene goldens and
// checked by the same `GoldenIntegrity` with a one-entry catalog (the integrity test runs everywhere,
// Linux included). No scene document: the oscilloscope is not an SCN-001 layer kind (VIS-003-R12).
import Foundation
import GoldenImages
import XCTest

enum OscilloscopeGoldenCatalog {
    /// The fixture: a 440 Hz sine of amplitude 0.8 at 44.1 kHz; frame 0 warms up (no trigger reference),
    /// frame 1 (735 samples later) is captured. Medium line, 20 ms, glow off, Reduce flashing off.
    static let run = GoldenSceneRun(name: "waveform-oscilloscope-sine", seed: 3_003, frameCount: 2, capturedFrames: [1],
                                    audio: .silent, reduceFlashing: false)
    static let runs = [run]
    static let frequency = 440.0
    static let amplitude: Float = 0.8
    static let advance = 735

    /// The 4,096-sample history ending at absolute sample `end` (oldest first).
    static func history(endingAt end: Int) -> [Float] {
        (0..<4_096).map { (i: Int) -> Float in
            let n = Double(end - 4_096 + i)
            let cycles: Double = n * frequency / 44_100
            return amplitude * Float(sin(2 * Double.pi * (cycles - cycles.rounded(.down))))
        }
    }

    static var root: URL { GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true) }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class OscilloscopeGoldenIntegrityTests: XCTestCase {
    func testGeneratorGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: OscilloscopeGoldenCatalog.root, runs: OscilloscopeGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = OscilloscopeGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "generator goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: OscilloscopeGoldenCatalog.root), 100_000)
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
import SceneRenderHarness
import VisualGenerators

final class OscilloscopeGoldenTests: XCTestCase {
    /// Renders the fixture's frames at `resolution` and returns the captured frame as RGBA8.
    private func render(device: MTLDevice, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let generator = try OscilloscopeGenerator(device: device, pixelFormat: .bgra8Unorm_srgb)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
        let rowBytes = resolution.width * 4
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * resolution.height, options: .storageModeShared))
        let run = OscilloscopeGoldenCatalog.run
        var end = 60_000
        for frame in 0..<run.frameCount {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let history = OscilloscopeGoldenCatalog.history(endingAt: end)
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
            XCTAssertEqual(generator.layout.lastTrigger.mode, .triggered)
            end += OscilloscopeGoldenCatalog.advance
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

    func testSineFixtureMatchesTheGolden() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device; the golden logic is covered by the plain tests.")
        }
        let run = OscilloscopeGoldenCatalog.run
        let platform = GoldenPlatformClass.current
        let policy = GoldenRecordPolicy.current
        let store = platform.map { (p: GoldenPlatformClass) -> GoldenStore in
            GoldenStore(folder: OscilloscopeGoldenCatalog.folder(p), platform: p)
        }
        for resolution in GoldenResolution.all {
            let actual = try render(device: device, resolution: resolution)
            // Two renders from scratch give the same pixels (determinism, QA-002 S2).
            XCTAssertEqual(try render(device: device, resolution: resolution).pixelSHA256, actual.pixelSHA256)
            let frame = run.capturedFrames[0]
            let capture = "\(run.name)-\(resolution)-f\(frame)"
            let manifest = store?.manifest()
            var expected: GoldenImage?
            var comparison: GoldenComparisonResult?
            if let entry = manifest?.entry(scene: run.name, width: resolution.width, frame: frame), let golden = store?.image(entry) {
                expected = golden
                comparison = GoldenComparison.compare(expected: golden, actual: actual)
            }
            let verdict = GoldenDecision.decide(capture: capture, platform: platform, policy: policy, comparison: comparison,
                                                osSensitive: false, recordedOS: manifest?.recordedOS, currentOS: GoldenOS.currentVersion)
            switch verdict {
            case let .pass(note), let .notCompared(note), let .pending(note):
                print("VIS-003 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("VIS-003 golden: \(note)\(wrote ? "" : " (unchanged)")")
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
