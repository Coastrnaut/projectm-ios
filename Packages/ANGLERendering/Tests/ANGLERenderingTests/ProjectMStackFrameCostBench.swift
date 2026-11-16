// CMP-001-T20 (CMP-001-S7 on hardware; the cost noted in ADR-0013) and CMP-002-T15 (projectM variant):
// compositor frame time with a projectM layer (`ProjectMLayerSource`, ANGLE's Metal backend) at the
// device's native screen size; 30 warm-up frames, then 600 measured, one command buffer per frame,
// waited for.
//
// * CMP-001 (CMP001_BENCH=1): projectM + a circular and a linear spectrum layer.
// * CMP-002 (CMP002_BENCH=1): an ordered `LayerStack` of 1-4 layers, bottom first: projectM, camera,
//   circular spectrum, linear spectrum. STAND-IN: the camera is `StubCameraFrameProvider` (a fixed
//   1920 x 1080 texture, no capture session); a unit test cannot run AVCapture.
//
// Two numbers per line, because projectM renders in ANGLE's own Metal command buffers: the
// compositor's buffer only waits for ANGLE's shared event on the GPU, so `medianMs`/`p95Ms`
// (gpuEndTime - gpuStartTime of the compositor's buffer) cover the compositing passes and may exclude
// the engine's draw. `wallMedianMs`/`wallP95Ms` (encode -> commit -> waitUntilCompleted, which waits
// for ANGLE's work too) are the whole frame including projectM. Report both.
//
// The preset is BENCH_PRESET (a path) or the engine's `110-per_pixel.milk` test preset (bundled in
// ANGLEDeviceTests); test presets are light, so this is a floor for projectM's cost, not a typical
// preset. Nothing is asserted about time. QA-011 cases `bench-cmp001-projectm`, `bench-cmp002-projectm`
// (ANGLEDeviceTests). Expected on a device: CMP-001 630 frames, < 15 s; CMP-002 4 x 630 frames, < 60 s.
#if canImport(Metal)
import AudioCore
import CameraLayer
import Compositor
import Foundation
import Metal
import ProjectMLayer
import SpectrumLayers
import VisualGenerators
import XCTest
#if os(iOS)
import UIKit
#endif

final class ProjectMStackFrameCostBench: XCTestCase {
    /// The engine's test presets in the source tree; on a device the test bundle's copy (as ProjectMLayerTests).
    private static let presets: URL = {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vendor/projectM/presets/tests")
        if FileManager.default.fileExists(atPath: source.path) { return source }
        return Bundle(for: ProjectMStackFrameCostBench.self).resourceURL?.appendingPathComponent("tests") ?? source
    }()
    private static let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    override func setUpWithError() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device")
        }
        self.device = device
        self.queue = queue
    }

    private static func presetPath() -> String {
        ProcessInfo.processInfo.environment["BENCH_PRESET"] ?? presets.appendingPathComponent("110-per_pixel.milk").path
    }

    /// A projectM layer with the bench preset and a PCM ring the timing loop keeps fed.
    private func makeProjectM(ring: NormalizedPCMRing) throws -> ProjectMLayerSource {
        let layer: ProjectMLayerSource
        do { layer = try ProjectMLayerSource(device: device) } catch {
            throw XCTSkip("ProjectMLayerSource unavailable here: \(error)")
        }
        try layer.loadPreset(atPath: Self.presetPath())
        layer.attach(pcm: ring)
        return layer
    }

    private func makeSpectra() throws -> (SpectrumLayerSource, SpectrumLayerSource) {
        let circular = try SpectrumLayerSource(
            device: device,
            generator: CircularSpectrumGenerator(device: device, pixelFormat: .rgba16Float,
                                                 configuration: CircularSpectrumConfiguration(barCount: .b64, background: Self.transparent)),
            name: "spectrum.circular")
        let linear = try SpectrumLayerSource(
            device: device,
            generator: LinearSpectrumGenerator(device: device, pixelFormat: .rgba16Float,
                                               configuration: LinearSpectrumConfiguration(barCount: .b64, background: Self.transparent)),
            name: "spectrum.linear")
        return (circular, linear)
    }

    private func output(_ screen: (width: Int, height: Int, scale: Double, source: String)) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: screen.width, height: screen.height,
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return try XCTUnwrap(device.makeTexture(descriptor: d))
    }

    func testProjectMAndTwoSpectraFrameTime() throws {
        guard ProcessInfo.processInfo.environment["CMP001_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set CMP001_BENCH=1")
        }
        let screen = ProjectMBenchScreen.native()
        let out = try output(screen)
        let ring = NormalizedPCMRing()
        let projectM = try makeProjectM(ring: ring)
        let (circular, linear) = try makeSpectra()
        let compositor = try Compositor(device: device, layers: [projectM, circular, linear])
        let timing = try ProjectMBenchTiming.measureComposite(compositor, output: out, queue: queue, ring: ring, scale: screen.scale)
        for k in 0..<3 { XCTAssertEqual(compositor.outcome(ofLayer: k), .rendered, "layer \(k) rendered") }
        ProjectMBenchTiming.emit([
            "task": "CMP-001-T20", "layers": 3, "stack": ["projectM", "spectrum.circular", "spectrum.linear"],
            "preset": URL(fileURLWithPath: Self.presetPath()).lastPathComponent,
            "device": device.name, "width": screen.width, "height": screen.height, "sizeSource": screen.source,
        ], timing)
    }

    func testProjectMStackGPUCostPerLayerCount() throws {
        guard ProcessInfo.processInfo.environment["CMP002_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set CMP002_BENCH=1")
        }
        let screen = ProjectMBenchScreen.native()
        let out = try output(screen)
        let names = ["projectM", "camera (stub provider, 1920x1080)", "spectrum.circular", "spectrum.linear"]
        let kinds: [LayerKind] = [LayerKind("projectM"), .camera, .circularSpectrum, .linearSpectrum]
        let settings = [LayerCompositeSettings(), LayerCompositeSettings(opacity: 0.6), LayerCompositeSettings(),
                        LayerCompositeSettings(blendMode: .screen)]
        var previousMedian: Double?
        for count in 1...4 {
            let ring = NormalizedPCMRing()
            let projectM = try makeProjectM(ring: ring)
            let stub = StubCameraFrameProvider(device: device, scenario: .granted,
                                               pattern: .columns([.init(red: 200, green: 40, blue: 40), .init(red: 40, green: 200, blue: 40),
                                                                  .init(red: 40, green: 40, blue: 200)]),
                                               width: 1920, height: 1080)
            let camera = CameraLayerSource(provider: stub)
            camera.start()
            let (circular, linear) = try makeSpectra()
            let sources: [any LayerSource] = Array(([projectM, camera, circular, linear] as [any LayerSource]).prefix(count))
            var stack = LayerStack()
            var ids: [LayerInstanceID] = []
            for k in 0..<count { ids.append(try stack.add(LayerDescriptor(kind: kinds[k]), settings: settings[k])) }
            let compositor = try Compositor(device: device)
            try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
                sources[ids.firstIndex(of: entry.id) ?? 0]
            }
            let timing = try ProjectMBenchTiming.measureComposite(compositor, output: out, queue: queue, ring: ring, scale: screen.scale)
            for k in 0..<count { XCTAssertEqual(compositor.outcome(ofLayer: k), .rendered, "layer \(k) (\(names[k])) rendered") }
            let median = ProjectMBenchTiming.percentile(timing.wallMs, 50)
            ProjectMBenchTiming.emit([
                "task": "CMP-002-T15", "layers": count, "stack": Array(names.prefix(count)), "added": names[count - 1],
                "cameraStandIn": "StubCameraFrameProvider 1920x1080 (no capture)",
                "preset": URL(fileURLWithPath: Self.presetPath()).lastPathComponent,
                "addedLayerWallMedianMs": ProjectMBenchTiming.round3(median - (previousMedian ?? 0)),
                "device": device.name, "width": screen.width, "height": screen.height, "sizeSource": screen.source,
            ], timing)
            previousMedian = median
        }
    }
}

// MARK: - Bench helpers (file-private copies of the Compositor benches' helpers)

fileprivate enum ProjectMBenchScreen {
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

fileprivate struct ProjectMBenchTimingResult {
    var gpuMs: [Double]
    var wallMs: [Double]
    var failedBuffers: Int
}

fileprivate enum ProjectMBenchTiming {
    static let warmUp = 30
    static let frames = 600
    static let frameNanoseconds: UInt64 = 16_666_667
    /// One 60 Hz frame of 44.1 kHz stereo (735 frames), a 220 Hz sine at -12 dBFS, reused every frame.
    static let pcm: [Float] = (0..<735).flatMap { (n: Int) -> [Float] in
        let s = 0.25 * sinf(2 * Float.pi * 220 * Float(n) / 44_100)
        return [s, s]
    }

    static func measureComposite(_ compositor: Compositor, output: MTLTexture, queue: MTLCommandQueue,
                                 ring: NormalizedPCMRing, scale: Double) throws -> ProjectMBenchTimingResult {
        let audio = LayerAudioBuffer()
        var bands = [Float](repeating: 0, count: 64)
        var gpu: [Double] = [], wall: [Double] = []
        gpu.reserveCapacity(frames)
        wall.reserveCapacity(frames)
        var failed = 0
        for i in 0..<(warmUp + frames) {
            pcm.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 735) }
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
        return ProjectMBenchTimingResult(gpuMs: gpu.sorted(), wallMs: wall.sorted(), failedBuffers: failed)
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

    static func emit(_ fields: [String: Any], _ t: ProjectMBenchTimingResult) {
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
