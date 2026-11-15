// MED-005-T03: the plain-Swift rules of cached reverse playback with a fake decoder (MED-005-R2 to R5, R10; S1, S3).
// Runs in the Linux shape too. No wall clock: video time is injected.
import CameraLayer
import Foundation
import ImageLayer
import VideoLayer
import XCTest

/// `frameCount` pictures at `fps`; each picture is its index. Optionally fails after `failAfter` pictures.
final class ReverseFakeDecoder: VideoReverseDecoding {
    let frameCount: Int
    let fps: Int64
    let width: Int
    let height: Int
    let failAfter: Int?
    let openError: VideoReverseUnsupported?
    private var position = 0
    private(set) var converted = 0

    init(frameCount: Int, fps: Int64 = 30, width: Int = 64, height: Int = 48, failAfter: Int? = nil,
         openError: VideoReverseUnsupported? = nil) {
        self.frameCount = frameCount
        self.fps = fps
        self.width = width
        self.height = height
        self.failAfter = failAfter
        self.openError = openError
    }

    func pts(_ k: Int) -> Int64 { Int64(k) * 1_000_000_000 / fps }

    func open() throws(VideoReverseUnsupported) -> VideoTrackInfo {
        if let openError { throw openError }
        return VideoTrackInfo(width: width, height: height, rotation: .none, frameRate: Double(fps),
                              durationNanoseconds: pts(frameCount), codec: .h264)
    }

    func next(width: Int, height: Int, accept: (Int64) -> Bool) throws(VideoReverseUnsupported) -> (pts: Int64, picture: Int?)? {
        if let failAfter, position >= failAfter { throw .undecodable }
        guard position < frameCount else { return nil }
        defer { position += 1 }
        let t = pts(position)
        guard accept(t) else { return (t, nil) }
        converted += 1
        return (t, position)
    }
}

final class VideoReverseTests: XCTestCase {
    private static let megabyte = 1024 * 1024
    private static let picture: Int64 = 1_000_000_000 / 30

    private func info(width: Int = 64, height: Int = 48, seconds: Double, rotation: Bool = false) -> VideoTrackInfo {
        VideoTrackInfo(width: width, height: height, rotation: rotation ? .clockwise90 : .none, frameRate: 30,
                       durationNanoseconds: Int64(seconds * 1e9), codec: .h264)
    }

    private func built(_ decoder: ReverseFakeDecoder, budget: Int = 32 * 1024 * 1024,
                       limits: VideoReverseLimits = .standard) throws -> VideoReverseCache<Int> {
        guard case .built(let cache) = VideoReverseCacheBuilder.build(decoder, limits: limits, budgetBytes: budget, isCancelled: { false }) else {
            XCTFail("not built")
            throw XCTSkip("not built")
        }
        return cache
    }

    // MARK: R2, R5 — eligibility and messages

    func testOnlyShortClipsUpTo1080pAreSupportedWithClearMessages() {
        let budget = 32 * Self.megabyte
        XCTAssertNoThrow(try VideoReversePlan(info: info(width: 1920, height: 1080, seconds: 30), budgetBytes: budget))
        XCTAssertNoThrow(try VideoReversePlan(info: info(width: 1920, height: 1080, seconds: 12, rotation: true), budgetBytes: budget),
                         "portrait 1080 × 1920 fits either way up")
        let refused: [(VideoTrackInfo, VideoReverseUnsupported)] = [
            (info(seconds: 30.001), .tooLong), (info(width: 1920, height: 1088, seconds: 5), .tooLarge),
            (info(width: 2048, height: 1080, seconds: 5), .tooLarge), (info(width: 3840, height: 2160, seconds: 40), .tooLong),
            (info(seconds: 0), .undecodable),
        ]
        for (facts, expected) in refused {
            XCTAssertThrowsError(try VideoReversePlan(info: facts, budgetBytes: budget)) { (error: Error) in
                XCTAssertEqual(error as? VideoReverseUnsupported, expected, "\(facts)")
            }
        }
        XCTAssertEqual(VideoReverseUnsupported.tooLong.message,
                       "Reverse playback is available for clips up to 30 seconds. This video plays forward.")
        XCTAssertEqual(VideoReverseUnsupported.tooLarge.message,
                       "Reverse playback is available for clips up to 1080p. This video plays forward.")
        XCTAssertEqual(VideoReverseUnsupported.undecodable.message, "This video can't be played in reverse. It plays forward.")
    }

    // MARK: R3, S3 — the budget holds for the largest supported clip on every device class

    func testLargestSupportedClipFitsEachDeviceClassBudget() throws {
        let gib: UInt64 = 1024 * 1024 * 1024
        for memory in [3 * gib, 6 * gib, 12 * gib] {
            let budget = AnimatedFrameBudget.bytes(physicalMemory: memory)
            let largest = VideoTrackInfo(width: 1920, height: 1080, rotation: .none, frameRate: 60,
                                         durationNanoseconds: 30_000_000_000, codec: .hevc)
            let plan = try VideoReversePlan(info: largest, budgetBytes: budget)
            XCTAssertLessThanOrEqual(plan.fullBytes, budget, "\(budget / Self.megabyte) MB")
            XCTAssertLessThanOrEqual(plan.pictureWidth, 1920)
            XCTAssertGreaterThanOrEqual(plan.pictureWidth, 100, "a usable picture at \(budget / Self.megabyte) MB")
            XCTAssertEqual(plan.maxPictures, 928, "≤ 30 a second over 30 s")
            // The real build path with a fake 60 fps decoder (the pictures are integers, the accounting is the plan's).
            let decoder = ReverseFakeDecoder(frameCount: 1800, fps: 60, width: 1920, height: 1080)
            let cache = try built(decoder, budget: budget)
            XCTAssertLessThanOrEqual(cache.peakBytes, budget, "peak within the budget")
            XCTAssertEqual(cache.pictures.count, 900, "every other picture of a 60 fps clip")
            XCTAssertEqual(decoder.converted, 900, "skipped pictures are never converted")
            print("MED-005 budget \(budget / Self.megabyte) MB: \(plan.pictureWidth) × \(plan.pictureHeight), peak \(cache.peakBytes) bytes")
        }
        let smaller = try VideoReversePlan(info: info(seconds: 2), budgetBytes: 128 * Self.megabyte)
        XCTAssertEqual(smaller.pictureWidth, 64, "never larger than the clip")
        XCTAssertEqual(smaller.pictureHeight, 48)
    }

    func testABudgetTooSmallForEvenTinyPicturesIsTooLarge() {
        let outcome = VideoReverseCacheBuilder.build(ReverseFakeDecoder(frameCount: 12), budgetBytes: 100, isCancelled: { false })
        guard case .unsupported(.tooLarge) = outcome else { return XCTFail("\(outcome)") }
    }

    // MARK: R4, S1 — selection

    /// "Short fixture reverses frame order": 12 pictures, steps of one picture interval (+ 5 ms) show 11 … 0 then wrap.
    func testTwelvePicturesPlayInDescendingOrderAndWrap() throws {
        let cache = try built(ReverseFakeDecoder(frameCount: 12))
        XCTAssertEqual(cache.pictures, Array(0..<12))
        var shown: [Int] = []
        for k in 0..<30 {
            let elapsed: Int64 = Int64(k) * Self.picture + 5_000_000
            shown.append(cache.pictures[cache.timeline.index(elapsedNanoseconds: elapsed, region: nil, startMediaNanoseconds: nil)])
        }
        let expected: [Int] = (0..<30).map { (k: Int) -> Int in 11 - k % 12 }
        XCTAssertEqual(shown, expected)
        XCTAssertEqual(cache.timeline.index(elapsedNanoseconds: 0, region: nil, startMediaNanoseconds: nil), 11, "starts at the end")
    }

    func testRegionStartAndSpeedArePureFunctionsOfVideoTime() throws {
        let cache = try built(ReverseFakeDecoder(frameCount: 60))
        let region = VideoLoopRegion(inMilliseconds: 500, outMilliseconds: 1000)   // pictures 15 … 29
        var shown: [Int] = []
        for k in 0..<32 {
            shown.append(cache.timeline.index(elapsedNanoseconds: Int64(k) * Self.picture + 5_000_000, region: region, startMediaNanoseconds: nil))
        }
        XCTAssertEqual(Array(shown.prefix(15)), Array((15...29).reversed()), "out back to in")
        XCTAssertEqual(shown[15], 29, "wraps from in back to out")
        XCTAssertTrue(shown.allSatisfy { (15...29).contains($0) }, "never outside the region")
        // Starting at the shown picture (7): no jump.
        let start = cache.timeline.mediaNanoseconds[7]
        let fromSeven: [Int] = (0..<9).map { (k: Int) -> Int in
            cache.timeline.index(elapsedNanoseconds: Int64(k) * Self.picture + 5_000_000, region: nil, startMediaNanoseconds: start)
        }
        XCTAssertEqual(fromSeven, [7, 6, 5, 4, 3, 2, 1, 0, 59])
        // At 0.5× (MED-004's clock): 2 s presented = 1 s of video = 30 pictures back.
        var clock = VideoPlaybackClock()
        clock.setSpeed(try XCTUnwrap(VideoPlaybackSpeed(percent: 50)))
        clock.advance(to: 1_000_000_000)
        for i in 1...120 { clock.advance(to: 1_000_000_000 + UInt64(i) * 1_000_000_000 / 60) }
        XCTAssertEqual(clock.playbackNanoseconds, 1_000_000_000)
        XCTAssertEqual(cache.timeline.index(elapsedNanoseconds: clock.playbackNanoseconds + 5_000_000, region: nil, startMediaNanoseconds: nil), 29)
    }

    // MARK: Build failures and cancel

    func testFailuresAndCancelNeverLeaveACache() {
        let failing = VideoReverseCacheBuilder.build(ReverseFakeDecoder(frameCount: 12, failAfter: 4), budgetBytes: 1 << 24, isCancelled: { false })
        guard case .unsupported(.undecodable) = failing else { return XCTFail("\(failing)") }
        let empty = VideoReverseCacheBuilder.build(ReverseFakeDecoder(frameCount: 0), budgetBytes: 1 << 24, isCancelled: { false })
        guard case .unsupported = empty else { return XCTFail("\(empty)") }
        let unopened = VideoReverseCacheBuilder.build(ReverseFakeDecoder(frameCount: 12, openError: .undecodable), budgetBytes: 1 << 24,
                                                      isCancelled: { false })
        guard case .unsupported(.undecodable) = unopened else { return XCTFail("\(unopened)") }
        var asked = 0
        let cancelled = VideoReverseCacheBuilder.build(ReverseFakeDecoder(frameCount: 12), budgetBytes: 1 << 24) { () -> Bool in
            asked += 1
            return asked > 3
        }
        guard case .cancelled = cancelled else { return XCTFail("\(cancelled)") }
    }

    func testFrameStoreNeverExceedsItsBudgetAndRecordsThePeak() {
        var store = VideoReverseFrameStore<Int>(budgetBytes: 100)
        XCTAssertTrue(store.reserve(60))
        XCTAssertFalse(store.reserve(50), "over the budget: refused, nothing evicted")
        store.commit(media: 0, picture: 0, bytes: 40, reserved: 60)
        XCTAssertTrue(store.reserve(60))
        store.commit(media: 1, picture: 1, bytes: 40, reserved: 60)
        XCTAssertEqual(store.accountedBytes, 80)
        XCTAssertEqual(store.peakBytes, 100)
        XCTAssertEqual(store.pictures.count, 2)
    }
}
