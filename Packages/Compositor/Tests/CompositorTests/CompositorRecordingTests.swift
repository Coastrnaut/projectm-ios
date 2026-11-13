// CompositorRecordingTests.swift — REC-003-T11, T12: the row's acceptance ("Ten-second fixture decodes
// and preserves monotonic timestamps") through the real Metal compositor, and `encodeOutput`.
//
// The fixture: a compositor whose one layer draws frame k's index as nine bars at 160 × 120, each
// half white and half black (left half white for a 1 bit, right half for a 0 bit), so every frame has
// the same brightness and the composite flash guard (FX-019) never dims it, driven by a simulated 30 fps frame clock (k × 10⁹ / 30 ns; no real time), recorded with
// the offline writer (it waits for the encoder on its own queue, so no frame is dropped), then read
// back with AVFoundation. Skipped without a Metal device.
#if canImport(Metal) && canImport(AVFoundation) && !COMPOSITOR_NO_METAL
import AVFoundation
import Compositor
import CoreVideo
import FrameRecording
import Metal
import XCTest

/// Draws `index` as `bits` vertical bars on black: bar b's left half is white for a 1 bit, its right
/// half for a 0 bit (constant brightness per frame).
private final class IndexBarsLayer: LayerSource {
    let layerName = "index bars"
    let fallback = LayerFallback.transparent
    static let bits = 9
    static let barWidth = 16
    var index = 0
    private var white: MTLBuffer?
    private var height = 0

    func prepare(picture: LayerPictureDescriptor, device: MTLDevice) throws(LayerSourceError) {
        height = picture.height
        // One white half bar of half floats (1.0 = 0x3C00), copied into each bar's left or right half.
        let halves = [UInt16](repeating: 0x3C00, count: Self.barWidth / 2 * picture.height * 4)
        white = halves.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> MTLBuffer? in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }
        if white == nil { throw .resourceUnavailable("bar buffer") }
    }

    func render(into picture: MTLTexture, commandBuffer: MTLCommandBuffer, frame: LayerFrameContext,
                audio: LayerAudioContext) throws(LayerSourceError) {
        SolidLayer.clear(picture, to: Pixel(0, 0, 0, 1), commandBuffer: commandBuffer)
        guard let white, let blit = commandBuffer.makeBlitCommandEncoder() else { throw .frameSkipped }
        let half = Self.barWidth / 2, rowBytes = half * 8
        for bit in 0..<Self.bits {
            let x = bit * Self.barWidth + (index & (1 << bit) != 0 ? 0 : half)
            blit.copy(from: white, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: rowBytes * height,
                      sourceSize: MTLSize(width: half, height: height, depth: 1), to: picture, destinationSlice: 0,
                      destinationLevel: 0, destinationOrigin: MTLOrigin(x: x, y: 0, z: 0))
        }
        blit.endEncoding()
    }
}

final class CompositorRecordingTests: XCTestCase {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("REC-003-\(name)-\(UUID().uuidString).mp4")
    }

    /// REC-003-S1: 10 s at 30 fps from a compositor source decodes with 300 frames, strictly increasing
    /// times equal to the written ones (20 × k at 1/600 s), duration 10 s, indices 0...299 in order,
    /// one video track, no audio track, no metadata.
    func testTenSecondFixtureDecodesWithMonotonicTimestamps() async throws {
        let url = temporaryURL("fixture")
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = 300
        let recorder = try recordFixture(frames: frames, url: url)
        let video = try (await recorder.finish()).get()
        print("REC-003 fixture codec: \(video.codec.title)")
        XCTAssertEqual(video.frameCount, frames)
        XCTAssertEqual(video.durationSeconds, 10, accuracy: 1e-9)
        XCTAssertEqual(video.statistics.dropped, 0)

        let info = try await XCTUnwrapAsync(await RecordedVideoInspector.inspect(url))
        XCTAssertEqual(info.frameCount, frames, accuracy: 1)
        XCTAssertTrue(info.timesStrictlyIncrease)
        XCTAssertEqual(info.presentationTicks, (0..<frames).map { (k: Int) -> Int64 in Int64(k) * 20 }, "the written times")
        XCTAssertEqual(info.durationSeconds, 10, accuracy: 1.0 / 30)
        XCTAssertEqual([info.width, info.height], [160, 120])
        XCTAssertEqual(info.videoTrackCount, 1)
        XCTAssertEqual(info.audioTrackCount, 0, "REC-003-R8: video only")
        XCTAssertEqual(info.metadataCount, 0, "REC-003-R8: no metadata items")
        XCTAssertEqual(info.codec, video.codec.fourCharacterCode)

        let indices = try decodedIndices(url)
        XCTAssertEqual(indices.count, frames)
        XCTAssertEqual(indices, Array(0..<frames), "decoded indices increase from 0 in order")
    }

    /// Records `frames` frames of the index-bar layer through a compositor (synchronous: each frame is
    /// committed, completed and appended before the next).
    private func recordFixture(frames: Int, url: URL) throws -> MetalFrameRecorder {
        let rig = try GPURig()
        let layer = IndexBarsLayer()
        let compositor = try Compositor(device: rig.device, layers: [layer])
        let output = try rig.output(.bgra8Unorm_srgb, width: 160, height: 120)
        let recorder = try MetalFrameRecorder(device: rig.device, url: url, drawableWidth: 160, drawableHeight: 120,
                                              realTime: false)
        for k in 0..<frames {
            layer.index = k
            let time = UInt64(k) * 1_000_000_000 / 30
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            XCTAssertTrue(compositor.composite(into: output, commandBuffer: commands, presentationTimeNanoseconds: time,
                                               contentScale: 2, reduceFlashing: false, audio: .empty))
            let outcome = recorder.recordFrame(presentationNanoseconds: time, drawableWidth: 160, drawableHeight: 120,
                                               commandBuffer: commands) { (texture: MTLTexture) -> Bool in
                compositor.encodeOutput(into: texture, commandBuffer: commands)
            }
            XCTAssertEqual(outcome, .submitted, "frame \(k)")
            commands.commit()
            commands.waitUntilCompleted()
            recorder.waitForPendingFrames()
        }
        return recorder
    }

    /// Decodes every frame to BGRA and compares each bar's half centers on the middle row.
    private func decodedIndices(_ url: URL) throws -> [Int] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var indices: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(image, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
            let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(image)).assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(image)
            let y = CVPixelBufferGetHeight(image) / 2
            var index = 0
            for bit in 0..<IndexBarsLayer.bits {
                let left = bit * IndexBarsLayer.barWidth + IndexBarsLayer.barWidth / 4
                let right = left + IndexBarsLayer.barWidth / 2
                if base[y * rowBytes + left * 4 + 1] > base[y * rowBytes + right * 4 + 1] { index |= 1 << bit }
            }
            indices.append(index)
        }
        return indices
    }

    /// REC-003-T12: `encodeOutput` needs a composite in the same command buffer; the copy equals the
    /// shown output (cropped from the top left) and the shown output is unchanged.
    func testEncodeOutputCopiesTheShownFrame() throws {
        let rig = try GPURig()
        let halfRed = Pixel(0.5, 0, 0, 0.5)
        let compositor = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: Pixel(0, 0, 1, 1)), SolidLayer("red", color: halfRed)])
        let plain = try Compositor(device: rig.device, layers: [SolidLayer("blue", color: Pixel(0, 0, 1, 1)), SolidLayer("red", color: halfRed)])
        let shown = try rig.output(.rgba16Float, width: 65, height: 49)
        let reference = try rig.output(.rgba16Float, width: 65, height: 49)
        let copy = try rig.output(.rgba16Float, width: 64, height: 48)
        let tooBig = try rig.output(.rgba16Float, width: 66, height: 49)

        let early = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertFalse(compositor.encodeOutput(into: copy, commandBuffer: early), "no frame composited yet")
        early.commit()

        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(compositor.composite(into: shown, commandBuffer: commands, presentationTimeNanoseconds: 1, contentScale: 2,
                                           reduceFlashing: false, audio: .empty))
        XCTAssertFalse(compositor.encodeOutput(into: tooBig, commandBuffer: commands), "larger than the output")
        XCTAssertTrue(compositor.encodeOutput(into: copy, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        try rig.frame(plain, into: reference, time: 1)
        XCTAssertEqual(try rig.read(shown), try rig.read(reference), "the shown frame is unchanged")

        let copied = try rig.read(copy), full = try rig.read(shown)
        for y in 0..<48 {
            for x in 0..<64 where copied[y * 64 + x] != full[y * 65 + x] {
                return XCTFail("pixel \(x),\(y) differs")
            }
        }
        assertAll(copied, equal: Pixel(0.5, 0, 0.5, 1), tolerance: 1e-3, "half red over blue")

        let other = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertFalse(compositor.encodeOutput(into: copy, commandBuffer: other), "another command buffer")
        other.commit()
    }
}

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
#endif
