// RecordingQualityFixtureTests.swift — REC-005-T05, the row's acceptance ("Selected preset matches encoded
// metadata"): for each profile available on this machine, 2 s of moving detail (25% per-frame noise over a
// moving colour gradient) from a 1440×2880 drawable
// (injected frame times, offline writer) is recorded with the real writer and read back. Codec and size
// exact, frame rate ±1 fps, average video bit rate ±25% (REC-005-S1, research REC-005-D4). The detail makes
// the encoder spend its target; flat content would encode far below it. GPU test; skipped without
// Metal. Host results are not device evidence (REC-005-T14).
#if canImport(Metal) && canImport(AVFoundation) && canImport(VideoToolbox) && !COMPOSITOR_NO_METAL
import AVFoundation
@testable import FrameRecording
import Foundation
import Metal
import XCTest

final class RecordingQualityFixtureTests: XCTestCase {
    static let drawableWidth = 1440
    static let drawableHeight = 2880
    static let seconds = 2
    /// The noise's share over a moving colour gradient (research REC-005-D4: pure noise makes HEVC overshoot
    /// its target by up to 55% in 2 s; 25% noise is detailed enough to use the target and stays within ±7%).
    static let amplitude: Float = 0.25
    static let bitRateTolerance = 0.25

    /// Hash noise per pixel and frame mixed over a moving gradient (full-screen triangle; no vertex buffer).
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 p [[position]]; };
    vertex V noiseVertex(uint i [[vertex_id]]) {
        float2 c = float2((i << 1) & 2, i & 2);
        V v; v.p = float4(c * 2.0 - 1.0, 0.0, 1.0); return v;
    }
    fragment float4 noiseFragment(V in [[stage_in]], constant uint &frame [[buffer(0)]], constant float &amp [[buffer(1)]]) {
        uint2 q = uint2(in.p.xy);
        uint h = q.x * 374761393u + q.y * 668265263u + frame * 2246822519u;
        h = (h ^ (h >> 13)) * 1274126177u; h ^= h >> 16;
        float3 c = float3(h & 255u, (h >> 8) & 255u, (h >> 16) & 255u) / 255.0;
        float2 uv = in.p.xy / 1440.0;
        float3 g = 0.5 + 0.5 * cos(6.2832 * (uv.xyx + float3(0, 0.33, 0.67) + float(frame) / 60.0));
        return float4(mix(g, c, amp), 1.0);
    }
    """

    private struct Rig {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
    }

    private func rig() throws -> Rig {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device (CI simulator or Linux); RecordingQualityProfileTests cover the rules.")
        }
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "noiseVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "noiseFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        return Rig(device: device, queue: queue, pipeline: try device.makeRenderPipelineState(descriptor: descriptor))
    }

    /// Records the fixture with `profile` and returns the plan and the read-back.
    private func record(_ profile: RecordingQualityProfile) async throws -> (RecordingProfilePlan, RecordedVideoInfo) {
        let caps = VideoToolboxEncoderCapabilities(maxFramesPerSecond: 60)
        guard let plan = RecordingQualityCatalog.availability(of: profile, drawableWidth: Self.drawableWidth,
                                                              drawableHeight: Self.drawableHeight, capabilities: caps).plan else {
            throw XCTSkip("\(profile.title) is not available on this machine")
        }
        let r = try rig()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC-005-\(profile.rawValue)-\(UUID().uuidString).mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let recorder = try MetalFrameRecorder(device: r.device, url: url, drawableWidth: Self.drawableWidth,
                                              drawableHeight: Self.drawableHeight, settings: plan.settings, realTime: false)
        let fps: Int = plan.settings.maxFrameRate
        let frameNanoseconds: UInt64 = 1_000_000_000 / UInt64(fps)
        for k in 0..<(fps * Self.seconds) {
            let commands = try XCTUnwrap(r.queue.makeCommandBuffer())
            var frame = UInt32(k)
            let outcome = recorder.recordFrame(presentationNanoseconds: UInt64(k) * frameNanoseconds, drawableWidth: Self.drawableWidth,
                                               drawableHeight: Self.drawableHeight, commandBuffer: commands) { (texture: MTLTexture) -> Bool in
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = texture
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store
                guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
                encoder.setRenderPipelineState(r.pipeline)
                encoder.setFragmentBytes(&frame, length: MemoryLayout<UInt32>.size, index: 0)
                var amp = Self.amplitude
                encoder.setFragmentBytes(&amp, length: MemoryLayout<Float>.size, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
                return true
            }
            XCTAssertEqual(outcome, .submitted, "frame \(k)")
            commands.commit()
            if k % 3 == 2 { recorder.waitForPendingFrames() }   // the gate holds 3 frames
        }
        recorder.waitForPendingFrames()
        _ = try (await recorder.finish()).get()
        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        return (plan, info)
    }

    private func check(_ profile: RecordingQualityProfile, size: [Int], codec: String) async throws {
        let (plan, info) = try await record(profile)
        let target = Double(plan.averageBitRate)
        let measured = info.averageVideoBitRate
        // Logged for research REC-005-D4.
        print("REC-005 fixture \(profile.rawValue): \(info.summary) fps=\(String(format: "%.2f", info.nominalFrameRate)) "
              + "bitrate=\(Int(measured)) target=\(Int(target)) ratio=\(String(format: "%.3f", measured / target))")
        XCTAssertEqual(info.codec, codec)
        XCTAssertEqual([info.width, info.height], size)
        XCTAssertEqual([plan.geometry.outputWidth, plan.geometry.outputHeight], size)
        XCTAssertEqual(info.frameCount, plan.settings.maxFrameRate * Self.seconds)
        XCTAssertEqual(info.nominalFrameRate, Double(plan.settings.maxFrameRate), accuracy: 1)
        XCTAssertEqual(measured, target, accuracy: target * Self.bitRateTolerance, "average video bit rate")
        XCTAssertEqual(info.audioTrackCount, 0, "audio is REC-004's and unchanged")
    }

    func testDraftMatchesItsProfile() async throws {
        try await check(.draft, size: [640, 1280], codec: "avc1")
    }

    func testStandardMatchesItsProfile() async throws {
        try await check(.standard, size: [960, 1920], codec: "hvc1")
    }

    func testHighMatchesItsProfile() async throws {
        try await check(.high, size: [1280, 2560], codec: "hvc1")
    }

    func testMaxMatchesItsProfile() async throws {
        try await check(.max, size: [1440, 2880], codec: "hvc1")
    }
}
#endif
