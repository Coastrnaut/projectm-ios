// SHD-001-T19 (S8; R16): per-material GPU frame cost at full screen, median and 95th percentile over
// 600 frames at the documented defaults, for every material in `ProceduralMaterialCatalog`. Each
// material layer is driven directly (its own frame clock and command buffers, no compositor) into a
// picture of the device's native screen size, like SHD-002's GraphCostBench; 30 warm-up frames, then
// 600 measured, one command buffer per frame, waited for (MTLCommandBuffer gpuStartTime/gpuEndTime).
// Runs only with SHD001_BENCH=1 (an on-demand measurement: nothing is asserted about time). On a
// device it runs from DeviceTests.yml's MaterialsDeviceTests (QA-011 case `bench-shd001`); on a Mac
// or simulator the numbers are not device evidence. Expected on a device: 5 materials x 630 frames,
// about 15-30 s.
//
// Output: one machine-readable line per material,
//   BENCH-RESULT {"task":"SHD-001-T19","material":"material.plasma",...}
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import Metal
import ProceduralMaterials
import XCTest
#if os(iOS)
import UIKit
#endif

final class MaterialFrameCostBench: XCTestCase {
    func testPerMaterialFullScreenGPUCost() throws {
        guard ProcessInfo.processInfo.environment["SHD001_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set SHD001_BENCH=1")
        }
        let rig = try MaterialGPURig()
        let screen = MaterialBenchScreen.native()
        let descriptor = try XCTUnwrap(LayerPictureDescriptor(width: screen.width, height: screen.height))
        let picture = try rig.picture(width: screen.width, height: screen.height)
        let audio = LayerAudioBuffer()
        var bands = [Float](repeating: 0, count: 64)
        XCTAssertFalse(ProceduralMaterialCatalog.materials.isEmpty)
        for definition in ProceduralMaterialCatalog.materials {
            let layer = ProceduralMaterialLayer(definition)   // documented defaults, default variant
            try layer.prepare(picture: descriptor, device: rig.device)
            var clock = LayerFrameClock()
            let timing = try MaterialBenchTiming.measure(queue: rig.queue) { (commands: MTLCommandBuffer, i: Int) throws in
                // A moving mid-level spectrum so the audio-reactive path runs (reactivity stays at its default).
                for b in 0..<bands.count { bands[b] = 0.4 + 0.3 * sinf(Float(i) * 0.1 + Float(b) * 0.2) }
                audio.set(frame: nil, bands: bands, events: [])
                let frame = clock.next(presentationTimeNanoseconds: 1_000_000_000 + UInt64(i) * MaterialGPURig.frameNanoseconds,
                                       outputWidth: screen.width, outputHeight: screen.height,
                                       contentScale: screen.scale, reduceFlashing: false)
                try layer.render(into: picture, commandBuffer: commands, frame: frame, audio: audio.context)
            }
            MaterialBenchTiming.emit([
                "task": "SHD-001-T19", "material": definition.id, "variant": layer.resolution.drawn,
                "device": rig.device.name, "width": screen.width, "height": screen.height, "sizeSource": screen.source,
            ], timing)
        }
    }
}

// MARK: - Bench helpers (file-private copies; CompositorTests and ANGLERenderingTests carry their own)

/// The output size: BENCH_WIDTH/BENCH_HEIGHT if set, else the device's native screen in portrait
/// pixels (UIWindowScene.screen.nativeBounds), else the iPhone 15's 1179 x 2556.
fileprivate enum MaterialBenchScreen {
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

fileprivate struct MaterialBenchTimingResult {
    var gpuMs: [Double]
    var wallMs: [Double]
    var failedBuffers: Int
}

fileprivate enum MaterialBenchTiming {
    static let warmUp = 30
    static let frames = 600

    /// Encodes `warmUp + frames` command buffers, one at a time, and keeps the last `frames` samples.
    static func measure(queue: MTLCommandQueue, _ encode: (MTLCommandBuffer, Int) throws -> Void) throws -> MaterialBenchTimingResult {
        var gpu: [Double] = [], wall: [Double] = []
        gpu.reserveCapacity(frames)
        wall.reserveCapacity(frames)
        var failed = 0
        for i in 0..<(warmUp + frames) {
            let commands = try XCTUnwrap(queue.makeCommandBuffer())
            let start = DispatchTime.now().uptimeNanoseconds
            try encode(commands, i)
            commands.commit()
            commands.waitUntilCompleted()
            let end = DispatchTime.now().uptimeNanoseconds
            if commands.error != nil { failed += 1 }
            if i >= warmUp {
                gpu.append((commands.gpuEndTime - commands.gpuStartTime) * 1000)
                wall.append(Double(end - start) / 1_000_000)
            }
        }
        XCTAssertEqual(failed, 0, "command buffer errors")
        return MaterialBenchTimingResult(gpuMs: gpu.sorted(), wallMs: wall.sorted(), failedBuffers: failed)
    }

    /// Nearest-rank percentile of sorted samples.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return .nan }
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

    /// Prints `BENCH-RESULT <json>` (sorted keys, one line).
    static func emit(_ fields: [String: Any], _ t: MaterialBenchTimingResult) {
        var out = fields
        out["frames"] = t.gpuMs.count
        out["warmUpFrames"] = warmUp
        out["medianMs"] = round3(percentile(t.gpuMs, 50))
        out["p95Ms"] = round3(percentile(t.gpuMs, 95))
        out["maxMs"] = round3(t.gpuMs.last ?? .nan)
        out["meanMs"] = round3(t.gpuMs.reduce(0, +) / Double(max(t.gpuMs.count, 1)))
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
