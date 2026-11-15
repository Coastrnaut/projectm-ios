// StarfieldGoldenTests.swift — VIS-016-T08 (VIS-016-R9, S3): a generator-level golden image of the starfield (seed
// 0x5EED0016, 2000 stars, Fast, spectrum palette; 64 fixture bands — a bass-heavy slope at full level for 0.25 s, then at
// 0.3 — at 60 Hz frames from 0 s, captured at 0.5 s; glow off, Reduce flashing off), compared with QA-002's rule (QA-003's
// `ImageDiff`), decision table, record policy (`GOLDEN_RECORD=1`; refused under CI) and diff artifacts, per platform
// class. The goldens live in `GeneratorGoldens/Starfield/<class>/` with their own manifest; their integrity test runs
// everywhere, Linux included. No scene document: the starfield is not an SCN-001 layer kind (VIS-016-R10).
import Foundation
import GoldenImages
import XCTest

enum StarfieldGoldenCatalog {
    static let field = GoldenSceneRun(name: "starfield", seed: 16, frameCount: 1, capturedFrames: [0],
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
            .appendingPathComponent("Starfield", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class StarfieldGoldenIntegrityTests: XCTestCase {
    func testGeneratorGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: StarfieldGoldenCatalog.root, runs: StarfieldGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = StarfieldGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "Starfield goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: StarfieldGoldenCatalog.root), 150_000)
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
import SceneRenderHarness
import VisualGenerators

final class StarfieldGoldenTests: XCTestCase {
    /// Renders the starfield at 0.5 s as RGBA8 (the frames before driven on the CPU, the last one encoded and read back).
    private func render(device: MTLDevice, run: GoldenSceneRun, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let generator = try StarfieldGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                               configuration: StarfieldConfiguration(density: 2000, speed: .fast))
        let catalog = StarfieldGoldenCatalog.self
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
        // Frames before the capture run the generator's per-frame CPU drive (bass from the low group, then advance);
        // the captured frame goes through `encode`.
        for frame in 0..<catalog.capturedFrame {
            let low = catalog.bands(frame: frame).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Double in
                MandalaBandGroups.from(b).low
            }
            generator.simulation.setBass(low)
            generator.simulation.advance(toNanoseconds: catalog.nanoseconds(frame: frame))
        }
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        let context = VisualFrameContext(timeNanoseconds: catalog.nanoseconds(frame: catalog.capturedFrame), frameDuration: 1.0 / 60,
                                         reduceFlashing: run.reduceFlashing)
        let drawn = catalog.bands(frame: catalog.capturedFrame).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: texture, commandBuffer: commands, bands: b, context: context)
        }
        XCTAssertTrue(drawn)
        XCTAssertEqual(generator.simulation.stepsRun, 120, "0.5 s of 1/240 s steps")
        XCTAssertGreaterThan(generator.layout.squareCount, 100, "stars are drawn")
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
            GoldenStore(folder: StarfieldGoldenCatalog.folder(p), platform: p)
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
                print("VIS-016 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("VIS-016 golden: \(note)\(wrote ? "" : " (unchanged)")")
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

    func testStarfieldMatchesTheGolden() throws {
        try check(StarfieldGoldenCatalog.field)
    }
}
#endif
