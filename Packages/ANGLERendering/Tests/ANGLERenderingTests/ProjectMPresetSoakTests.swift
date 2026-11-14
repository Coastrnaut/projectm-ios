// QA-006-T09 (US3; QA-006-R11, S4; research QA-006-D7): the projectM preset-switch soak on the iOS
// simulator. One `ProjectMLayerSource` in one `Compositor` (its own `TexturePool`) at 64 × 64 switches
// through five test presets every 40 frames; every frame an AUD-016 two-tone sine (110 Hz left, 440 Hz
// right, 44.1 kHz) is written into the layer's PCM ring, and frame n is presented at n/60 s (injected
// clock). 1,200 frames = 20 s simulated = 6 cycles. The QA-006 verdict (`RenderSoakRecorder`, Compositor)
// must pass: no render error (preset load, encode, command buffer, PERF-014 fault), memory slope and bound
// on `MTLDevice.currentAllocatedSize` (pool live bytes when it reports 0), pool checkouts constant, nothing
// alive or checked out after release. `QA006_SOAK_SECONDS=<n>` lengthens it (scripts/run_render_soak.py
// --angle). The JSON report goes to QA006_REPORT_DIR or the temporary folder and is attached. Simulator
// results are not device evidence (QA-006-T13 {device}).
import XCTest
import AudioCore
import Darwin
import Compositor
import Metal
@testable import ProjectMLayer

final class ProjectMPresetSoakTests: XCTestCase {
    private static let presets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")
    private static let presetFiles = ["100-square.milk", "110-per_pixel.milk", "200-wave.milk", "202-wave.milk",
                                      "240-wave-smooth-00.milk"]
    private static let dwellFrames = 40
    private static let interval: UInt64 = 16_666_667

    private final class Weak {
        weak var object: AnyObject?
        init(_ object: AnyObject) { self.object = object }
    }

    func testPresetSwitchSoakIsBoundedAndErrorFree() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw XCTSkip("No Metal device") }
        let requested = ProcessInfo.processInfo.environment["QA006_SOAK_SECONDS"].flatMap(Double.init)
        let seconds = requested.map { (s: Double) -> Double in s > 0 ? s : 20 } ?? 20
        let frames = Int((seconds * 60).rounded())
        let started = Date()
        let usesDevice = device.currentAllocatedSize > 0
        var recorder = RenderSoakRecorder()
        let pool = TexturePool(device: device)
        var weakObjects: [Weak] = []
        try autoreleasepool {
            try soak(device: device, queue: queue, pool: pool, frames: frames, usesDevice: usesDevice, recorder: &recorder,
                     weakObjects: &weakObjects)
        }
        let alive = weakObjects.filter { (w: Weak) -> Bool in w.object != nil }.count
        recorder.record(release: RenderSoakRelease(checkedOutTextures: pool.counters.checkedOutTextures, liveObjects: alive))

        let cycles = frames / (Self.dwellFrames * Self.presetFiles.count)
        let report = RenderSoakReport(name: "qa006-projectm-soak", platform: Self.platform,
                                      memorySource: usesDevice ? "deviceAllocatedSize" : "poolEstimate", width: 64, height: 64,
                                      frames: frames, simulatedSeconds: Double(frames) / 60,
                                      wallSeconds: Date().timeIntervalSince(started), switches: frames / Self.dwellFrames - 1,
                                      cycles: cycles,
                                      settings: ["presets": Self.presetFiles.joined(separator: ","), "dwellFrames": "\(Self.dwellFrames)",
                                                 "audio": "sine 110 Hz left, 440 Hz right, 44.1 kHz"],
                                      recorder: recorder)
        let url = try write(report)
        print("QA-006 \(report.name) [\(report.platform), \(report.memorySource)]: \(report.verdict.summary); \(frames) frames in "
              + "\(String(format: "%.1f", report.wallSeconds)) s wall; report \(url.path)")
        XCTAssertEqual(report.errorCount, 0, "\(report.errors)")
        XCTAssertTrue(report.verdict.passed, report.verdict.summary)
    }

    private func soak(device: MTLDevice, queue: MTLCommandQueue, pool: TexturePool, frames: Int, usesDevice: Bool,
                      recorder: inout RenderSoakRecorder, weakObjects: inout [Weak]) throws {
        let layer = try ProjectMLayerSource(device: device)
        let ring = NormalizedPCMRing()
        layer.attach(pcm: ring)
        let compositor = try Compositor(device: device, layers: [layer], texturePool: pool)
        weakObjects.append(Weak(layer))
        weakObjects.append(Weak(compositor))
        let tone = try ToneGenerator(signal: .sine(SineTone(left: 110, right: 440, amplitude: 0.5)),
                                     format: try ToneFormat(sampleRate: 44_100, channels: 2))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        let output = try XCTUnwrap(device.makeTexture(descriptor: d))
        let cycleFrames = Self.dwellFrames * Self.presetFiles.count
        var highWater = 0
        var memory = 0
        var audioFrame: Int64 = 0
        for frame in 0..<frames {
            try autoreleasepool {
                if frame % Self.dwellFrames == 0 {
                    let index = (frame / Self.dwellFrames) % Self.presetFiles.count
                    if frame > 0 {
                        let counters = pool.counters
                        let previous = Self.presetFiles[(index + Self.presetFiles.count - 1) % Self.presetFiles.count]
                        recorder.record(dwell: RenderSoakDwellSample(cycle: (frame - 1) / cycleFrames, scene: previous,
                                                                     checkedOutTextures: counters.checkedOutTextures,
                                                                     checkedOutBytes: counters.checkedOutBytes, liveScenes: 1))
                    }
                    if frame > 0 && frame % cycleFrames == 0 {
                        recorder.record(cycle: RenderSoakCycleSample(cycle: frame / cycleFrames - 1, memoryHighWaterBytes: highWater,
                                                                     memoryEndBytes: memory, poolLiveBytes: pool.counters.liveBytes,
                                                                     poolMisses: pool.counters.misses, frames: cycleFrames,
                                                                     processFootprintBytes: Self.footprint()))
                        highWater = 0
                    }
                    do {
                        try layer.loadPreset(atPath: Self.presets.appendingPathComponent(Self.presetFiles[index]).path)
                    } catch {
                        recorder.record(error: RenderSoakError(frame: frame, scene: Self.presetFiles[index], message: "load: \(error)"))
                    }
                }
                let samples = tone.interleaved(frames: 735, startFrame: audioFrame)   // 44,100 / 60
                audioFrame += 735
                samples.withUnsafeBufferPointer { (p: UnsafeBufferPointer<Float>) -> Void in ring.write(p.baseAddress!, frames: 735) }
                let commands = try XCTUnwrap(queue.makeCommandBuffer())
                let scene = Self.presetFiles[(frame / Self.dwellFrames) % Self.presetFiles.count]
                if !compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: UInt64(frame) * Self.interval,
                                         contentScale: 1, reduceFlashing: true, audio: .empty) {
                    recorder.record(error: RenderSoakError(frame: frame, scene: scene, message: "frame not encoded"))
                }
                commands.commit()
                commands.waitUntilCompleted()
                if let error = commands.error {
                    recorder.record(error: RenderSoakError(frame: frame, scene: scene, message: "command buffer: \(error)"))
                }
                memory = usesDevice ? device.currentAllocatedSize : pool.counters.liveBytes
                highWater = max(highWater, memory)
            }
        }
        if frames % cycleFrames == 0, frames > 0 {
            let counters = pool.counters
            recorder.record(dwell: RenderSoakDwellSample(cycle: frames / cycleFrames - 1, scene: Self.presetFiles.last ?? "",
                                                         checkedOutTextures: counters.checkedOutTextures,
                                                         checkedOutBytes: counters.checkedOutBytes, liveScenes: 1))
            recorder.record(cycle: RenderSoakCycleSample(cycle: frames / cycleFrames - 1, memoryHighWaterBytes: highWater,
                                                         memoryEndBytes: memory, poolLiveBytes: counters.liveBytes,
                                                         poolMisses: counters.misses, frames: cycleFrames,
                                                         processFootprintBytes: Self.footprint()))
        }
        for _ in 0..<compositor.health.faultCount {
            recorder.record(error: RenderSoakError(frame: frames, scene: "projectM",
                                                   message: "render health fault: \(compositor.health.lastReason.map { "\($0)" } ?? "unknown")"))
        }
    }

    /// The process's physical footprint (reported only; the simulator's GPU reports no allocated size).
    private static func footprint() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { (p: UnsafeMutablePointer<task_vm_info_data_t>) -> kern_return_t in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { (q: UnsafeMutablePointer<integer_t>) -> kern_return_t in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), q, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : nil
    }

    private static var platform: String {
        #if targetEnvironment(simulator)
        return "iOS Simulator"
        #else
        return "iOS"
        #endif
    }

    private func write(_ report: RenderSoakReport) throws -> URL {
        let env = ProcessInfo.processInfo.environment
        let directory = env["QA006_REPORT_DIR"].flatMap { (s: String) -> URL? in s.isEmpty ? nil : URL(fileURLWithPath: s, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("qa006-render-soak", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent("\(report.name).json")
        try encoder.encode(report).write(to: url)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        add(attachment)
        return url
    }
}
