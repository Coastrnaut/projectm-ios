// MED-014-T08, T12, T14, T15: the fixture table through the real import decoders (ImageIO and
// AVFoundation), a decoder fuzz, and the roadmap acceptance "Corrupt fixture fails gracefully and
// leaves compositor running" through the Metal compositor (MED-014-S1 to S3, R11, R12). Fixtures are
// generated (`MediaFixtureBytes`, ImageIO, AVAssetWriter); nothing is checked in. Waits are ceilings
// for background loads, never timing assertions. The Metal test is skipped without a device.
#if canImport(ImageIO) && canImport(AVFoundation)
import AVFoundation
import Compositor
import CoreGraphics
import ImageIO
import ImageLayer
import MediaSniffing
import UniformTypeIdentifiers
import VideoLayer
import XCTest

final class SafeDecoderTests: XCTestCase {
    private typealias F = MediaFixtureBytes
    private typealias RGBA = ImageFixtures.RGBA
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED014-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func imageOutcome(_ bytes: Data) -> Result<Int, ImageImportError> {
        do throws(ImageImportError) {
            let copy = try ImageSanitizer.sanitize(bytes, limits: .standard)
            return .success(copy.width)
        } catch {
            return .failure(error)
        }
    }

    private func videoOutcome(_ bytes: [UInt8], _ name: String) async throws -> Result<Int, VideoImportError> {
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return await videoOutcome(url)
    }

    private func videoOutcome(_ url: URL) async -> Result<Int, VideoImportError> {
        do throws(VideoImportError) {
            return .success(try await VideoProbe.check(url, limits: .standard).width)
        } catch {
            return .failure(error)
        }
    }

    /// F5: a 16 × 16 JPEG encoded by ImageIO.
    private func jpeg() -> Data {
        ImageFixtures.encode(ImageFixtures.solid(RGBA(r: 40, g: 90, b: 200, a: 255), width: 16, height: 16), .jpeg)
    }

    // MARK: - The fixture table (plan "Fixture table"; S1)

    func testImageFixtureTable() {
        let png = F.png()
        XCTAssertEqual(imageOutcome(Data(png)), .success(8), "F1 valid PNG decodes")
        let chunks = F.pngChunkOffsets(png)
        let idat = chunks.first { $0.type == "IDAT" }!, iend = chunks.first { $0.type == "IEND" }!
        for cut in [8, 8 + 15, idat.offset + 8 + idat.length / 2, iend.offset] {
            XCTAssertEqual(imageOutcome(Data(png.prefix(cut))), .failure(.damaged), "F2 cut at \(cut)")
        }
        var flipped = png
        flipped[idat.offset + 8 + 10] ^= 1
        XCTAssertEqual(imageOutcome(Data(flipped)), .failure(.damaged), "F3 bad CRC")
        XCTAssertEqual(imageOutcome(Data(F.png(headerWidth: 100_000, headerHeight: 100_000))), .failure(.tooManyPixels), "F4")

        let valid = jpeg()
        XCTAssertEqual(imageOutcome(valid), .success(16), "F5 valid JPEG decodes")
        XCTAssertEqual(try? ImageHeaderSniffer.sniff(valid), ImageHeaderFacts(container: .jpeg, width: 16, height: 16))
        XCTAssertEqual(imageOutcome(valid.prefix(valid.count - 2)), .failure(.damaged), "F6 no EOI")
        var absurd = [UInt8](valid)
        let sof = (0..<absurd.count - 1).first { absurd[$0] == 0xFF && (absurd[$0 + 1] == 0xC0 || absurd[$0 + 1] == 0xC2) }!
        absurd.replaceSubrange(sof + 5..<sof + 9, with: [0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(imageOutcome(Data(absurd)), .failure(.tooManyPixels), "F7 SOF 65,535 × 65,535")
        XCTAssertEqual(imageOutcome(Data()), .failure(.notAnImage), "F8 zero bytes")
        var rng = F.SplitMix64(seed: 9)
        let noise = F.pngSignature + (0..<4096).map { (_: Int) -> UInt8 in UInt8(truncatingIfNeeded: rng.next()) }
        XCTAssertEqual(imageOutcome(Data(noise)), .failure(.damaged), "F9 random bytes behind a PNG signature")
        var overrun = F.heif()
        overrun[3] = 0xF0
        XCTAssertEqual(imageOutcome(Data(overrun)), .failure(.damaged), "F10 HEIF ftyp past the end")
        XCTAssertEqual(imageOutcome(Data(F.heif(brands: ["\u{0}\u{0}\u{0}\u{0}", "\u{0}\u{0}\u{0}\u{0}"]))), .failure(.damaged),
                       "F11 HEIF ftyp without legible brands")
    }

    func testMovieFixtureTable() async throws {
        let f12 = try await videoOutcome(F.movieWithOverrunningMoov(), "f12.mov")
        XCTAssertEqual(f12, .failure(.damaged), "F12 moov past the end")
        let f13 = try await videoOutcome(F.movie(handler: "soun", format: "mp4a"), "f13.mov")
        XCTAssertEqual(f13, .failure(.notAVideo), "F13 sound only")
        let valid = directory.appendingPathComponent("f14.mov")
        try await VideoFixtures.write(to: valid)
        let f14 = await videoOutcome(valid)
        XCTAssertEqual(f14, .success(64), "F14 valid H.264 movie imports")
        let facts = try VideoContainerCheck.check(valid, limits: .standard)
        XCTAssertEqual(facts.codecString, "avc1")
        XCTAssertEqual(facts.codedWidth, 64)
        XCTAssertEqual(facts.codedHeight, 48)
        let f15 = try await videoOutcome(Array("This is plain text, not a movie.".utf8), "f15.mov")
        XCTAssertEqual(f15, .failure(.notAVideo), "F15 text")
        let f16 = try await videoOutcome(F.movie(width: 8192, height: 8), "f16.mov")
        XCTAssertEqual(f16, .failure(.pictureTooLarge), "F16 coded 8192 px")
        let empty = try await videoOutcome([], "empty.mov")
        XCTAssertEqual(empty, .failure(.notAVideo), "zero bytes")
    }

    // MARK: - Decoder fuzz (S2)

    func testDecoderFuzzAlwaysGivesAPictureOrATypedError() {
        var rng = F.SplitMix64(seed: 0x5AFE)
        let seeds = [Data(F.png()), jpeg()]
        var pictures = 0, errors = 0
        for i in 0..<300 {
            var bytes = [UInt8](seeds[i % 2])
            for _ in 0...rng.below(2) { bytes = F.mutate(bytes, &rng) }
            do throws(ImageImportError) {
                let decoded = try ImageIODecoder().decode(Data(bytes), limits: .standard)
                XCTAssertEqual(decoded.pixels.count, decoded.width * decoded.height * 4)
                pictures += 1
            } catch {
                errors += 1
            }
        }
        XCTAssertEqual(pictures + errors, 300)
        XCTAssertGreaterThan(errors, 150, "most mutations are refused before ImageIO")
    }
}

#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

/// The roadmap acceptance (MED-014-S3, R12; US4).
final class SafeDecoderIsolationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED014-iso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        for _ in 0..<500 where !condition() { usleep(10_000) }
        return condition()
    }

    /// A running compositor with a solid layer under a photo and a video: both media files are
    /// replaced by corrupt fixtures (the photo at load, the video while playing, caught at its loop
    /// reopen). Every frame is still produced, both layers report `.failed(.damaged)` and draw
    /// transparent, and the output is exactly the solid layer.
    func testCorruptStoredMediaFailGracefullyAndTheCompositorKeepsRunning() async throws {
        let rig = try GPURig()
        let solidColor = Pixel(0.2, 0.4, 0.6, 1)
        let solid = SolidLayer("solid", color: solidColor)
        let photo = ImageLayerSource(device: rig.device)
        let video = VideoLayerSource(device: rig.device)
        let compositor = try Compositor(device: rig.device, layers: [solid, photo, video])
        let output = try rig.output()

        let photoURL = directory.appendingPathComponent("photo.png")
        try Data(MediaFixtureBytes.png()).write(to: photoURL)
        let videoURL = directory.appendingPathComponent("video.mov")
        try await VideoFixtures.write(to: videoURL)
        photo.content = .file(photoURL)
        video.content = .file(videoURL)
        photo.waitUntilLoaded()
        XCTAssertEqual(photo.state, .ready(width: 8, height: 6))
        XCTAssertTrue(video.waitUntilBuffered())

        let base: UInt64 = 10_000_000_000
        var produced = 0
        func frame(_ t: UInt64) throws {
            XCTAssertTrue(try rig.frame(compositor, into: output, time: base + t), "frame at \(t) ns produced")
            produced += 1
        }
        try frame(0)
        XCTAssertEqual(compositor.outcome(ofLayer: 1), .rendered, "the valid photo renders")
        XCTAssertEqual(compositor.outcome(ofLayer: 2), .rendered, "the valid video renders")

        // (a) The photo's stored copy is damaged on disk; the layer loads it again.
        try Data(MediaFixtureBytes.png().prefix(60)).write(to: photoURL)
        photo.content = .none
        photo.content = .file(photoURL)
        photo.waitUntilLoaded()
        XCTAssertEqual(photo.state, .failed(.damaged), "the truncated PNG fails with its typed error")

        // (b) The playing video's file is replaced (a new file at the same path, so the open reader
        // keeps its old bytes); the reopen at the 2 s loop meets the damaged container.
        try Data(MediaFixtureBytes.movieWithOverrunningMoov()).write(to: videoURL, options: .atomic)
        var t: UInt64 = 0
        for _ in 0..<12 {
            t += 400_000_000
            video.waitUntilBuffered()
            try frame(t)
            XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackTransparent(.notReady), "the broken photo stays transparent")
        }
        XCTAssertTrue(waitUntil { video.state == .failed(.damaged) }, "the video fails at its reopen: \(video.state)")
        for _ in 0..<5 {
            t += 16_666_667
            try frame(t)
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "the solid layer is unaffected")
            XCTAssertEqual(compositor.outcome(ofLayer: 1), .fallbackTransparent(.notReady))
            XCTAssertEqual(compositor.outcome(ofLayer: 2), .fallbackTransparent(.notReady))
        }
        assertAll(try rig.read(output), equal: solidColor, tolerance: 1.0 / 255, "only the solid layer shows")
        XCTAssertEqual(produced, 18, "every frame was produced")
        XCTAssertEqual(photo.state, .failed(.damaged))
        XCTAssertEqual(video.state, .failed(.damaged), "no retry: the failure stays until the content changes")
    }
}
#endif
#endif
