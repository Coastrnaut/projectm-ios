// MED-002-T13, T14: the video layer through the real Metal compositor at 64 × 64 with injected
// presentation times (a fake clock; MED-002-R9 to R13, S1 to S3, S7). Fixtures are generated; skipped
// without a Metal device. Waits are ceilings for the decode thread, never timing assertions.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(AVFoundation)
import AVFoundation
import Compositor
import Metal
import VideoLayer
import XCTest

final class VideoLayerTests: XCTestCase {
    private var directory: URL!
    private let base: UInt64 = 50_000_000_000

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED002-layer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture(_ name: String, _ options: VideoFixtures.Options = .init()) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        try await VideoFixtures.write(to: url, options)
        return url
    }

    private func srgbCode(_ linear: Float) -> Int {
        let c = max(0, min(1, linear))
        let encoded = c <= 0.0031308 ? 12.92 * c : 1.055 * powf(c, 1 / 2.4) - 0.055
        return Int((encoded * 255).rounded())
    }

    private func linear(_ code: Int) -> Float {
        let c = Float(code) / 255
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    /// The fixture index shown in the middle of the output (nil: not a fixture color / transparent).
    private func shownIndex(_ rig: GPURig, _ output: MTLTexture) throws -> Int? {
        let p = try rig.read(output)[32 * 64 + 32]
        guard p.w > 0.99 else { return nil }
        let level = srgbCode(p.x)
        return VideoFixtures.index(level: level)
    }

    /// Playback time `ns` → presentation time (frame 0 is at `base`).
    private func presentation(_ ns: Int64) -> UInt64 { base + UInt64(ns) }

    private func start(_ rig: GPURig, _ url: URL) throws -> (VideoLayerSource, Compositor) {
        let layer = VideoLayerSource(device: rig.device)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        layer.content = .file(url)
        return (layer, compositor)
    }

    private func waitForState(_ layer: VideoLayerSource, _ matches: (VideoLayerState) -> Bool) -> Bool {
        for _ in 0..<500 where !matches(layer.state) { usleep(10_000) }
        return matches(layer.state)
    }

    /// S1, S2: at playback time t the shown picture is ⌊t × 30⌋ (over a loop), queue ≤ 3.
    func testPicturesFollowTheTimelineAtTheIntendedRate() async throws {
        let rig = try GPURig()
        let (layer, compositor) = try start(rig, try await fixture("counter.mov"))
        XCTAssertEqual(layer.fallback, .transparent)
        let output = try rig.output()
        for i in 0..<75 {
            let t: Int64 = i == 0 ? 0 : Int64(i) * 1_000_000_000 / 30 + 5_000_000
            XCTAssertTrue(layer.waitUntilBuffered())
            try rig.frame(compositor, into: output, time: presentation(t))
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "step \(i)")
            XCTAssertEqual(layer.playbackNanoseconds, t)
            XCTAssertEqual(try shownIndex(rig, output), i % 30, "playback \(t) ns shows picture \(i % 60) (level \(i % 30))")
        }
        XCTAssertEqual(layer.state, .playing(width: 64, height: 48))
        let s = layer.statistics
        XCTAssertLessThanOrEqual(s.maxDepth, 3, "bounded decode queue")
        XCTAssertEqual(s.loops, 1)
        XCTAssertEqual(s.dropped, 0)
        XCTAssertEqual(layer.framesShown, 75)
    }

    /// S3: a solid picture reads back as the linear value of the code the decoder produced.
    func testSolidPictureReadsBackLinear() async throws {
        let rig = try GPURig()
        let written = (r: UInt8(188), g: UInt8(90), b: UInt8(40))
        let url = try await fixture("solid.mov", .init(frames: 10, solid: written))
        // The decoder's own 8-bit result (codec rounding is not the layer's concern; research D2).
        let asset = AVURLAsset(url: url)
        let track = try await XCTUnwrapAsync(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [  // the layer's reader settings
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        reader.add(out)
        XCTAssertTrue(reader.startReading())
        let pixels = try XCTUnwrap(out.copyNextSampleBuffer().flatMap(CMSampleBufferGetImageBuffer))
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let row = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self) + 24 * CVPixelBufferGetBytesPerRow(pixels) + 32 * 4
        let decoded = (r: Int(row[2]), g: Int(row[1]), b: Int(row[0]))
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        reader.cancelReading()
        XCTAssertLessThanOrEqual(abs(decoded.r - Int(written.r)), 12, "codec rounding stays small")
        XCTAssertLessThanOrEqual(abs(decoded.b - Int(written.b)), 12)

        let (layer, compositor) = try start(rig, url)
        XCTAssertTrue(layer.waitUntilBuffered())
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: base)
        // The middle 16 × 16 (the codec's 4:2:0 chroma differs by a few codes near the picture's edges,
        // which is the codec's rounding, not the layer's conversion).
        let all = try rig.read(output)
        let middle = (24..<40).flatMap { y in (24..<40).map { all[y * 64 + $0] } }
        assertAll(middle, equal: Pixel(linear(decoded.r), linear(decoded.g), linear(decoded.b), 1),
                  tolerance: 1.0 / 255, "video sRGB → linear, opaque")
        assertAll(all, equal: Pixel(linear(decoded.r), linear(decoded.g), linear(decoded.b), 1),
                  tolerance: 8.0 / 255, "the whole picture is the solid color within the codec's edge rounding")
    }

    /// S7: a stored copy that cannot be decoded gives the transparent fallback and a typed error.
    func testDamagedCopyFallsBackTransparentWithTypedError() async throws {
        let rig = try GPURig()
        var data = try Data(contentsOf: try await fixture("good.mov"))
        let start = data.range(of: Data("mdat".utf8))!.upperBound
        for i in start..<min(start + 6000, data.count / 2) { data[i] = UInt8(truncatingIfNeeded: i &* 131) }
        let damaged = directory.appendingPathComponent("damaged.mov")
        try data.write(to: damaged)
        let (layer, compositor) = try self.start(rig, damaged)
        XCTAssertTrue(waitForState(layer) { if case .failed = $0 { return true } else { return false } }, "state \(layer.state)")
        XCTAssertEqual(layer.state, .failed(.damaged))
        let output = try rig.output()
        XCTAssertTrue(try rig.frame(compositor, into: output, time: base), "the compositor keeps drawing")
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady))
        assertAll(try rig.read(output), equal: .zero, "transparent")
        let missing = VideoLayerSource(device: rig.device)
        missing.content = .file(directory.appendingPathComponent("gone.mov"))
        XCTAssertTrue(waitForState(missing) { if case .failed = $0 { return true } else { return false } })
    }

    /// R9, R13: a pause continues from the same picture; suspend releases the decoder and resumes there.
    func testPauseAndSuspendContinueFromTheSamePicture() async throws {
        let rig = try GPURig()
        let (layer, compositor) = try start(rig, try await fixture("counter.mov"))
        let output = try rig.output()
        var t: Int64 = 0
        var p: UInt64 = base
        func step(_ presentationStep: UInt64) throws {
            XCTAssertTrue(layer.waitUntilBuffered())
            p += presentationStep
            try rig.frame(compositor, into: output, time: p)
            t = layer.playbackNanoseconds
        }
        try step(0)
        for _ in 0..<10 { try step(33_333_334) }
        XCTAssertEqual(try shownIndex(rig, output), 10)
        try step(5_000_000_000)   // a 5 s gap (paused): playback does not move
        XCTAssertEqual(try shownIndex(rig, output), 10, "continues from the picture it stopped at")
        try step(33_333_334)
        XCTAssertEqual(try shownIndex(rig, output), 11)

        layer.suspendDecoding()   // background
        try rig.frame(compositor, into: output, time: p + 16_666_667)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "nothing decoded or held in the background")
        XCTAssertEqual(layer.statistics, VideoPipelineStatistics(), "the decoder and its pictures are released")
        layer.resumeDecoding()
        p += 60_000_000_000
        XCTAssertTrue(layer.waitUntilBuffered())
        try rig.frame(compositor, into: output, time: p)
        XCTAssertEqual(layer.playbackNanoseconds, t)
        XCTAssertEqual(try shownIndex(rig, output), 11, "resumes at the same playback time")
        try step(33_333_334)
        XCTAssertEqual(try shownIndex(rig, output), 12)
        // A 0.5 s hitch (within the 1 s rule): the first frame may still show an older decoded picture
        // (never a later one); the decoder catches up on its own and the next frame is exact.
        try step(500_000_000)
        let afterHitch = try XCTUnwrap(try shownIndex(rig, output))
        XCTAssertTrue((12...27).contains(afterHitch), "an older or the due picture, never a later one: \(afterHitch)")
        try step(0)
        XCTAssertEqual(try shownIndex(rig, output), 27, "caught up: picture 27 at 0.9 s")
        XCTAssertLessThanOrEqual(layer.statistics.maxDepth, 3)
    }

    /// New content restarts at 0; a rotated (portrait) video reports its upright size.
    func testNewContentRestartsAndRotationIsUpright() async throws {
        let rig = try GPURig()
        let (layer, compositor) = try start(rig, try await fixture("counter.mov"))
        let output = try rig.output()
        XCTAssertTrue(layer.waitUntilBuffered())
        try rig.frame(compositor, into: output, time: base)
        XCTAssertTrue(layer.waitUntilBuffered())
        try rig.frame(compositor, into: output, time: base + 500_000_000)
        XCTAssertTrue(layer.waitUntilBuffered())
        try rig.frame(compositor, into: output, time: base + 500_000_000)
        XCTAssertEqual(try shownIndex(rig, output), 15, "after the decoder caught up")
        layer.content = .file(try await fixture("rotated.mov", .init(rotated: true)))
        XCTAssertEqual(layer.playbackNanoseconds, 0)
        XCTAssertTrue(layer.waitUntilBuffered())
        try rig.frame(compositor, into: output, time: base + 600_000_000)
        XCTAssertEqual(try shownIndex(rig, output), 0, "the new video starts at its first picture")
        XCTAssertTrue(waitForState(layer) { $0 == .playing(width: 48, height: 64) }, "upright size \(layer.state)")
        layer.content = .none
        XCTAssertEqual(layer.state, .empty)
        try rig.frame(compositor, into: output, time: base + 700_000_000)
        XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady))
    }
}

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
#endif
