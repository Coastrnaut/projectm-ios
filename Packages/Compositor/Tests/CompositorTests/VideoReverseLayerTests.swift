// MED-005-T07, T15, T17: reverse playback through the real Metal compositor at 64 × 64 with injected presentation
// times (MED-005-R1 to R6, R9; S1 to S3). Fixtures are generated with `AVAssetWriter` (VideoFixtures: picture i is
// grey level 8 + 8 × i). Skipped without a Metal device. Waits are ceilings for the build thread, never timing
// assertions.
#if canImport(Metal) && !COMPOSITOR_NO_METAL && canImport(AVFoundation)
import AVFoundation
import Compositor
import Metal
import VideoLayer
import XCTest

final class VideoReverseLayerTests: XCTestCase {
    private var directory: URL!
    private let base: UInt64 = 50_000_000_000
    private static let picture: Int64 = 1_000_000_000 / 30

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MED005-layer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture(_ name: String, frames: Int) async throws -> URL {
        let url = directory.appendingPathComponent(name)
        var options = VideoFixtures.Options()
        options.frames = frames
        try await VideoFixtures.write(to: url, options)
        return url
    }

    /// The fixture index in the middle of the output (nil: transparent or not a fixture level).
    private func shownIndex(_ rig: GPURig, _ output: MTLTexture) throws -> Int? {
        let p = try rig.read(output)[32 * 64 + 32]
        guard p.w > 0.99 else { return nil }
        let c = max(0, min(1, p.x))
        let encoded = c <= 0.0031308 ? 12.92 * c : 1.055 * powf(c, 1 / 2.4) - 0.055
        return VideoFixtures.index(level: Int((encoded * 255).rounded()))
    }

    /// Video time of step `k`: 0, then k picture intervals + 5 ms (≥ 5 ms from a picture edge).
    private func time(_ k: Int, offset: Int64 = 5_000_000) -> UInt64 { k == 0 ? base : base + UInt64(Int64(k) * Self.picture + offset) }

    private func layer(_ rig: GPURig) throws -> (VideoLayerSource, Compositor) {
        let layer = VideoLayerSource(device: rig.device)
        return (layer, try Compositor(device: rig.device, layers: [layer]))
    }

    /// S1, R4: "Short fixture reverses frame order": 12 pictures read back 11 … 0, then wrap to 11 (twice round).
    func testTwelvePictureFixtureReversesFrameOrderThroughTheCompositor() async throws {
        let rig = try GPURig()
        let (layer, compositor) = try layer(rig)
        layer.reverse = true
        XCTAssertEqual(layer.reverseState, .off, "no content yet")
        layer.content = .file(try await fixture("twelve.mov", frames: 12))
        XCTAssertTrue(layer.waitUntilReverseBuilt(), "the build ends")
        XCTAssertEqual(layer.reverseState, .playing)
        let output = try rig.output()
        var shown: [Int] = []
        for k in 0..<26 {
            try rig.frame(compositor, into: output, time: time(k))
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "step \(k)")
            shown.append(try shownIndex(rig, output) ?? -1)
            XCTAssertEqual(layer.reverseShownIndex, shown.last, "the cache index is the fixture index")
        }
        let expected: [Int] = (0..<26).map { (k: Int) -> Int in 11 - k % 12 }
        XCTAssertEqual(shown, expected, "descending, at one picture per interval, wrapping from 0 back to 11")
        XCTAssertGreaterThan(layer.reversePeakBytes, 0)
        XCTAssertLessThanOrEqual(layer.reversePeakBytes, layer.reverseBudgetBytes)
        print("MED-005 reverse fixture: \(shown)")
    }

    /// R1, R6: off resumes forward at the picture shown last; a region plays backwards inside it.
    func testOffResumesForwardAtTheShownPictureAndARegionStaysInside() async throws {
        let rig = try GPURig()
        let (layer, compositor) = try layer(rig)
        layer.content = .file(try await fixture("counter.mov", frames: 60))
        let output = try rig.output()
        for k in 0..<10 {   // forward: pictures 0 … 9
            XCTAssertTrue(layer.waitUntilBuffered())
            try rig.frame(compositor, into: output, time: time(k))
        }
        XCTAssertEqual(try shownIndex(rig, output), 9)
        layer.reverse = true
        XCTAssertEqual(layer.reverseState, .preparing)
        XCTAssertTrue(layer.waitUntilReverseBuilt())
        var reversed: [Int] = []
        for k in 10..<14 {   // the cache starts at the shown picture: 9, 8, 7, 6
            // After the first reversed frame, sample 15 ms inside each interval (not on a picture boundary).
            try rig.frame(compositor, into: output, time: time(k, offset: k == 10 ? 5_000_000 : 20_000_000))
            reversed.append(try shownIndex(rig, output) ?? -1)
        }
        XCTAssertEqual(reversed, [9, 8, 7, 6], "no jump when reverse starts")
        layer.loopRegion = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)   // pictures 15 … 29
        var inside: [Int] = []
        for k in 14..<34 {
            try rig.frame(compositor, into: output, time: time(k))
            inside.append(layer.reverseShownIndex ?? -1)
        }
        XCTAssertTrue(inside.allSatisfy { (15...29).contains($0) }, "inside the region: \(inside)")
        XCTAssertEqual(Array(inside.prefix(15)), Array((15...29).reversed()), "out back to in")
        XCTAssertEqual(inside[15], 29, "wraps from in back to out")
        layer.loopRegion = nil
        let last = try XCTUnwrap(try shownIndex(rig, output))
        layer.reverse = false
        XCTAssertEqual(layer.reverseState, .off)
        var forward: [Int] = []
        for k in 34..<40 {
            XCTAssertTrue(layer.waitUntilBuffered())
            try rig.frame(compositor, into: output, time: time(k))
            forward.append(try shownIndex(rig, output) ?? -1)
        }
        // Forward continues from the picture shown last (that picture or the next one, as after a resume), then advances
        // one picture per step (a picture may be held one extra frame while the restarted decoder catches up).
        let first = try XCTUnwrap(forward.first)
        XCTAssertTrue(first == last || first == (last + 1) % VideoFixtures.levels, "resumes at \(last): \(forward)")
        var distinct: [Int] = []
        for i in forward where distinct.last != i { distinct.append(i) }
        XCTAssertGreaterThanOrEqual(distinct.count, 4, "\(forward)")
        for (n, i) in distinct.enumerated() {
            XCTAssertEqual(i, (first + n) % VideoFixtures.levels, "plays forward again: \(forward)")
        }
    }

    /// S2, R5: a clip over the duration limit (by its track facts) and a corrupt copy report their reason; the
    /// over-limit clip keeps playing forward.
    func testUnsupportedClipsReportTheirReasonAndKeepPlayingForward() async throws {
        let rig = try GPURig()
        let (layer, compositor) = try layer(rig)
        layer.reverseLimits = VideoReverseLimits(maxDurationNanoseconds: 1_000_000_000, maxLongestSide: 1920, maxShortestSide: 1080,
                                                 maxPicturesPerSecond: 30)
        layer.reverse = true
        layer.content = .file(try await fixture("two-seconds.mov", frames: 60))
        XCTAssertTrue(layer.waitUntilReverseBuilt())
        XCTAssertEqual(layer.reverseState, .unsupported(.tooLong))
        let output = try rig.output()
        var forward: [Int] = []
        for k in 0..<8 {
            XCTAssertTrue(layer.waitUntilBuffered())
            try rig.frame(compositor, into: output, time: time(k))
            forward.append(try shownIndex(rig, output) ?? -1)
        }
        XCTAssertEqual(forward, Array(0..<8), "playback falls back to forward")
        XCTAssertNil(layer.reverseShownIndex)

        var data = try Data(contentsOf: try await fixture("good.mov", frames: 30))
        let start = try XCTUnwrap(data.range(of: Data("mdat".utf8))).upperBound
        for i in start..<min(start + 6000, data.count / 2) { data[i] = UInt8(truncatingIfNeeded: i &* 131) }
        let damaged = directory.appendingPathComponent("damaged.mov")
        try data.write(to: damaged)
        let (broken, brokenCompositor) = try self.layer(rig)
        broken.reverse = true
        broken.content = .file(damaged)
        XCTAssertTrue(broken.waitUntilReverseBuilt())
        XCTAssertEqual(broken.reverseState, .unsupported(.undecodable))
        XCTAssertTrue(try rig.frame(brokenCompositor, into: output, time: base), "the compositor keeps drawing")
    }

    /// S3, R3, R9: a small budget holds; suspend releases the cache and resume rebuilds it.
    func testSmallBudgetHoldsAndSuspendReleasesTheCache() async throws {
        let rig = try GPURig()
        let (layer, compositor) = try layer(rig)
        layer.reverseBudgetBytes = 64 * 1024
        layer.reverse = true
        layer.content = .file(try await fixture("twelve.mov", frames: 12))
        XCTAssertTrue(layer.waitUntilReverseBuilt())
        XCTAssertEqual(layer.reverseState, .playing)
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: time(0))
        XCTAssertEqual(try shownIndex(rig, output), 11, "downsampled pictures keep their grey level")
        XCTAssertGreaterThan(layer.reversePeakBytes, 0)
        XCTAssertLessThanOrEqual(layer.reversePeakBytes, 64 * 1024, "peak within the budget")
        layer.suspendDecoding()
        XCTAssertEqual(layer.reverseState, .preparing, "released in the background")
        XCTAssertNil(layer.reverseShownIndex)
        layer.resumeDecoding()
        XCTAssertTrue(layer.waitUntilReverseBuilt())
        XCTAssertEqual(layer.reverseState, .playing, "rebuilt on resume")
    }
}
#endif
