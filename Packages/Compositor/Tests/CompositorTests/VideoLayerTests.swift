// MED-002-T13, T14: the video layer through the real Metal compositor at 64 × 64 with injected
// presentation times (a fake clock; MED-002-R9 to R13, S1 to S3, S7). Fixtures are generated; skipped
// without a Metal device. Waits are ceilings for the decode thread, never timing assertions.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(AVFoundation)
import AVFoundation
import Compositor
import Metal
import os
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

    /// MED-003-T07 (S1, S2): a loop region on a real file: every shown picture (read from pixels) is
    /// inside [0.5 s, 1.0 s) = pictures 15-29 across three boundaries, the wrap goes from 29 to 15 with
    /// no held picture when the decoder keeps up, and a region edit mid-play continues inside.
    func testLoopRegionOnARealFileStaysInsideAcrossBoundaries() async throws {
        let rig = try GPURig()
        let layer = VideoLayerSource(device: rig.device)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        layer.loopRegion = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)
        layer.content = .file(try await fixture("counter.mov"))
        let output = try rig.output()
        for i in 0..<50 {
            let t: Int64 = i == 0 ? 0 : Int64(i) * 1_000_000_000 / 30 + 5_000_000
            XCTAssertTrue(layer.waitUntilBuffered())
            try rig.frame(compositor, into: output, time: presentation(t))
            XCTAssertEqual(try shownIndex(rig, output), 15 + i % 15, "step \(i)")
            let media = try XCTUnwrap(layer.shownMediaNanoseconds)
            XCTAssertTrue(media >= 500_000_000 && media < 1_000_000_000, "step \(i): \(media) inside")
        }
        XCTAssertEqual(layer.wraps, 3)
        XCTAssertLessThan(layer.maxWrapLatenessNanoseconds, 1_000_000_000 / 30, "gap 0 frames at the joint")
        XCTAssertEqual(layer.mediaDurationNanoseconds, 2_000_000_000)
        XCTAssertGreaterThanOrEqual(layer.statistics.prepared, 1, "the pass at in was prepared ahead of out")
        XCTAssertEqual(layer.statistics.dropped, 0)

        // Edit: out moves to 0.8 s (picture 24) while picture 19 (step 49 → 15 + 4) is shown: continue inside.
        layer.loopRegion = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 800)
        var shown: [Int] = []
        for i in 50..<70 {
            let t: Int64 = Int64(i) * 1_000_000_000 / 30 + 5_000_000
            XCTAssertTrue(layer.waitUntilBuffered())
            try rig.frame(compositor, into: output, time: presentation(t))
            if let index = try shownIndex(rig, output) { shown.append(index) }
        }
        XCTAssertFalse(shown.isEmpty)
        XCTAssertTrue(shown.allSatisfy { (k: Int) -> Bool in (15...23).contains(k) }, "inside the edited region: \(shown)")
        XCTAssertEqual(layer.state, .playing(width: 64, height: 48))
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

    /// Regression (SIGSEGV in `CVMetalTextureCache::bufferBackingNotInUse`, CAM-013 gate 2026-11-14):
    /// the crash report showed the decode thread finalizing an `AVVideoFrameReader`'s texture cache
    /// (a failed reopen ended the session) while the render thread released the picture it held, whose
    /// release reports back to that cache. A picture must keep its cache alive, so the cache can only
    /// be finalized after its last picture. This races the two releases many times.
    func testPictureReleaseRacesItsReadersRelease() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        try Self.raceReleases(url: try await fixture("race.mov"), device: device, rounds: 120)
    }

    /// Sequential: every reader (and its cache) is released before its pictures, which stay valid.
    func testPictureOutlivesItsReaderAndCache() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
        let url = try await fixture("outlive.mov")
        var frames: [VideoTextureFrame] = []
        for _ in 0..<10 {
            var reader: AVVideoFrameReader? = AVVideoFrameReader(url: url, device: device)
            _ = try reader?.open(startNanoseconds: 0)
            for _ in 0..<3 {
                if let next = try reader?.next() { frames.append(next.frame) }
            }
            reader = nil
            XCTAssertNil(reader)
        }
        XCTAssertEqual(frames.count, 30)
        XCTAssertTrue(frames.allSatisfy { (frame: VideoTextureFrame) -> Bool in frame.texture.width > 0 })
        frames.removeAll()
    }

    /// Synchronous: each round a second thread, started by a spin handshake, drops the reader (and its cache)
    /// while this thread drops the pictures, at an offset swept over the rounds. Before the fix about 7 in
    /// 10 runs of 60 rounds crashed. Rounds stop at a 4 s cap.
    private static func raceReleases(url: URL, device: MTLDevice, rounds: Int) throws {
        let deadline = Date().addingTimeInterval(4)   // a time cap for a loaded host (short tests)
        for round in 0..<rounds where Date() < deadline {
            let box = ReaderBox(AVVideoFrameReader(url: url, device: device))   // the only strong reference
            _ = try box.reader?.open(startNanoseconds: 0)
            var frames: [VideoTextureFrame] = []
            for _ in 0..<3 {
                if let next = try box.reader?.next() { frames.append(next.frame) }
            }
            XCTAssertEqual(frames.count, 3, "round \(round)")
            box.reader?.close()   // the reopen's close: only the cache's release is left for the race
            // Handshake by try-lock spins (neither side sleeps on the lock): 1 = releaser ready, 2 = go.
            let phase = OSAllocatedUnfairLock(initialState: 0)
            let releaser = Thread { () -> Void in
                while phase.withLockIfAvailable({ (p: inout Int) -> Void in p = max(p, 1) }) == nil {}
                while phase.withLockIfAvailable({ (p: inout Int) -> Int in p }) != 2 {}
                box.reader = nil   // the decode thread's side: releases the reader and its cache
                box.finished.signal()
            }
            releaser.qualityOfService = .userInitiated
            releaser.start()
            while phase.withLockIfAvailable({ (p: inout Int) -> Int in p }) != 1 {}
            while phase.withLockIfAvailable({ (p: inout Int) -> Void in p = 2 }) == nil {}
            spin(round % 16)      // sweep the offset between the two releases
            frames.removeAll()    // the render side: drops the held pictures at the same moment
            box.finished.wait()
        }
    }

    private static func spin(_ steps: Int) {
        var x: UInt64 = 0
        for i in 0..<(steps * 200) { x = x &+ UInt64(i) }
        withExtendedLifetime(x) { () -> Void in }
    }
}

/// Hands the last reference to another thread.
private final class ReaderBox: @unchecked Sendable {
    var reader: AVVideoFrameReader?
    let finished = DispatchSemaphore(value: 0)
    init(_ reader: AVVideoFrameReader) { self.reader = reader }
}

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
#endif
