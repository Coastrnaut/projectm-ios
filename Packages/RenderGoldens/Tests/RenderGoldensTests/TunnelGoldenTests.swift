// TunnelGoldenTests.swift — VIS-015-T07 (VIS-015-R10, S5): a generator-level golden image of the tunnel (seed 1301,
// spectrum palette, 1 ring per beat; a manual 120 BPM tempo for 0.25 s, then none, so the speed is easing towards the
// base speed; the noise field's 64 fixture bands — a bass-heavy slope at full level for 0.25 s, then at 0.3 — at 60 Hz
// frames from 0 s, captured at 0.5 s; glow off, Reduce flashing off), compared with QA-002's
// rule (QA-003's `ImageDiff`), decision table, record policy (`GOLDEN_RECORD=1`; refused under CI) and diff artifacts,
// per platform class. The goldens live in `GeneratorGoldens/Tunnel/<class>/` with their own manifest; their integrity
// test runs everywhere, Linux included. No scene document: the tunnel is not an SCN-001 layer kind (VIS-015-R11).
import Foundation
import GoldenImages
import XCTest

enum TunnelGoldenCatalog {
    static let field = GoldenSceneRun(name: "tunnel", seed: 1_301, frameCount: 1, capturedFrames: [0],
                                      audio: .silent, reduceFlashing: false)
    static let runs = [field]
    /// The 60 Hz frame index captured (0.5 s).
    static let capturedFrame = 30

    static func nanoseconds(frame: Int) -> UInt64 { UInt64(frame) * 1_000_000_000 / 60 }

    /// The fixture's 64 bands at frame f.
    static func bands(frame f: Int) -> [Float] {
        let level: Float = f < 15 ? 1 : 0.3
        return (0..<64).map { (k: Int) -> Float in (1 - Float(k) / 64) * level }
    }

    static var root: URL {
        GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true)
            .appendingPathComponent("Tunnel", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class TunnelGoldenIntegrityTests: XCTestCase {
    func testGeneratorGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: TunnelGoldenCatalog.root, runs: TunnelGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = TunnelGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "Tunnel goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: TunnelGoldenCatalog.root), 200_000)   // a full-screen field compresses less than flat shapes
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
import SceneRenderHarness
import VisualGenerators

final class TunnelGoldenTests: XCTestCase {
    /// Renders the tunnel at 0.5 s as RGBA8 (every frame from 0 s encoded, the last one read back).
    private func render(device: MTLDevice, run: GoldenSceneRun, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let generator = try NoiseFieldGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                configuration: NoiseFieldConfiguration(seed: Int(run.seed), tunnelPace: 1))
        let catalog = TunnelGoldenCatalog.self
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        for frame in 0...catalog.capturedFrame {
            let context = VisualFrameContext(timeNanoseconds: catalog.nanoseconds(frame: frame), frameDuration: 1.0 / 60,
                                             reduceFlashing: run.reduceFlashing)
            generator.tempo = frame < 15 ? TunnelTempo(bpm: 120, confidence: 1) : .none
            let drawn = catalog.bands(frame: frame).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
        }
        XCTAssertGreaterThan(generator.tunnelDrive.phase, 0.5, "the rings have moved")
        XCTAssertTrue(generator.tunnelDrive.speed > 1.5 && generator.tunnelDrive.speed < 2, "easing to the base speed")
        let rowBytes = resolution.width * 4
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * resolution.height, options: .storageModeShared))
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: resolution.width, height: resolution.height, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * resolution.height)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
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

    private func check(_ run: GoldenSceneRun) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device; the shape logic is covered by the VisualGenerators CPU tests.")
        }
        let platform = GoldenPlatformClass.current
        let policy = GoldenRecordPolicy.current
        let store = platform.map { (p: GoldenPlatformClass) -> GoldenStore in
            GoldenStore(folder: TunnelGoldenCatalog.folder(p), platform: p)
        }
        for resolution in GoldenResolution.all {
            let actual = try render(device: device, run: run, resolution: resolution)
            // Two renders from scratch give the same pixels (determinism, QA-002 S2).
            XCTAssertEqual(try render(device: device, run: run, resolution: resolution).pixelSHA256,
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
                print("VIS-015 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("VIS-015 golden: \(note)\(wrote ? "" : " (unchanged)")")
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

    func testTunnelMatchesTheGolden() throws {
        try check(TunnelGoldenCatalog.field)
    }
}
#endif
