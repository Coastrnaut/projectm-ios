// ParticleOrbitGoldenTests.swift — VIS-009-T09 (VIS-009-R13, S6; research VIS-009-D7): a generator-level golden image
// of a seeded particle orbit (seed 0x5EED0009, 160 particles, base radius 0.5; steady bass 0.5 from 0 s and one beat at
// 0.2 s; simulated with 60 Hz frames from 0 s and captured at 0.5 s; glow off, Reduce flashing off), compared with
// QA-002's rule (QA-003's `ImageDiff`), decision table, record policy (`GOLDEN_RECORD=1`; refused under CI) and diff
// artifacts, per platform class. The goldens live in `GeneratorGoldens/ParticleOrbit/<class>/` with their own
// manifest; their integrity test runs everywhere, Linux included. No scene document: the orbit is not an SCN-001 layer
// kind (VIS-009-R11).
import Foundation
import GoldenImages
import XCTest

enum ParticleOrbitGoldenCatalog {
    static let orbit = GoldenSceneRun(name: "particle-orbit", seed: 9_009, frameCount: 1, capturedFrames: [0],
                                      audio: .silent, reduceFlashing: false)
    static let runs = [orbit]
    /// The steady bass, the beat (seconds) and the 60 Hz frame index captured (0.5 s).
    static let bass = 0.5
    static let beatSeconds = 0.2
    static let capturedFrame = 30

    static func nanoseconds(frame: Int) -> UInt64 { UInt64(frame) * 1_000_000_000 / 60 }

    static var root: URL {
        GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true)
            .appendingPathComponent("ParticleOrbit", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class ParticleOrbitGoldenIntegrityTests: XCTestCase {
    func testGeneratorGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: ParticleOrbitGoldenCatalog.root, runs: ParticleOrbitGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = ParticleOrbitGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "Particle orbit goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: ParticleOrbitGoldenCatalog.root), 150_000)
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
import SceneRenderHarness
import VisualGenerators

final class ParticleOrbitGoldenTests: XCTestCase {
    /// Renders the seeded orbit at 0.5 s as RGBA8.
    private func render(device: MTLDevice, run: GoldenSceneRun, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let generator = try ParticleOrbitGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                   configuration: ParticleOrbitConfiguration())
        let catalog = ParticleOrbitGoldenCatalog.self
        let beat = UInt64((catalog.beatSeconds * 1e9).rounded())
        var beatQueued = false
        for frame in 0...catalog.capturedFrame {   // the drive before every frame, on the injected clock
            let now = catalog.nanoseconds(frame: frame)
            if !beatQueued, beat <= now {
                generator.enqueueBeat(atNanoseconds: beat)
                beatQueued = true
            }
            generator.drive(base: 0.5, bass: catalog.bass)
            if frame < catalog.capturedFrame { generator.simulation.advance(toNanoseconds: now) }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
        let rowBytes = resolution.width * 4
        let buffer = try XCTUnwrap(device.makeBuffer(length: rowBytes * resolution.height, options: .storageModeShared))
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: ParticleOrbitGoldenCatalog.nanoseconds(frame: ParticleOrbitGoldenCatalog.capturedFrame),
                                         frameDuration: 1.0 / 60, reduceFlashing: run.reduceFlashing)
        let drawn = [Float]().withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
        }
        XCTAssertTrue(drawn)
        XCTAssertEqual(generator.layout.squareCount, 161)
        XCTAssertEqual(generator.simulation.beatsApplied, 1)
        XCTAssertEqual(generator.simulation.radius, 0.6, accuracy: 0.01)
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
            GoldenStore(folder: ParticleOrbitGoldenCatalog.folder(p), platform: p)
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
                print("VIS-009 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("VIS-009 golden: \(note)\(wrote ? "" : " (unchanged)")")
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

    func testSeededOrbitMatchesTheGolden() throws {
        try check(ParticleOrbitGoldenCatalog.orbit)
    }
}
#endif
