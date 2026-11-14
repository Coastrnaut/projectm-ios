// RecordingRulesTests.swift — REC-003-T06: the plain-Swift recording rules (geometry, timeline, gate,
// refusals). Runs on the Mac host and in the Linux shape.
import FrameRecording
import XCTest

final class RecordingRulesTests: XCTestCase {
    private let ns30: UInt64 = 1_000_000_000 / 30

    // MARK: Geometry (research REC-003-D3)

    func testGeometryCropsOddSizesAndFitsTheLongSide() throws {
        let phone = try XCTUnwrap(RecordingGeometry(drawableWidth: 1179, drawableHeight: 2556, maxLongSide: 1920))
        XCTAssertEqual(phone.sourceWidth, 1178)
        XCTAssertEqual(phone.sourceHeight, 2556)
        XCTAssertEqual(phone.outputHeight, 1920)
        XCTAssertEqual(phone.outputWidth, 884)   // 1178 × 1920 / 2556 = 884.9 → nearest even
        XCTAssertTrue(phone.isScaled)
        XCTAssertEqual(phone.outputWidth % 2, 0)

        let small = try XCTUnwrap(RecordingGeometry(drawableWidth: 161, drawableHeight: 121, maxLongSide: 1920))
        XCTAssertEqual([small.sourceWidth, small.sourceHeight, small.outputWidth, small.outputHeight], [160, 120, 160, 120])
        XCTAssertFalse(small.isScaled)
        XCTAssertTrue(small.matches(drawableWidth: 161, drawableHeight: 120))
        XCTAssertFalse(small.matches(drawableWidth: 162, drawableHeight: 120))

        let landscape = try XCTUnwrap(RecordingGeometry(drawableWidth: 3840, drawableHeight: 2160, maxLongSide: 1920))
        XCTAssertEqual([landscape.outputWidth, landscape.outputHeight], [1920, 1080])
        XCTAssertNil(RecordingGeometry(drawableWidth: 1, drawableHeight: 100, maxLongSide: 1920))
    }

    func testSettingsAreClamped() {
        let s = RecordingSettings(maxFrameRate: 500, maxLongSide: 15, maxDurationSeconds: 0, framesInFlight: 0, codecPreference: [])
        XCTAssertEqual(s.maxFrameRate, 60)
        XCTAssertEqual(s.maxLongSide, 16)
        XCTAssertEqual(s.maxDurationSeconds, 1)
        XCTAssertEqual(s.framesInFlight, 1)
        XCTAssertEqual(s.codecPreference, [.hevc, .h264])
        XCTAssertEqual(RecordingSettings.standard.frameIntervalTicks, 20)
        XCTAssertEqual(RecordingSettings.standard.maxDurationTicks, 360_000)
    }

    // MARK: Timeline (REC-003-R5, R6; research REC-003-D4)

    /// Writes every candidate (no queue), returning the written ticks.
    private func run(_ times: [UInt64], settings: RecordingSettings = .standard) -> (ticks: [Int64], outcomes: [RecordingTimeline.Admission]) {
        var timeline = RecordingTimeline(settings: settings)
        var ticks: [Int64] = []
        var outcomes: [RecordingTimeline.Admission] = []
        for t in times {
            let a = timeline.admit(presentationNanoseconds: t)
            outcomes.append(a)
            if case .candidate(let tick) = a {
                timeline.markWritten(tick: tick)
                ticks.append(tick)
            }
        }
        return (ticks, outcomes)
    }

    func testThirtyFramesPerSecondGivesExactTicks() {
        let start: UInt64 = 5_000_000_000   // an arbitrary frame-clock origin
        let (ticks, _) = run((0..<300).map { (k: Int) -> UInt64 in start + UInt64(k) * 1_000_000_000 / 30 })
        XCTAssertEqual(ticks, (0..<300).map { (k: Int) -> Int64 in Int64(k) * 20 })
        var timeline = RecordingTimeline()
        for k in 0..<300 {
            if case .candidate(let tick) = timeline.admit(presentationNanoseconds: UInt64(k) * ns30) { timeline.markWritten(tick: tick) }
        }
        XCTAssertEqual(timeline.endTick, 6000, "10 s: the last frame plus one interval")
        XCTAssertEqual(timeline.recordedSeconds, 10, accuracy: 1e-9)
    }

    func testFasterLoopsAreCappedAtThirty() {
        let sixty = run((0..<120).map { (k: Int) -> UInt64 in UInt64(k) * 1_000_000_000 / 60 })
        XCTAssertEqual(sixty.ticks.count, 60, "every other frame of a 60 Hz loop")
        XCTAssertEqual(sixty.outcomes.filter { (a: RecordingTimeline.Admission) -> Bool in a == .skippedRate }.count, 60)
        let oneTwenty = run((0..<120).map { (k: Int) -> UInt64 in UInt64(k) * 1_000_000_000 / 120 })
        // REC-006 grid: 120 Hz into 30 fps takes the frame on each slot (every fourth), never one a quarter early.
        XCTAssertEqual(oneTwenty.ticks, (0..<30).map { (k: Int) -> Int64 in Int64(k) * 20 })
    }

    /// After a stall the grid continues from the late frame's slot: no burst of frames to catch up; the
    /// empty slots are left out (REC-006-D3).
    func testNoBurstAfterAStall() {
        let times: [UInt64] = [0, 33_333_333, 500_000_000, 516_666_667, 533_333_333, 550_000_000, 566_666_667]
        XCTAssertEqual(run(times).ticks, [0, 20, 300, 320, 340])
    }

    /// REC-006: a 20 fps loop recorded at 30 fps stays on the 30 fps grid; every third slot has no frame.
    func testSlowerLoopsStayOnTheGrid() {
        let twenty = run((0..<20).map { (k: Int) -> UInt64 in UInt64(k) * 50_000_000 })   // 20 fps
        XCTAssertEqual(twenty.ticks.count, 20, "every frame is written")
        XCTAssertTrue(twenty.ticks.allSatisfy { (t: Int64) -> Bool in t % 20 == 0 }, "\(twenty.ticks)")
        XCTAssertEqual(twenty.ticks.last, 580, "19 × 50 ms = 950 ms → slot 29 (rounded half up)")
    }

    func testJitterInsideTheHalfIntervalWindowIsKept() {
        // 30 fps with frames 4 ms early: each is still nearest its own slot.
        let times: [UInt64] = [0, 33_333_333 - 4_000_000, 66_666_667 - 4_000_000, 100_000_000]
        XCTAssertEqual(run(times).ticks, [0, 20, 40, 60])
        // 16 ms after the first frame is still in slot 0's window: skipped.
        XCTAssertEqual(run([0, 16_000_000]).outcomes.last, .skippedRate)
    }

    func testNonIncreasingTimesAreDroppedNeverWritten() {
        let times: [UInt64] = [1_000_000_000, 1_100_000_000, 1_100_000_000, 1_050_000_000, 900_000_000, 1_200_000_000]
        let (ticks, outcomes) = run(times)
        XCTAssertEqual(ticks, [0, 60, 120])
        XCTAssertEqual(outcomes[2], .droppedNotIncreasing, "equal time")
        XCTAssertEqual(outcomes[3], .droppedNotIncreasing, "earlier time")
        XCTAssertEqual(outcomes[4], .droppedNotIncreasing, "before the first frame")
        XCTAssertTrue(zip(ticks, ticks.dropFirst()).allSatisfy { (p: (Int64, Int64)) -> Bool in p.1 > p.0 })
    }

    func testCandidateNotMarkedDoesNotAdvance() {
        var timeline = RecordingTimeline()
        guard case .candidate(let first) = timeline.admit(presentationNanoseconds: 0) else { return XCTFail("first") }
        timeline.markWritten(tick: first)
        // A candidate the queue dropped is not marked: the next frame is measured from the last written one.
        XCTAssertEqual(timeline.admit(presentationNanoseconds: ns30), .candidate(tick: 20))
        XCTAssertEqual(timeline.admit(presentationNanoseconds: 2 * ns30), .candidate(tick: 40))
        timeline.markWritten(tick: 40)
        timeline.markWritten(tick: 30)   // smaller: ignored
        XCTAssertEqual(timeline.lastWrittenTick, 40)
        XCTAssertEqual(timeline.writtenCount, 2)
    }

    func testDurationLimit() {
        let settings = RecordingSettings(maxDurationSeconds: 2)
        let (ticks, outcomes) = run((0..<90).map { (k: Int) -> UInt64 in UInt64(k) * 1_000_000_000 / 30 }, settings: settings)
        XCTAssertEqual(ticks.count, 60)
        XCTAssertEqual(ticks.last, 1180)
        XCTAssertEqual(outcomes[60], .durationReached)
    }

    // MARK: Gate (REC-003-R7)

    func testGateRefusesAtCapacityWithoutWaiting() {
        let gate = RecordingFrameGate(capacity: 3)
        XCTAssertTrue(gate.tryAcquire())
        XCTAssertTrue(gate.tryAcquire())
        XCTAssertTrue(gate.tryAcquire())
        XCTAssertFalse(gate.tryAcquire(), "the fourth frame is refused")
        XCTAssertEqual(gate.inFlight, 3)
        gate.release()
        XCTAssertTrue(gate.tryAcquire(), "a released slot reopens")
        XCTAssertEqual(gate.maxInFlight, 3)
        for _ in 0..<5 { gate.release() }
        XCTAssertEqual(gate.inFlight, 0, "never negative")
    }

    func testStatisticsSumDropsButNotRateSkips() {
        var s = RecordingStatistics()
        s.droppedBusy = 2
        s.droppedNotReady = 1
        s.droppedNotIncreasing = 3
        s.skippedRate = 40
        XCTAssertEqual(s.dropped, 6)
    }

    // MARK: Refusals and notices (REC-003-R11, R12)

    func testRefusalOrder() {
        XCTAssertEqual(RecordingGate.refusal(visualAvailable: false, recordable: false, outputLive: false, paused: true, busy: true), .busy)
        XCTAssertEqual(RecordingGate.refusal(visualAvailable: false, recordable: true, outputLive: true, paused: false, busy: false), .noVisual)
        XCTAssertEqual(RecordingGate.refusal(visualAvailable: true, recordable: false, outputLive: false, paused: true, busy: false), .notRecordable)
        XCTAssertEqual(RecordingGate.refusal(visualAvailable: true, recordable: true, outputLive: false, paused: true, busy: false), .outputBlackedOut)
        XCTAssertEqual(RecordingGate.refusal(visualAvailable: true, recordable: true, outputLive: true, paused: true, busy: false), .paused)
        XCTAssertNil(RecordingGate.refusal(visualAvailable: true, recordable: true, outputLive: true, paused: false, busy: false))
        XCTAssertEqual(RecordingRefusal.outputBlackedOut.notice, "Restore the output to record.")
        XCTAssertEqual(RecordingRefusal.paused.notice, "Resume to record.")
    }

    func testEveryStopExceptTheUsersHasANotice() {
        for reason in RecordingStopReason.allCases {
            XCTAssertEqual(reason.notice == nil, reason == .user, "\(reason)")
        }
        XCTAssertEqual(RecordingFailure.tooFewFrames.notice, "Nothing was recorded.")
        XCTAssertEqual(RecordingFailure.writerFailed("x").notice, "The recording couldn't be finished.")
    }

    func testBitRates() {
        XCTAssertEqual(RecordingCodec.h264.averageBitRate(width: 1920, height: 1080, frameRate: 30), 12_441_600)
        XCTAssertEqual(RecordingCodec.hevc.averageBitRate(width: 160, height: 120, frameRate: 30), 1_000_000, "floor")
        XCTAssertEqual(RecordingCodec.hevc.fourCharacterCode, "hvc1")
        XCTAssertEqual(RecordingCodec.h264.fourCharacterCode, "avc1")
    }
}
