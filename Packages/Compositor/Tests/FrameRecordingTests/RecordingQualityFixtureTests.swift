// RecordingQualityFixtureTests.swift — REC-005-T05, the row's acceptance ("Selected preset matches encoded
// metadata"): for each profile available on this machine, 2 s of moving detail (quarter-range noise over a
// per-frame base colour, eight distinct frames cycled) from a 1440×2880 drawable
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
    /// Research REC-005-D4: pure noise makes HEVC overshoot its target by up to 55% in 2 s; quarter-range
    /// noise is detailed enough to use the target and stays close to it.
    static let bitRateTolerance = 0.25
    /// Distinct frames, cycled (more than an encoder's reference frames, so no frame repeats a reference).
    static let distinctFrames = 8

    /// The frames, made once per test process on the CPU (no shader is compiled: SHD-011 allows runtime
    /// Metal source only in reviewed module files) and copied into each pixel buffer with a GPU blit: random
    /// bytes masked to a quarter of the range (0-63 per channel) over a per-frame base colour.
    nonisolated(unsafe) private static let frames: [MTLBuffer]? = {   // written once (lazy static), then only read
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let length = drawableWidth * drawableHeight * 4
        return (0..<distinctFrames).compactMap { (k: Int) -> MTLBuffer? in
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else { return nil }
            arc4random_buf(buffer.contents(), length)
            let base = UInt32(k * 16) | UInt32(96 - k * 8) << 8 | UInt32(64 + k * 12) << 16 | 0xFF00_0000
            let base64 = UInt64(base) | UInt64(base) << 32
            let words = buffer.contents().bindMemory(to: UInt64.self, capacity: length / 8)
            for i in 0..<(length / 8) {   // BGRA in memory; no carry: 63 + 180 < 256
                words[i] = (words[i] & 0x003F_3F3F_003F_3F3F) &+ base64
            }
            return buffer
        }
    }()

    private struct Rig {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let frames: [MTLBuffer]
    }

    private func rig() throws -> Rig {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let frames = Self.frames, frames.count == Self.distinctFrames else {
            throw XCTSkip("No Metal device (CI simulator or Linux); RecordingQualityProfileTests cover the rules.")
        }
        return Rig(device: device, queue: queue, frames: frames)
    }

    /// Records the fixture with `profile` and returns the plan, the recorder's result and the read-back.
    private func record(_ profile: RecordingQualityProfile) async throws -> (RecordingProfilePlan, RecordedVideo, RecordedVideoInfo) {
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
            let source: MTLBuffer = r.frames[k % Self.distinctFrames]
            let outcome = recorder.recordFrame(presentationNanoseconds: UInt64(k) * frameNanoseconds, drawableWidth: Self.drawableWidth,
                                               drawableHeight: Self.drawableHeight, commandBuffer: commands) { (texture: MTLTexture) -> Bool in
                guard let blit = commands.makeBlitCommandEncoder() else { return false }
                blit.copy(from: source, sourceOffset: 0, sourceBytesPerRow: Self.drawableWidth * 4,
                          sourceBytesPerImage: Self.drawableWidth * Self.drawableHeight * 4,
                          sourceSize: MTLSize(width: Self.drawableWidth, height: Self.drawableHeight, depth: 1),
                          to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
                return true
            }
            XCTAssertEqual(outcome, .submitted, "frame \(k)")
            commands.commit()
            if k % 3 == 2 { recorder.waitForPendingFrames() }   // the gate holds 3 frames
        }
        recorder.waitForPendingFrames()
        let video = try (await recorder.finish()).get()
        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        return (plan, video, info)
    }

    private func check(_ profile: RecordingQualityProfile, size: [Int], codec: String) async throws {
        var (plan, video, info) = try await record(profile)
        let target = Double(plan.averageBitRate)
        if abs(info.averageVideoBitRate - target) > target * Self.bitRateTolerance {
            // The host's hardware encoder is shared with other processes; under contention its rate control can
            // overshoot one short clip. One re-record, both values logged (research REC-005-D4).
            print("REC-005 fixture \(profile.rawValue): first take \(Int(info.averageVideoBitRate)) b/s; recording again")
            (plan, video, info) = try await record(profile)
        }
        let measured = info.averageVideoBitRate
        let stats = video.statistics
        let slots: Int = plan.settings.maxFrameRate * Self.seconds
        // Logged for research REC-005-D4 (and the drop counts, for a slow encoder).
        print("REC-005 fixture \(profile.rawValue): \(info.summary) fps=\(String(format: "%.2f", info.nominalFrameRate)) "
              + "bitrate=\(Int(measured)) target=\(Int(target)) ratio=\(String(format: "%.3f", measured / target)) "
              + "written=\(stats.written) notReady=\(stats.droppedNotReady) busy=\(stats.droppedBusy) slots=\(stats.droppedSlots)")
        XCTAssertEqual(info.codec, codec)
        XCTAssertEqual([info.width, info.height], size)
        XCTAssertEqual([plan.geometry.outputWidth, plan.geometry.outputHeight], size)
        // Every offered frame is in the file, and the recorder's counts say why when one is not (REC-003-R7,
        // REC-006-R4). Run 43612171768 lost one of 120 on CI's iOS 27 simulator, where this test took 432 s (53 s on
        // the Mac Studio's simulator, which writes all 120): a frame the slow encoder had not taken within the offline
        // writer's former 5 s hang guard (`VideoFileWriter.offlineReadyTimeoutSeconds`) is dropped and counted.
        XCTAssertEqual(info.frameCount, stats.written, "the file holds exactly the frames the recorder appended")
        XCTAssertEqual(video.frameCount, stats.written)
        XCTAssertEqual(stats.written + stats.dropped, slots, "frames + dropped = offered slots")
        XCTAssertEqual(stats.dropped, 0, "offline, no frame is dropped: notReady \(stats.droppedNotReady), busy \(stats.droppedBusy)")
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
