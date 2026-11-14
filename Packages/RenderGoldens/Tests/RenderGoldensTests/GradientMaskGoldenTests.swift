// GradientMaskGoldenTests.swift — CMP-008-T09 (CMP-008-S3; research CMP-008-D5): compositor-level golden images of
// a solid layer faded by a gradient mask, compared with QA-002's rule (QA-003's `ImageDiff`), decision table, record
// policy (`GOLDEN_RECORD=1`; refused under CI) and diff artifacts, per platform class:
//   gradient-mask-linear: a diagonal linear gradient with four stops (rise, fall, rise);
//   gradient-mask-radial: a radial gradient with three stops times a rounded-rectangle shape mask (CMP-007).
// The faded layer is drawn over an opaque dark-blue layer (so the PNG is opaque: ImageIO on the iOS simulator does
// not round-trip straight-alpha PNGs exactly) by the real `Compositor` into an rgba16Float output and captured with REC-001's
// `requestFrameCapture` and `FrameColorConversion.rgba8` (straight alpha), as the scene goldens are. The goldens
// live in `GeneratorGoldens/GradientMask/<class>/` with their own manifest; the integrity test runs everywhere.
import Foundation
import GoldenImages
import XCTest

enum GradientMaskGoldenCatalog {
    static let linear = GoldenSceneRun(name: "gradient-mask-linear", seed: 8_008, frameCount: 1, capturedFrames: [0],
                                       audio: .silent, reduceFlashing: false)
    static let radial = GoldenSceneRun(name: "gradient-mask-radial", seed: 8_009, frameCount: 1, capturedFrames: [0],
                                       audio: .silent, reduceFlashing: false)
    static let runs = [linear, radial]

    static var root: URL {
        GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true)
            .appendingPathComponent("GradientMask", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class GradientMaskGoldenIntegrityTests: XCTestCase {
    func testGradientMaskGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: GradientMaskGoldenCatalog.root, runs: GradientMaskGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = GradientMaskGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "gradient mask goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: GradientMaskGoldenCatalog.root), 150_000)
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FrameCapture
import Metal
import SceneRenderHarness

/// Clears its picture to one premultiplied colour every frame.
private final class SolidColorLayer: LayerSource {
    let layerName = "cmp008.solid"
    let fallback: LayerFallback = .transparent
    let color: MTLClearColor

    init(_ color: MTLClearColor) { self.color = color }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {}
    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = picture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = color
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }
}

/// Receives the capture on Metal's completion thread.
private final class CaptureSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CapturedPixels?
    let signal = DispatchSemaphore(value: 0)

    func store(_ pixels: CapturedPixels?) {
        lock.lock()
        value = pixels
        lock.unlock()
        signal.signal()
    }

    var pixels: CapturedPixels? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class GradientMaskGoldenTests: XCTestCase {
    private static func settings(_ run: GoldenSceneRun) throws -> LayerCompositeSettings {
        if run == GradientMaskGoldenCatalog.linear {
            let stops: [LayerGradientStop] = [LayerGradientStop(position: 0.05, alpha: 0.1), LayerGradientStop(position: 0.35, alpha: 1),
                                              LayerGradientStop(position: 0.65, alpha: 0.2), LayerGradientStop(position: 0.95, alpha: 0.8)]
            let gradient = try LayerGradientMask(kind: .linear(start: LayerPoint(x: 0, y: 0), end: LayerPoint(x: 1, y: 1)), stops: stops)
            return LayerCompositeSettings(gradientMask: gradient)
        }
        let stops: [LayerGradientStop] = [LayerGradientStop(position: 0, alpha: 1), LayerGradientStop(position: 0.5, alpha: 0.3),
                                          LayerGradientStop(position: 1, alpha: 0)]
        let gradient = try LayerGradientMask(kind: .radial(center: LayerPoint(x: 0.4, y: 0.55), radius: 0.7), stops: stops)
        let shape = try LayerMask(shape: .rectangle(cornerRadius: 0.2), transform: LayerMaskTransform(scale: LayerPoint(x: 1.2, y: 0.8)))
        return LayerCompositeSettings(mask: shape, gradientMask: gradient)
    }

    /// Composites the run's one frame at `resolution` and returns the capture as RGBA8 (straight alpha).
    private func render(device: MTLDevice, run: GoldenSceneRun, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: LayerKind("cmp008.backdrop")))
        try stack.add(LayerDescriptor(kind: .photo), settings: try Self.settings(run))
        let compositor = try Compositor(device: device)
        let faded = SolidColorLayer(MTLClearColor(red: 0.9, green: 0.45, blue: 0.1, alpha: 1))
        let backdrop = SolidColorLayer(MTLClearColor(red: 0.02, green: 0.03, blue: 0.12, alpha: 1))
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            entry.descriptor.kind == .photo ? faded : backdrop
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        let audio = LayerAudioBuffer()
        let slot = CaptureSlot()
        compositor.requestFrameCapture { (pixels: CapturedPixels?) in slot.store(pixels) }
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: run.presentationNanoseconds(frame: 0),
                                           contentScale: 2, reduceFlashing: run.reduceFlashing, audio: audio.context))
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
        XCTAssertEqual(slot.signal.wait(timeout: .now() + 5), .success, "capture delivered")
        let pixels = try XCTUnwrap(slot.pixels)
        let rgba8 = FrameColorConversion.rgba8(pixels, policy: .preserveCoverage)
        return try XCTUnwrap(GoldenImage(width: rgba8.width, height: rgba8.height, rgba: rgba8.rgba))
    }

    private func check(_ run: GoldenSceneRun) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device; the gradient logic is covered by the Compositor CPU reference tests.")
        }
        let platform = GoldenPlatformClass.current
        let policy = GoldenRecordPolicy.current
        let store = platform.map { (p: GoldenPlatformClass) -> GoldenStore in
            GoldenStore(folder: GradientMaskGoldenCatalog.folder(p), platform: p)
        }
        for resolution in GoldenResolution.all {
            let actual = try render(device: device, run: run, resolution: resolution)
            XCTAssertEqual(try render(device: device, run: run, resolution: resolution).pixelSHA256, actual.pixelSHA256, "deterministic")
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
                print("CMP-008 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("CMP-008 golden: \(note)\(wrote ? "" : " (unchanged)")")
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

    func testLinearGradientMaskMatchesTheGolden() throws {
        try check(GradientMaskGoldenCatalog.linear)
    }

    func testRadialGradientTimesShapeMatchesTheGolden() throws {
        try check(GradientMaskGoldenCatalog.radial)
    }
}
#endif
