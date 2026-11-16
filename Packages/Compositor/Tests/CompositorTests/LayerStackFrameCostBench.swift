// CMP-002-T15 (CMP-002-S6, R15) and CMP-001-T20 (CMP-001-S7, the material variant): compositor GPU
// time per frame at the device's native screen size, 30 warm-up frames then 600 measured, one command
// buffer per frame, waited for (MTLCommandBuffer gpuStartTime/gpuEndTime).
//
// * CMP-002 (CMP002_BENCH=1): an ordered `LayerStack` of 1, 2, 3 and 4 layers, bottom first: the Noise
//   Flow material, the camera, a circular spectrum, a linear spectrum. STAND-IN: the camera is
//   `StubCameraFrameProvider` (a fixed 1920 x 1080 BGRA texture, no capture session), because a unit
//   test cannot run AVCapture; it measures the camera layer's sampling and compositing, not capture,
//   CVMetalTexture wrapping or YUV conversion. The projectM variant is in ANGLERenderingTests
//   (ProjectMStackFrameCostBench).
// * CMP-001 (CMP001_BENCH=1): a compositor with a material and two spectrum layers. ANGLE/projectM is
//   not available to this package's tests; the projectM variant is ProjectMStackFrameCostBench.
//
// Nothing is asserted about time (an on-demand measurement). On a device these run from DeviceTests.yml's
// CompositorDeviceTests (QA-011 cases `bench-cmp002`, `bench-cmp001`); Mac and simulator numbers are not
// device evidence. Expected on a device: CMP-002 4 x 630 frames, about 15-30 s; CMP-001 630 frames, < 10 s.
//
// Output: one line per measurement, `BENCH-RESULT {"task":"CMP-002-T15","layers":2,...}`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CameraLayer
import Compositor
import Foundation
import Metal
import ProceduralMaterials
import SpectrumLayers
import VisualGenerators
import XCTest
#if os(iOS)
import UIKit
#endif

final class LayerStackFrameCostBench: XCTestCase {
    private static let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// The four CMP-002 layers, bottom first, with their stack kinds. Fresh sources for every stack.
    private static func makeLayers(_ device: MTLDevice) throws -> [(LayerKind, LayerCompositeSettings, any LayerSource, String)] {
        let material = ProceduralMaterialCatalog.makeLayer(.noiseFlow)
        let stub = StubCameraFrameProvider(device: device, scenario: .granted,
                                           pattern: .columns([.init(red: 200, green: 40, blue: 40), .init(red: 40, green: 200, blue: 40),
                                                              .init(red: 40, green: 40, blue: 200)]),
                                           width: 1920, height: 1080)
        let camera = CameraLayerSource(provider: stub)
        camera.start()
        let circular = try SpectrumLayerSource(
            device: device,
            generator: CircularSpectrumGenerator(device: device, pixelFormat: .rgba16Float,
                                                 configuration: CircularSpectrumConfiguration(barCount: .b64, background: transparent)),
            name: "spectrum.circular")
        let linear = try SpectrumLayerSource(
            device: device,
            generator: LinearSpectrumGenerator(device: device, pixelFormat: .rgba16Float,
                                               configuration: LinearSpectrumConfiguration(barCount: .b64, background: transparent)),
            name: "spectrum.linear")
        return [
            (.material, LayerCompositeSettings(), material, material.layerName),
            (.camera, LayerCompositeSettings(opacity: 0.6), camera, "camera (stub provider, 1920x1080)"),
            (.circularSpectrum, LayerCompositeSettings(), circular, "spectrum.circular"),
            (.linearSpectrum, LayerCompositeSettings(blendMode: .screen), linear, "spectrum.linear"),
        ]
    }

    func testOrderedStackGPUCostPerLayerCount() throws {
        guard ProcessInfo.processInfo.environment["CMP002_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set CMP002_BENCH=1")
        }
        let gpu = try GPURig()
        let screen = StackBenchScreen.native()
        let output = try gpu.output(.bgra8Unorm_srgb, width: screen.width, height: screen.height)
        var previousMedian: Double?
        for count in 1...4 {
            let layers = try Self.makeLayers(gpu.device)
            let used = Array(layers.prefix(count))
            var stack = LayerStack()
            var ids: [LayerInstanceID] = []
            for (kind, settings, _, _) in used { ids.append(try stack.add(LayerDescriptor(kind: kind), settings: settings)) }
            let sources = used.map { $0.2 }
            let compositor = try Compositor(device: gpu.device)
            try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                sources[ids.firstIndex(of: entry.id) ?? 0]
            }
            let timing = try StackBenchTiming.measureComposite(compositor, output: output, queue: gpu.queue, scale: screen.scale)
            for k in 0..<count {
                XCTAssertEqual(compositor.outcome(ofLayer: k), .rendered, "layer \(k) (\(used[k].3)) rendered")
            }
            let median = StackBenchTiming.percentile(timing.gpuMs, 50)
            StackBenchTiming.emit([
                "task": "CMP-002-T15", "layers": count, "stack": used.map { $0.3 }, "added": used[count - 1].3,
                "cameraStandIn": "StubCameraFrameProvider 1920x1080 (no capture)",
                "addedLayerMedianMs": StackBenchTiming.round3(median - (previousMedian ?? 0)),
                "device": gpu.device.name, "width": screen.width, "height": screen.height, "sizeSource": screen.source,
            ], timing)
            previousMedian = median
        }
    }

    func testMaterialAndTwoSpectraFrameTime() throws {
        guard ProcessInfo.processInfo.environment["CMP001_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set CMP001_BENCH=1")
        }
        let gpu = try GPURig()
        let screen = StackBenchScreen.native()
        let output = try gpu.output(.bgra8Unorm_srgb, width: screen.width, height: screen.height)
        let all = try Self.makeLayers(gpu.device)
        let used = [all[0], all[2], all[3]]   // material, circular, linear (no camera)
        let compositor = try Compositor(device: gpu.device, layers: used.map { $0.2 })
        let timing = try StackBenchTiming.measureComposite(compositor, output: output, queue: gpu.queue, scale: screen.scale)
        for k in 0..<used.count { XCTAssertEqual(compositor.outcome(ofLayer: k), .rendered, "layer \(k) rendered") }
        StackBenchTiming.emit([
            "task": "CMP-001-T20", "layers": used.count, "stack": used.map { $0.3 },
            "note": "material stands in for projectM (ANGLE is not in Compositor's tests); see ProjectMStackFrameCostBench",
            "device": gpu.device.name, "width": screen.width, "height": screen.height, "sizeSource": screen.source,
        ], timing)
    }
}

// MARK: - Bench helpers (file-private; ProceduralMaterialsTests and ANGLERenderingTests carry their own copies)

/// BENCH_WIDTH/BENCH_HEIGHT if set, else the native screen in portrait pixels, else 1179 x 2556 (iPhone 15).
fileprivate enum StackBenchScreen {
    static func native() -> (width: Int, height: Int, scale: Double, source: String) {
        let env = ProcessInfo.processInfo.environment
        if let w = env["BENCH_WIDTH"].flatMap(Int.init), let h = env["BENCH_HEIGHT"].flatMap(Int.init), w > 0, h > 0 {
            return (w, h, 3, "env")
        }
        #if os(iOS)
        if Thread.isMainThread {
            let found: (CGSize, CGFloat)? = MainActor.assumeIsolated {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                return scenes.first.map { ($0.screen.nativeBounds.size, $0.screen.nativeScale) }
            }
            if let (size, scale) = found, size.width > 0, size.height > 0 {
                let a = Int(size.width.rounded()), b = Int(size.height.rounded())
                return (min(a, b), max(a, b), Double(scale), "nativeBounds")
            }
        }
        #endif
        return (1179, 2556, 3, "fallback")
    }
}

fileprivate struct StackBenchTimingResult {
    var gpuMs: [Double]
    var wallMs: [Double]
    var failedBuffers: Int
}

fileprivate enum StackBenchTiming {
    static let warmUp = 30
    static let frames = 600
    static let frameNanoseconds: UInt64 = 16_666_667

    /// `warmUp + frames` composites with a moving 64-band spectrum; keeps the last `frames` samples.
    static func measureComposite(_ compositor: Compositor, output: MTLTexture, queue: MTLCommandQueue,
                                 scale: Double) throws -> StackBenchTimingResult {
        let audio = LayerAudioBuffer()
        var bands = [Float](repeating: 0, count: 64)
        var gpu: [Double] = [], wall: [Double] = []
        gpu.reserveCapacity(frames)
        wall.reserveCapacity(frames)
        var failed = 0
        for i in 0..<(warmUp + frames) {
            for b in 0..<bands.count { bands[b] = 0.4 + 0.3 * sinf(Float(i) * 0.1 + Float(b) * 0.2) }
            audio.set(frame: nil, bands: bands, events: [])
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let start = DispatchTime.now().uptimeNanoseconds
            let ok = compositor.composite(into: output, commandBuffer: commands,
                                          presentationTimeNanoseconds: 1_000_000_000 + UInt64(i) * frameNanoseconds,
                                          contentScale: scale, reduceFlashing: false, audio: audio.context)
            commands.commit()
            commands.waitUntilCompleted()
            let end = DispatchTime.now().uptimeNanoseconds
            if !ok || commands.error != nil { failed += 1 }
            if i >= warmUp {
                gpu.append((commands.gpuEndTime - commands.gpuStartTime) * 1000)
                wall.append(Double(end - start) / 1_000_000)
            }
        }
        XCTAssertEqual(failed, 0, "composite failures or command buffer errors")
        return StackBenchTimingResult(gpuMs: gpu.sorted(), wallMs: wall.sorted(), failedBuffers: failed)
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

    static func emit(_ fields: [String: Any], _ t: StackBenchTimingResult) {
        var out = fields
        out["frames"] = t.gpuMs.count
        out["warmUpFrames"] = warmUp
        out["medianMs"] = round3(percentile(t.gpuMs, 50))
        out["p95Ms"] = round3(percentile(t.gpuMs, 95))
        out["maxMs"] = round3(t.gpuMs.last ?? .nan)
        out["wallMedianMs"] = round3(percentile(t.wallMs, 50))
        out["wallP95Ms"] = round3(percentile(t.wallMs, 95))
        out["failedBuffers"] = t.failedBuffers
        #if DEBUG
        out["configuration"] = "Debug"
        #else
        out["configuration"] = "Release"
        #endif
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        print("BENCH-RESULT " + json)
    }
}
#endif
