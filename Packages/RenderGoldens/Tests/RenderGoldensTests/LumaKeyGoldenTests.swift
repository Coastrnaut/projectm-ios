// LumaKeyGoldenTests.swift — CMP-009-T09 (CMP-009-S3): a compositor-level golden image of a black luma key, compared
// with QA-002's rule (QA-003's `ImageDiff`), decision table, record policy (`GOLDEN_RECORD=1`; refused under CI) and diff
// artifacts, per platform class:
//   luma-key-black: a picture with a black band, an orange patch, a green patch and a grey ramp, keyed with a black key
//   (low 0, high 0.15, softness 0.1) over an opaque dark-blue layer, so the black band shows the blue and the ramp fades in.
// Drawn by the real `Compositor` into an rgba16Float output and captured with REC-001's `requestFrameCapture` and
// `FrameColorConversion.rgba8`, as the CMP-008 goldens are. The goldens live in `GeneratorGoldens/LumaKey/<class>/` with
// their own manifest; the integrity test runs everywhere.
import Foundation
import GoldenImages
import XCTest

enum LumaKeyGoldenCatalog {
    static let black = GoldenSceneRun(name: "luma-key-black", seed: 9_009, frameCount: 1, capturedFrames: [0],
                                      audio: .silent, reduceFlashing: false)
    static let runs = [black]

    static var root: URL {
        GoldenPaths.packageRoot.appendingPathComponent("GeneratorGoldens", isDirectory: true)
            .appendingPathComponent("LumaKey", isDirectory: true)
    }

    static func folder(_ platform: GoldenPlatformClass) -> URL { root.appendingPathComponent(platform.rawValue, isDirectory: true) }
}

final class LumaKeyGoldenIntegrityTests: XCTestCase {
    func testLumaKeyGoldensAreCompleteAndSmall() {
        let issues = GoldenIntegrity.check(goldensRoot: LumaKeyGoldenCatalog.root, runs: LumaKeyGoldenCatalog.runs)
        XCTAssertEqual(issues.map(\.description), [])
        for platform in GoldenPlatformClass.allCases {
            let manifest = LumaKeyGoldenCatalog.folder(platform).appendingPathComponent(GoldenManifest.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path), "luma key goldens for \(platform.rawValue)")
        }
        XCTAssertLessThan(GoldenIntegrity.totalBytes(goldensRoot: LumaKeyGoldenCatalog.root), 100_000)
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FrameCapture
import Metal
import SceneRenderHarness

/// Clears its picture to one premultiplied colour every frame.
private final class LumaSolidLayer: LayerSource {
    let layerName = "cmp009.solid"
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

/// The keyed picture, built for the prepared size (half floats, premultiplied linear) and copied in every frame:
/// columns 0…0.3 black, 0.3…0.55 orange (top) / green (bottom), 0.55…1 a grey ramp (displayed 0…0.6, left to right).
private final class LumaPatternLayer: LayerSource {
    let layerName = "cmp009.pattern"
    let fallback: LayerFallback = .transparent
    private var staging: MTLTexture?

    static func texel(_ i: Int, _ j: Int, width: Int, height: Int) -> SIMD4<Float> {
        let u: Double = (Double(i) + 0.5) / Double(width)
        let v: Double = (Double(j) + 0.5) / Double(height)
        if u < 0.3 { return SIMD4<Float>(0, 0, 0, 1) }
        if u < 0.55 { return v < 0.5 ? SIMD4<Float>(0.9, 0.45, 0.1, 1) : SIMD4<Float>(0.1, 0.7, 0.2, 1) }
        let displayed: Double = (u - 0.55) / 0.45 * 0.6
        let g: Float = Float(LayerBlend.decode(displayed))
        return SIMD4<Float>(g, g, g, 1)
    }

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        let w: Int = picture.width
        let h: Int = picture.height
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: LayerPictureDescriptor.metalPixelFormat, width: w, height: h,
                                                         mipmapped: false)
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw .resourceUnavailable("pattern staging") }
        var halves: [UInt16] = []
        halves.reserveCapacity(w * h * 4)
        for j in 0..<h {
            for i in 0..<w {
                let p: SIMD4<Float> = Self.texel(i, j, width: w, height: h)
                halves.append(Float16(p.x).bitPattern)
                halves.append(Float16(p.y).bitPattern)
                halves.append(Float16(p.z).bitPattern)
                halves.append(Float16(p.w).bitPattern)
            }
        }
        halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.baseAddress {
                t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * 8)
            }
        }
        staging = t
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        guard let staging, let blit = commandBuffer.makeBlitCommandEncoder() else { throw .resourceUnavailable("pattern blit") }
        blit.copy(from: staging, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: min(staging.width, picture.width), height: min(staging.height, picture.height), depth: 1),
                  to: picture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }
}

/// Receives the capture on Metal's completion thread.
private final class LumaCaptureSlot: @unchecked Sendable {
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

final class LumaKeyGoldenTests: XCTestCase {
    /// Composites the run's one frame at `resolution` and returns the capture as RGBA8 (straight alpha).
    private func render(device: MTLDevice, run: GoldenSceneRun, resolution: GoldenResolution) throws -> GoldenImage {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: LayerKind("cmp009.backdrop")))
        try stack.add(LayerDescriptor(kind: .photo), settings: LayerCompositeSettings(lumaKey: LayerLumaKey(low: 0, high: 0.15, softness: 0.1)))
        let compositor = try Compositor(device: device)
        let faded = LumaPatternLayer()
        let backdrop = LumaSolidLayer(MTLClearColor(red: 0.03, green: 0.08, blue: 0.35, alpha: 1))
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            entry.descriptor.kind == .photo ? faded : backdrop
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: resolution.width,
                                                         height: resolution.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        let audio = LayerAudioBuffer()
        let slot = LumaCaptureSlot()
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
            throw XCTSkip("No Metal device; the key logic is covered by the Compositor CPU reference tests.")
        }
        let platform = GoldenPlatformClass.current
        let policy = GoldenRecordPolicy.current
        let store = platform.map { (p: GoldenPlatformClass) -> GoldenStore in
            GoldenStore(folder: LumaKeyGoldenCatalog.folder(p), platform: p)
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
                print("CMP-009 golden: \(note)")
            case let .write(note):
                let wrote = try XCTUnwrap(store).record(actual, scene: run.name, resolution: resolution, frame: frame,
                                                        osSensitive: false, gpu: device.name)
                print("CMP-009 golden: \(note)\(wrote ? "" : " (unchanged)")")
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

    func testBlackLumaKeyMatchesTheGolden() throws {
        try check(LumaKeyGoldenCatalog.black)
    }
}
#endif
