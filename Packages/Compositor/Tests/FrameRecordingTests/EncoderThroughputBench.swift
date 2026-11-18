// EncoderThroughputBench.swift — QA-011 REC-003-T23 follow-up (2026-11-18): on the A16 devices a 60 s, 60 fps
// Max-profile recording dropped 15 % (D1) and 71 % (D3) of its slots, almost all as "encoder not ready". This bench
// feeds a real-time AVAssetWriter at 60 fps for 10 s per input format, at the device's native screen size, HEVC at
// the Max profile's 40 Mbit/s, and counts the slots the input refused. It compares 32BGRA input (what the recorder
// feeds today: the encoder converts each picture to 4:2:0) with 4:2:0 bi-planar input (no conversion).
// Runs only with REC003_ENCODER_BENCH=1 (an on-demand measurement; nothing is asserted about the drop share).
#if canImport(AVFoundation) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
import Foundation
@testable import FrameRecording
#if canImport(Metal)
import Metal
#endif
import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class EncoderThroughputBench: XCTestCase {
    private struct Result { let format: String; let codec: String; let offered: Int; let refused: Int; let seconds: Double }

    private static func size() -> (width: Int, height: Int) {
        #if canImport(UIKit) && os(iOS)
        let native = UIScreen.main.nativeBounds
        let w = Int(min(native.width, native.height)) & ~1, h = Int(max(native.width, native.height)) & ~1
        return (w, h)
        #else
        return (1640, 2360)
        #endif
    }

    /// Fills `buffer` with a gradient plus per-buffer variation (moderately compressible, like a visual).
    private static func fill(_ buffer: CVPixelBuffer, seed: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let planes = max(CVPixelBufferGetPlaneCount(buffer), 1)
        for plane in 0..<planes {
            let planar = CVPixelBufferIsPlanar(buffer)
            guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, plane) : CVPixelBufferGetBaseAddress(buffer)
            else { continue }
            let rows = planar ? CVPixelBufferGetHeightOfPlane(buffer, plane) : CVPixelBufferGetHeight(buffer)
            let stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) : CVPixelBufferGetBytesPerRow(buffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var state = UInt32(truncatingIfNeeded: seed &* 2_654_435_761 &+ plane)
            for y in 0..<rows {
                let row = bytes + y * stride
                for x in 0..<stride {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    row[x] = UInt8(truncatingIfNeeded: (x + y + seed * 7) / 4) &+ UInt8(truncatingIfNeeded: state >> 28)
                }
            }
        }
    }

    private func run(format: OSType, name: String, codec: AVVideoCodecType, width: Int, height: Int) throws -> Result {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("encoder-bench-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 40_000_000, AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoExpectedSourceFrameRateKey: 60, AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), "\(name): \(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)
        var buffers: [CVPixelBuffer] = []
        for seed in 0..<8 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes as CFDictionary, &buffer)
            let made = try XCTUnwrap(buffer)
            Self.fill(made, seed: seed)
            buffers.append(made)
        }
        let frames = 600, interval = 1.0 / 60
        var refused = 0
        let start = Date()
        for i in 0..<frames {
            let due = start.addingTimeInterval(Double(i) * interval)
            let wait = due.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            if input.isReadyForMoreMediaData {
                if !adaptor.append(buffers[i % buffers.count], withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 60)) {
                    XCTFail("\(name): append failed: \(String(describing: writer.error))")
                    break
                }
            } else {
                refused += 1
            }
        }
        let seconds = Date().timeIntervalSince(start)
        input.markAsFinished()
        let done = expectation(description: "finish")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 30)
        return Result(format: name, codec: codec == .hevc ? "hevc" : "h264", offered: frames, refused: refused, seconds: seconds)
    }

    func testEncoderThroughputByInputFormat() throws {
        guard ProcessInfo.processInfo.environment["REC003_ENCODER_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set REC003_ENCODER_BENCH=1")
        }
        let (width, height) = Self.size()
        let cases: [(OSType, String, AVVideoCodecType)] = [
            (kCVPixelFormatType_32BGRA, "32BGRA", .hevc),
            (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, "420v", .hevc),
            (kCVPixelFormatType_32BGRA, "32BGRA", .h264),
            (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, "420v", .h264),
        ]
        for (format, name, codec) in cases {
            let r = try run(format: format, name: name, codec: codec, width: width, height: height)
            print("REC003_ENCODER_BENCH \(width)x\(height) \(r.codec) \(r.format): refused \(r.refused) of \(r.offered) "
                  + "(\(String(format: "%.1f", 100 * Double(r.refused) / Double(r.offered))) %) in \(String(format: "%.1f", r.seconds)) s")
        }
    }
    /// The app's own writer (`VideoFileWriter`, Max profile at 60 fps, real time), fed like `MetalFrameRecorder`
    /// feeds it: a pool buffer per frame (contents copied from a filled picture), appends on the writer's queue, and,
    /// with `audio`, 735 stereo frames of AAC input per video frame (44.1 kHz / 60). Counts refused video frames.
    private func runAppWriter(audio: Bool, audioLagFrames: Int = 0, width: Int, height: Int) async throws -> (refused: Int, audioRefused: Int) {
        let settings = RecordingQualityProfile.max.settings(frameRate: 60)
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: width, drawableHeight: height, settings: settings))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("app-writer-bench-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try VideoFileWriter.make(url: url, geometry: geometry, settings: settings, realTime: true, audio: audio)
        var source: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            RecordingPixelBuffers.attributes(width: width, height: height) as CFDictionary, &source)
        let picture = try XCTUnwrap(source)
        Self.fill(picture, seed: 1)
        let samples = (0..<(735 * 2)).map { (i: Int) -> Float in Float(sin(Double(i) * 0.05)) * 0.2 }
        final class Counts: @unchecked Sendable { let lock = NSLock(); var refused = 0, audio = 0 }
        let counts = Counts()
        let interval = 1.0 / 60, start = Date()
        for i in 0..<600 {
            let wait = start.addingTimeInterval(Double(i) * interval).timeIntervalSinceNow
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            guard let buffer = writer.makePixelBuffer() else { counts.lock.withLock { counts.refused += 1 }; continue }
            CVPixelBufferLockBaseAddress(picture, .readOnly); CVPixelBufferLockBaseAddress(buffer, [])
            if let from = CVPixelBufferGetBaseAddress(picture), let to = CVPixelBufferGetBaseAddress(buffer) {
                memcpy(to, from, min(CVPixelBufferGetDataSize(picture), CVPixelBufferGetDataSize(buffer)))
            }
            CVPixelBufferUnlockBaseAddress(buffer, []); CVPixelBufferUnlockBaseAddress(picture, .readOnly)
            nonisolated(unsafe) let pixels = buffer
            let tick = Int64(i) * settings.frameIntervalTicks
            writer.queue.async {
                if writer.append(pixels, tick: tick) != .appended { counts.lock.withLock { counts.refused += 1 } }
                // With a lag, the chunk for video frame i is frame i - lag's audio (it arrives `lag` frames late).
                if audio, i >= audioLagFrames,
                   writer.appendAudio(samples, startSample: Int64(i - audioLagFrames) * 735) != .appended {
                    counts.lock.withLock { counts.audio += 1 }
                }
            }
        }
        writer.queue.sync {}
        _ = await writer.finish(endTick: 600 * settings.frameIntervalTicks, keep: false)
        return counts.lock.withLock { (counts.refused, counts.audio) }
    }

    func testAppWriterWithAndWithoutAudio() async throws {
        guard ProcessInfo.processInfo.environment["REC003_ENCODER_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set REC003_ENCODER_BENCH=1")
        }
        let (width, height) = Self.size()
        for (audio, lag) in [(false, 0), (true, 0), (true, 15), (true, 30), (true, 60)] {
            let r = try await runAppWriter(audio: audio, audioLagFrames: lag, width: width, height: height)
            print("REC003_APP_WRITER_BENCH \(width)x\(height) max 60 fps audio=\(audio) audioLag=\(lag) frames: refused \(r.refused) "
                  + "of 600 video frames, \(r.audioRefused) audio chunks refused")
        }
    }
    #if canImport(Metal)
    /// Like `runAppWriter`, but the GPU writes each frame into the pool buffer (a blit into its Metal texture from the
    /// CVMetalTextureCache, as `MetalFrameRecorder` does) and appends on completion; with `load`, a second queue keeps
    /// the GPU busy with full-size blits meanwhile (the visual's render).
    private func runGPUFedWriter(load: Bool, renderPass: Bool = false, width: Int, height: Int) async throws -> Int {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue()), loadQueue = try XCTUnwrap(device.makeCommandQueue())
        var cacheOut: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cacheOut)
        let cache = try XCTUnwrap(cacheOut)
        let settings = RecordingQualityProfile.max.settings(frameRate: 60)
        let geometry = try XCTUnwrap(RecordingGeometry(drawableWidth: width, drawableHeight: height, settings: settings))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gpu-writer-bench-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try VideoFileWriter.make(url: url, geometry: geometry, settings: settings, realTime: true, audio: true)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        let source = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: (i / 4) % width / 6 + (i % 4) * 40) }
        source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        let scratch = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        final class Counts: @unchecked Sendable { let lock = NSLock(); var refused = 0; var running = true }
        let counts = Counts()
        let samples = (0..<(735 * 2)).map { (i: Int) -> Float in Float(sin(Double(i) * 0.05)) * 0.2 }
        nonisolated(unsafe) let loadSource = source, loadTarget = scratch
        let loader = Thread {
            while counts.lock.withLock({ counts.running }) {
                guard let commands = loadQueue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else { break }
                for _ in 0..<4 { blit.copy(from: loadSource, to: loadTarget) }
                blit.endEncoding()
                commands.commit()
                commands.waitUntilCompleted()
            }
        }
        if load { loader.start() }
        let interval = 1.0 / 60, start = Date()
        for i in 0..<600 {
            let wait = start.addingTimeInterval(Double(i) * interval).timeIntervalSinceNow
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            guard let buffer = writer.makePixelBuffer() else { counts.lock.withLock { counts.refused += 1 }; continue }
            var textureOut: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, [
                kCVMetalTextureUsage as String: MTLTextureUsage([.renderTarget, .shaderRead, .shaderWrite]).rawValue,
            ] as CFDictionary, .bgra8Unorm_srgb, width, height, 0, &textureOut)
            guard let made = textureOut, let target = CVMetalTextureGetTexture(made),
                  let commands = queue.makeCommandBuffer() else { continue }
            if renderPass {
                // Like the app's "REC-003 recording output" pass: the frame is drawn into the buffer's texture.
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(i % 60) / 60, green: 0.3, blue: 0.6, alpha: 1)
                guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { continue }
                encoder.endEncoding()
            } else {
                guard let blit = commands.makeBlitCommandEncoder() else { continue }
                blit.copy(from: source, to: target)
                blit.endEncoding()
            }
            nonisolated(unsafe) let pixels = buffer, keep = made
            let tick = Int64(i) * settings.frameIntervalTicks
            commands.addCompletedHandler { _ in
                writer.queue.async {
                    _ = keep
                    if writer.append(pixels, tick: tick) != .appended { counts.lock.withLock { counts.refused += 1 } }
                    _ = writer.appendAudio(samples, startSample: Int64(i) * 735)
                }
            }
            commands.commit()
        }
        queue.makeCommandBuffer().map { (c: MTLCommandBuffer) -> Void in c.commit(); c.waitUntilCompleted() }
        counts.lock.withLock { counts.running = false }
        writer.queue.sync {}
        _ = await writer.finish(endTick: 600 * settings.frameIntervalTicks, keep: false)
        return counts.lock.withLock { counts.refused }
    }

    func testGPUFedWriterWithAndWithoutLoad() async throws {
        guard ProcessInfo.processInfo.environment["REC003_ENCODER_BENCH"] == "1" else {
            throw XCTSkip("on-demand bench: set REC003_ENCODER_BENCH=1")
        }
        let (width, height) = Self.size()
        for (load, pass) in [(false, false), (true, false), (false, true), (true, true)] {
            let refused = try await runGPUFedWriter(load: load, renderPass: pass, width: width, height: height)
            print("REC003_GPU_WRITER_BENCH \(width)x\(height) max 60 fps gpuLoad=\(load) renderPass=\(pass): refused \(refused) of 600 video frames")
        }
    }
    #endif
}
#endif
