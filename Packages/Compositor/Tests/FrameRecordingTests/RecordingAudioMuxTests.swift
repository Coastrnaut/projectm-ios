// RecordingAudioMuxTests.swift — REC-004-T08, T09, T12: the acceptance fixture (owned audio aligned with
// the picture within 20 ms), microphone consent, System/App Capture and a source switch, written with
// the real AVAssetWriter and read back with AVAssetReader. Every time is injected (no wall clock).
// GPU tests: skipped without a Metal device (CI simulators); the policy and timeline tests cover the rules.
#if canImport(Metal) && canImport(AVFoundation) && !COMPOSITOR_NO_METAL
import AVFoundation
import CoreVideo
@testable import FrameRecording
import Foundation
import Metal
import XCTest

final class RecordingAudioMuxTests: XCTestCase {
    /// The host-clock time of the first frame (any value: only differences matter).
    private let base: UInt64 = 5_000_000_000
    private static let chunkFrames = 441   // 10 ms

    private struct Fixture {
        var audio: Bool
        var seconds: Double = 2.0
        var flashAt: Double? = 1.0
        /// The click (2 ms at 0.9); nil for a steady tone of 0.5 (the "microphone" content).
        var clickAt: Double? = 1.0
        var offerAudio = true
        /// `endAudio()` before the first chunk at or after this time (a source switch).
        var switchAt: Double?
        /// Audio offered from this time (negative: before the first frame).
        var audioFrom: Double = 0
    }

    private struct ReadBack {
        var info: RecordedVideoInfo
        var flashTime: Double?
        var clickTime: Double?
        var lastAudioTime: Double?
        var audioPeak: Float
    }

    private func gpu() throws -> (MTLDevice, MTLCommandQueue) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device (CI simulator or Linux); the rule tests cover the contract.")
        }
        return (device, queue)
    }

    // MARK: - Writing

    private func record(_ fixture: Fixture) async throws -> ReadBack {
        let (device, queue) = try gpu()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("REC-004-\(UUID().uuidString).mp4")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let recorder = try MetalFrameRecorder(device: device, url: url, drawableWidth: 160, drawableHeight: 120,
                                              settings: RecordingSettings(maxFrameRate: 30), realTime: true, audio: fixture.audio)
        let frameCount = Int(fixture.seconds * 30)
        var chunk = Int((fixture.audioFrom * 100).rounded())   // 10 ms chunks
        for frame in 0..<frameCount {
            let frameTime = Double(frame) / 30
            let level: Double = fixture.flashAt.map { (t: Double) -> Double in abs(frameTime - t) < 1.0 / 60 ? 1 : 0 } ?? 0
            try offerFrame(recorder, queue: queue, ns: base + UInt64(frame) * 1_000_000_000 / 30, level: level)
            // Audio up to the next frame's time, in time order with the frames.
            while fixture.offerAudio, Double(chunk) / 100 < Double(frame + 1) / 30 {
                let start = Double(chunk) / 100
                if let switchAt = fixture.switchAt, start >= switchAt { recorder.endAudio() }
                offerAudio(recorder, chunk: chunk, fixture: fixture)
                chunk += 1
            }
            // The live writer (never waits, like the app); pacing (not an assertion) lets the encoder keep up.
            recorder.waitForPendingFrames()
            try await Task.sleep(for: .milliseconds(4))
        }
        recorder.waitForPendingFrames()
        let finished = await recorder.finish()
        guard case .success(let video) = finished else { return try XCTUnwrap(nil, "the recording finished: \(finished)") }
        return try await readBack(video.url)
    }

    private func offerFrame(_ recorder: MetalFrameRecorder, queue: MTLCommandQueue, ns: UInt64, level: Double) throws {
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        _ = recorder.recordFrame(presentationNanoseconds: ns, drawableWidth: 160, drawableHeight: 120,
                                 commandBuffer: commands) { (texture: MTLTexture) -> Bool in
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: level, green: level, blue: level, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
            return true
        }
        commands.commit()
        commands.waitUntilCompleted()
    }

    /// One 10 ms chunk; its first sample is at `chunk × 10 ms` after the first frame (host clock).
    private func offerAudio(_ recorder: MetalFrameRecorder, chunk: Int, fixture: Fixture) {
        let frames = Self.chunkFrames
        var samples = [Float](repeating: fixture.clickAt == nil ? 0.5 : 0, count: frames * 2)
        if let click = fixture.clickAt {
            let clickSample = Int((click * 44_100).rounded())
            for i in 0..<frames {
                let position = chunk * frames + i
                if position >= clickSample, position < clickSample + 88 {   // 2 ms
                    samples[2 * i] = 0.9
                    samples[2 * i + 1] = 0.9
                }
            }
        }
        let offset = Int64(chunk) * 10_000_000
        let ns = UInt64(Int64(base) + offset)
        samples.withUnsafeBufferPointer { (p: UnsafeBufferPointer<Float>) -> Void in
            recorder.appendAudio(p.baseAddress!, frames: frames, firstSampleNanoseconds: ns)
        }
    }

    // MARK: - Reading back

    private func readBack(_ url: URL) async throws -> ReadBack {
        let inspected = await RecordedVideoInspector.inspect(url)
        let info = try XCTUnwrap(inspected)
        let asset = AVURLAsset(url: url)
        var result = ReadBack(info: info, flashTime: nil, clickTime: nil, lastAudioTime: nil, audioPeak: 0)
        result.flashTime = try await flashTime(asset)
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            try readAudio(asset, track: audio, into: &result)
        }
        return result
    }

    private func flashTime(_ asset: AVURLAsset) async throws -> Double? {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
            let row = CVPixelBufferGetBytesPerRow(pixels)
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
            let center = bytes[(CVPixelBufferGetHeight(pixels) / 2) * row + (CVPixelBufferGetWidth(pixels) / 2) * 4 + 1]
            if center > 128 { return CMSampleBufferGetPresentationTimeStamp(sample).seconds }
        }
        return nil
    }

    private func readAudio(_ asset: AVURLAsset, track: AVAssetTrack, into result: inout ReadBack) throws {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                                       AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
                                       AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        while let sample = output.copyNextSampleBuffer() {
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var floats = [Float](repeating: 0, count: frames * 2)
            let bytes = min(CMBlockBufferGetDataLength(block), floats.count * 4)
            _ = floats.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> OSStatus in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: raw.baseAddress!)
            }
            for i in 0..<frames {
                let value = abs(floats[2 * i])
                result.audioPeak = max(result.audioPeak, value)
                if result.clickTime == nil, value > 0.3 { result.clickTime = start + Double(i) / 44_100 }
                if value > 0.05 { result.lastAudioTime = start + Double(i) / 44_100 }
            }
        }
    }

    // MARK: - REC-004-S1: the acceptance fixture

    func testOwnedAudioClickAlignsWithFlash() async throws {
        let back = try await record(Fixture(audio: true))
        XCTAssertEqual(back.info.audioTrackCount, 1)
        XCTAssertEqual(back.info.audioCodec, "aac ")
        XCTAssertEqual(back.info.audioSampleRate, 44_100)
        XCTAssertEqual(back.info.audioChannelCount, 2)
        XCTAssertEqual(back.info.metadataCount, 0)
        let flash = try XCTUnwrap(back.flashTime)
        let click = try XCTUnwrap(back.clickTime)
        XCTAssertEqual(flash, 1.0, accuracy: 0.001, "the flash frame is at 1.0 s")
        XCTAssertEqual(click, flash, accuracy: RecordingAudioTimeline.toleranceSeconds, "click \(click) s, flash \(flash) s")
    }

    func testAudioBeforeTheFirstFrameIsLeftOut() async throws {
        // Audio from −0.5 s with the click at −0.2 s: the click is before the file starts.
        let back = try await record(Fixture(audio: true, flashAt: nil, clickAt: -0.2, audioFrom: -0.5))
        XCTAssertEqual(back.info.audioTrackCount, 1)
        XCTAssertNil(back.clickTime, "nothing before the first frame is in the file")
    }

    // MARK: - REC-004-S2: microphone consent

    private func microphoneRecording(includeMicrophone: Bool, granted: Bool) async throws -> ReadBack {
        let decision = RecordingAudioPolicy.decide(source: .microphone, includeMicrophone: includeMicrophone, microphoneGranted: granted)
        // The microphone's samples are offered in every case; only the decision decides.
        return try await record(Fixture(audio: decision.includesAudio, seconds: 1.0, flashAt: nil, clickAt: nil))
    }

    func testMicrophoneWithoutConsentLeavesNoAudio() async throws {
        let settingOff = try await microphoneRecording(includeMicrophone: false, granted: true)
        XCTAssertEqual(settingOff.info.audioTrackCount, 0)
        let denied = try await microphoneRecording(includeMicrophone: true, granted: false)
        XCTAssertEqual(denied.info.audioTrackCount, 0)
    }

    func testMicrophoneWithConsentIsRecorded() async throws {
        let back = try await microphoneRecording(includeMicrophone: true, granted: true)
        XCTAssertEqual(back.info.audioTrackCount, 1)
        XCTAssertGreaterThan(back.audioPeak, 0.3, "the offered microphone samples are in the file")
    }

    // MARK: - REC-004-S3, S4: other apps' audio and a switch

    func testSystemCaptureNeverHasAnAudioTrack() async throws {
        let decision = RecordingAudioPolicy.decide(source: .systemCapture, includeMicrophone: true, microphoneGranted: true)
        let back = try await record(Fixture(audio: decision.includesAudio, seconds: 1.0, flashAt: nil, clickAt: nil))
        XCTAssertEqual(back.info.audioTrackCount, 0)
    }

    func testASwitchEndsTheAudioAndTheVideoGoesOn() async throws {
        let back = try await record(Fixture(audio: true, seconds: 2.0, flashAt: nil, clickAt: nil, switchAt: 1.0))
        let last = try XCTUnwrap(back.lastAudioTime)
        XCTAssertEqual(last, 1.0, accuracy: RecordingAudioTimeline.toleranceSeconds, "the audio ends at the switch")
        XCTAssertEqual(back.info.durationSeconds, 2.0, accuracy: 0.05, "the video goes on")
    }

    func testIncludeWithNoAudioOfferedWritesNoAudioTrack() async throws {   // contract C3
        let back = try await record(Fixture(audio: true, seconds: 1.0, flashAt: nil, offerAudio: false))
        XCTAssertEqual(back.info.audioTrackCount, 0, "no silent or empty track pretends there was audio")
    }
}
#endif
