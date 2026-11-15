// ParticleTrailGoldenTests.swift — VIS-010-T08 (VIS-010-R10, S4): a generator-level golden image of VIS-008's seeded
// particle fountain with Long trails (the same seed, gravity and onsets as ParticleFountainGoldenTests; every 60 Hz
// frame from 0 s encoded with trails, so the streaks build up; captured at 0.6 s; glow off, Reduce flashing off),
// compared with QA-002's rule (QA-003's `ImageDiff`), decision table, record policy (`GOLDEN_RECORD=1`; refused
// under CI) and diff artifacts, per platform class. The goldens live in `GeneratorGoldens/ParticleTrails/<class>/`
// with their own manifest; their integrity test runs everywhere, Linux included. The trails-off fountain golden is
// unchanged (VIS-010-R2).
import Foundation
import GoldenImages
import XCTest

enum ParticleTrailGoldenCatalog {
    static let trails = GoldenSceneRun(name: "particle-trails", seed: 10_010, frameCount: 1, capturedFrames: [0],
                                         audio: .silent, reduceFlashing: false)
    static let runs = [trails]
    /// Onsets (seconds, strength, threshold) and the 60 Hz frame index captured (0.6 s).
    static let onsets: [(seconds: Double, strength: Float, threshold: Float)] = [(0, 0.5, 0.1), (0.25, 0.35, 0.1)]
    static let capturedFrame = 36

    static func nanoseconds(frame: Int) -> UInt64 { UInt64(frame) * 1_000_000_000 / 60 }

    static var root: URL {
        GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true)
            .appendingPathComponent("ParticleTrails", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class ParticleTrailGoldenIntegrityTests: XCTestCase {
    func testGeneratorGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: ParticleTrailGoldenCatalog.root, runs: ParticleTrailGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = ParticleTrailGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "Particle trail goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: ParticleTrailGoldenCatalog.root), 150_000)
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
import SceneRenderHarness
import VisualGenerators

final class ParticleTrailGoldenTests: XCTestCase {
    /// Renders the seeded fountain with Long trails, every frame to 0.6 s, as RGBA8.
    private func render(device: MTLDevice, run: GoldenSceneRun, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let generator = try ParticleFountainGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                      configuration: ParticleFountainConfiguration(gravity: 3.0))
        generator.trails = .long
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
        let rowBytes = resolution.width * 4
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * resolution.height, options: .storageModeShared))
        var next = 0
        let catalog = ParticleTrailGoldenCatalog.self
        var commands = try XCTUnwrap(queue.makeCommandBuffer())
        for frame in 0...catalog.capturedFrame {   // every frame on the injected clock, so the trail accumulates
            let now = catalog.nanoseconds(frame: frame)
            while next < catalog.onsets.count, UInt64((catalog.onsets[next].seconds * 1e9).rounded()) <= now {
                generator.enqueueOnset(atNanoseconds: UInt64((catalog.onsets[next].seconds * 1e9).rounded()),
                                       strength: catalog.onsets[next].strength, threshold: catalog.onsets[next].threshold)
                next += 1
            }
            commands = try XCTUnwrap(queue.makeCommandBuffer())
            let context = VisualFrameContext(timeNanoseconds: now, frameDuration: 1.0 / 60, reduceFlashing: run.reduceFlashing)
            let drawn = [Float]().withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
            }
            XCTAssertTrue(drawn)
            if frame < catalog.capturedFrame {
                commands.commit()
                commands.waitUntilCompleted()
            }
        }
        XCTAssertEqual(generator.simulation.spawnedCount, 24 + 24, "both bursts spawned")
        XCTAssertGreaterThan(generator.layout.squareCount, 30)
        XCTAssertNotNil(generator.trailPass)
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
            GoldenStore(folder: ParticleTrailGoldenCatalog.folder(p), platform: p)
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
                print("VIS-010 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("VIS-010 golden: \(note)\(wrote ? "" : " (unchanged)")")
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

    func testSeededFountainWithLongTrailsMatchesTheGolden() throws {
        try check(ParticleTrailGoldenCatalog.trails)
    }
}
#endif
