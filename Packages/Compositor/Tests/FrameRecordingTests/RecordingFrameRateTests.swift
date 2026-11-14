// RecordingFrameRateTests.swift — REC-006-T04, T12: the frame grid's decimation and drop rules (contract
// C1, C2) and the rate availability and resolution with injected capabilities (C3, C4). Plain Swift; runs on
// the Mac host and in the Linux shape. Shared helpers (`FrameTimes`, `GridRun`) are used by the GPU fixture.
import FrameRecording
import XCTest

/// Injected frame-time patterns (research REC-006-D8). Times are nanoseconds from 0.
enum FrameTimes {
    static let second: UInt64 = 1_000_000_000

    /// A steady loop at `hz` for `seconds`.
    static func steady(hz: UInt64, seconds: Double = 1) -> [UInt64] {
        let count = Int(Double(hz) * seconds)
        return (0..<count).map { (k: Int) -> UInt64 in UInt64(k) * second / hz }
    }

    /// A steady loop with each time moved by a pseudo-random offset in ±`jitterMicroseconds` (fixed seed).
    static func jittery(hz: UInt64, jitterMicroseconds: Int64, seconds: Double = 1, seed: UInt64 = 0x5EED) -> [UInt64] {
        var state: UInt64 = seed
        let span: UInt64 = UInt64(2 * jitterMicroseconds + 1)
        return steady(hz: hz, seconds: seconds).enumerated().map { (pair: (offset: Int, element: UInt64)) -> UInt64 in
            guard pair.offset > 0 else { return 0 }   // the first frame is the origin
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let micro: Int64 = Int64((state >> 33) % span) - jitterMicroseconds
            return UInt64(Int64(pair.element) + micro * 1_000)
        }
    }

    /// 60 Hz with no frame strictly between `at` and `at + 200 ms` (one 200 ms stall).
    static func stalled(at: UInt64 = 400_000_000, stall: UInt64 = 200_000_000, seconds: Double = 1) -> [UInt64] {
        steady(hz: 60, seconds: seconds).filter { (t: UInt64) -> Bool in t <= at || t >= at + stall }
    }

    /// Slots on the `fps` grid between the first and last frame whose half-interval window holds no frame.
    static func emptyWindows(_ times: [UInt64], fps: Int) -> Int {
        guard let first = times.first, let last = times.last else { return 0 }
        let f = UInt64(fps)
        let slot: (UInt64) -> UInt64 = { (t: UInt64) -> UInt64 in ((t - first) * f + second / 2) / second }
        let covered: Set<UInt64> = Set(times.map(slot))
        return (0...slot(last)).filter { (n: UInt64) -> Bool in !covered.contains(n) }.count
    }
}

/// Drives a timeline with every candidate written (no queue), the way `MetalFrameRecorder` does.
struct GridRun {
    var ticks: [Int64] = []
    var frames: [Int] = []
    let interval: Int64

    init(_ times: [UInt64], fps: Int) {
        let settings = RecordingSettings(maxFrameRate: fps)
        interval = settings.frameIntervalTicks
        var timeline = RecordingTimeline(settings: settings)
        for (k, t) in times.enumerated() {
            if case .candidate(let tick) = timeline.admit(presentationNanoseconds: t) {
                timeline.markWritten(tick: tick)
                ticks.append(tick)
                frames.append(k)
            }
        }
    }

    /// Contract C2: empty slots between written frames.
    var dropped: Int {
        zip(ticks, ticks.dropFirst()).reduce(0) { (sum: Int, p: (Int64, Int64)) -> Int in sum + Int((p.1 - p.0) / interval - 1) }
    }
}

/// Injected capabilities (REC-006-S4).
private struct RateCapabilities: RecordingEncoderCapabilities {
    var maxFramesPerSecond = 60
    var renderLimit: RecordingRenderLimit? = nil
    var encoderLimit = 60
    var hevc = true

    func canEncode(_ codec: RecordingCodec, width: Int, height: Int) -> Bool { codec == .hevc ? hevc : true }
    func maxEncodedFramesPerSecond(_ codec: RecordingCodec, width: Int, height: Int) -> Int { encoderLimit }
}

final class RecordingFrameRateTests: XCTestCase {
    private let phone = (width: 1206, height: 2622)

    // MARK: Grid and decimation (REC-006-R2, R3, S3)

    /// 60 Hz into 24 fps: every slot gets the rendered frame nearest it (ties to the earlier), found by brute force.
    func testSixtyToTwentyFourPicksTheNearestFrames() {
        let times = FrameTimes.steady(hz: 60, seconds: 2)
        let run = GridRun(times, fps: 24)
        XCTAssertEqual(run.ticks, (0..<run.ticks.count).map { (n: Int) -> Int64 in Int64(n) * 25 }, "every slot, exactly n/24 s")
        XCTAssertEqual(run.ticks.count, 48)
        for (n, chosen) in run.frames.enumerated() {
            let slotScaled = UInt64(n) * FrameTimes.second            // slot time × 24
            let distance: (Int) -> UInt64 = { (k: Int) -> UInt64 in
                let scaled = times[k] * 24
                return scaled > slotScaled ? scaled - slotScaled : slotScaled - scaled
            }
            // The earliest frame within 1 µs of the minimum distance: the injected times are truncated to whole
            // nanoseconds, so k/60 s frames that tie exactly differ here by a few nanoseconds.
            let best: UInt64 = times.indices.map(distance).min()!
            let nearest = times.indices.first { (k: Int) -> Bool in distance(k) <= best + 1_000 * 24 }!
            XCTAssertEqual(chosen, nearest, "slot \(n)")
        }
        // The pattern alternates 2 and 3 render frames per slot (not every other frame).
        let steps = zip(run.frames, run.frames.dropFirst()).map { (p: (Int, Int)) -> Int in p.1 - p.0 }
        XCTAssertEqual(Set(steps), [2, 3])
    }

    func testSteadyRenderingAtOrAboveTheTargetDropsNothing() {
        for fps in RecordingFrameRateChoice.supportedRates {
            for hz: UInt64 in [60, 120] {
                let run = GridRun(FrameTimes.steady(hz: hz), fps: fps)
                XCTAssertEqual(run.dropped, 0, "\(hz) Hz → \(fps) fps")
                XCTAssertEqual(run.ticks.count, fps, "\(hz) Hz → \(fps) fps: one second")
                XCTAssertTrue(run.ticks.allSatisfy { (t: Int64) -> Bool in t % run.interval == 0 })
            }
        }
    }

    func testJitteryRenderingDropsAtMostOnePercent() {
        let patterns: [(String, [UInt64])] = [("120 Hz ±2 ms", FrameTimes.jittery(hz: 120, jitterMicroseconds: 2_000, seconds: 4)),
                                              ("60 Hz ±3 ms", FrameTimes.jittery(hz: 60, jitterMicroseconds: 3_000, seconds: 4))]
        for (name, times) in patterns {
            for fps in RecordingFrameRateChoice.supportedRates where !(name.hasPrefix("60") && fps == 60) {
                let run = GridRun(times, fps: fps)
                let slots = Int(run.ticks.last! / run.interval) + 1
                XCTAssertLessThanOrEqual(Double(run.dropped), Double(slots) * 0.01, "\(name) → \(fps) fps: \(run.dropped) of \(slots)")
                XCTAssertTrue(zip(run.ticks, run.ticks.dropFirst()).allSatisfy { (p: (Int64, Int64)) -> Bool in p.1 > p.0 })
            }
        }
        // 60 Hz ±3 ms into 60 fps: some intervals exceed a slot, so drops are bounded by the empty windows (+1 per gap).
        let times = FrameTimes.jittery(hz: 60, jitterMicroseconds: 3_000, seconds: 4)
        let run = GridRun(times, fps: 60)
        XCTAssertLessThanOrEqual(run.dropped, 2 * FrameTimes.emptyWindows(times, fps: 60) + 2)
    }

    /// REC-006-S2: a 200 ms stall drops its empty slots (or one more) and never more than ⌈0.2 × fps⌉.
    func testAStallDropsItsEmptySlots() {
        let times = FrameTimes.stalled()
        let expected: [Int: Int] = [24: 3, 30: 5, 60: 11]   // empty windows, worked out in research REC-006-D8
        for fps in RecordingFrameRateChoice.supportedRates {
            let run = GridRun(times, fps: fps)
            let empty = FrameTimes.emptyWindows(times, fps: fps)
            XCTAssertEqual(empty, expected[fps], "\(fps) fps")
            XCTAssertGreaterThanOrEqual(run.dropped, empty, "\(fps) fps")
            XCTAssertLessThanOrEqual(run.dropped, empty + 1, "\(fps) fps")
            XCTAssertLessThanOrEqual(run.dropped, (fps * 200 + 999) / 1000, "\(fps) fps: ⌈0.2 × fps⌉")
        }
    }

    func testSlowerRenderingCountsEveryEmptySlot() {
        let run = GridRun(FrameTimes.steady(hz: 30), fps: 60)
        XCTAssertEqual(run.ticks.count, 30)
        XCTAssertEqual(run.dropped, 29, "every other 60 fps slot between the first and last frame is empty")
    }

    // MARK: Choice

    func testChoiceValues() {
        XCTAssertEqual(RecordingFrameRateChoice.allCases.map(\.rawValue), ["profile", "24", "30", "60"])
        XCTAssertEqual(RecordingFrameRateChoice.defaultChoice, .profileDefault)
        XCTAssertNil(RecordingFrameRateChoice(rawValue: "25"))
        XCTAssertEqual(RecordingFrameRateChoice(rate: 30), .fps30)
        XCTAssertEqual(RecordingFrameRateChoice.profileDefault.title(profileRate: 60), "Profile default (60 fps)")
        XCTAssertEqual(RecordingFrameRateChoice.fps24.title(profileRate: 60), "24 fps")
        XCTAssertEqual(RecordingSettings(maxFrameRate: 24).frameIntervalTicks, 25)
    }

    func testExplicitRateChangesOnlyTheRate() {
        let high = RecordingQualityProfile.high.settings(frameRate: 24)
        XCTAssertEqual(high.maxFrameRate, 24)
        XCTAssertEqual(high.fixedBitRate, 20_000_000, "fixed bit rates stay (REC-006-R12)")
        XCTAssertEqual(high.maxLongSide, 2560)
        XCTAssertEqual(RecordingQualityProfile.standard.settings(frameRate: nil), .standard)
        let standard24 = RecordingQualityProfile.standard.settings(frameRate: 24)
        XCTAssertEqual(standard24.averageBitRate(codec: .hevc, width: 1080, height: 1920), 5_971_968, "per-pixel rule at 24 fps")
    }

    // MARK: Availability (REC-006-R6, S4)

    func testUnsupportedRatesAreDisabledWithTheirReason() {
        let cases: [(RateCapabilities, String)] = [
            (RateCapabilities(maxFramesPerSecond: 30), "This display shows at most 30 fps."),
            (RateCapabilities(renderLimit: RecordingRenderLimit(reason: .lowPowerMode)), "Low Power Mode limits the visual to 30 fps."),
            (RateCapabilities(renderLimit: RecordingRenderLimit(reason: .thermal)), "The device is too warm; the visual is limited to 30 fps."),
            (RateCapabilities(renderLimit: RecordingRenderLimit(reason: .batterySaver)), "Battery saver limits the visual to 30 fps."),   // PERF-008-R8
            (RateCapabilities(encoderLimit: 30), "This device encodes at most 30 fps at 1178×2560."),
        ]
        for (caps, text) in cases {
            let rows = RecordingFrameRateChoice.allCases.map { (c: RecordingFrameRateChoice) -> RecordingFrameRateAvailability in
                RecordingFrameRateCatalog.availability(of: c, profile: .high, drawableWidth: phone.width, drawableHeight: phone.height,
                                                       capabilities: caps)
            }
            XCTAssertEqual(rows[0], .available, "Profile default stays selectable: \(text)")
            XCTAssertEqual(rows[1], .available, text)
            XCTAssertEqual(rows[2], .available, text)
            XCTAssertEqual(rows[3].reason?.text, text)
        }
        let all = RecordingFrameRateChoice.allCases.allSatisfy { (c: RecordingFrameRateChoice) -> Bool in
            RecordingFrameRateCatalog.availability(of: c, profile: .standard, drawableWidth: phone.width, drawableHeight: phone.height,
                                                   capabilities: RateCapabilities()).isAvailable
        }
        XCTAssertTrue(all, "a 60 fps display without caps offers every rate")
    }

    // MARK: Resolution (REC-006-R7, contract C4)

    func testExplicitRateFallsBackWithANotice() {
        let caps = RateCapabilities(renderLimit: RecordingRenderLimit(reason: .lowPowerMode))
        let r = RecordingFrameRateCatalog.resolve(profile: .standard, choice: .fps60, drawableWidth: phone.width,
                                                  drawableHeight: phone.height, capabilities: caps)
        XCTAssertEqual(r.plan?.settings.maxFrameRate, 30)
        XCTAssertEqual(r.plan?.profile, .standard)
        XCTAssertEqual(r.notice, "Recording at 30 fps: Low Power Mode limits the visual to 30 fps.")
        let ok = RecordingFrameRateCatalog.resolve(profile: .high, choice: .fps24, drawableWidth: phone.width,
                                                   drawableHeight: phone.height, capabilities: RateCapabilities(maxFramesPerSecond: 30))
        XCTAssertEqual(ok.plan?.profile, .high, "an explicit 24 makes High recordable on a 30 fps display")
        XCTAssertEqual(ok.plan?.settings.maxFrameRate, 24)
        XCTAssertNil(ok.notice)
    }

    func testProfileDefaultKeepsREC005AndAppliesTheRenderCap() {
        let thirty = RecordingFrameRateCatalog.resolve(profile: .high, choice: .profileDefault, drawableWidth: phone.width,
                                                       drawableHeight: phone.height, capabilities: RateCapabilities(maxFramesPerSecond: 30))
        XCTAssertEqual(thirty.plan?.profile, .standard, "REC-005's profile fallback on a 30 fps display")
        XCTAssertNil(thirty.rateFallback)
        XCTAssertEqual(thirty.notice, "Recording at Standard: Needs 60 fps; this display shows at most 30.")
        let lowPower = RecordingFrameRateCatalog.resolve(profile: .high, choice: .profileDefault, drawableWidth: phone.width,
                                                         drawableHeight: phone.height,
                                                         capabilities: RateCapabilities(renderLimit: RecordingRenderLimit(reason: .lowPowerMode)))
        XCTAssertEqual(lowPower.plan?.profile, .high)
        XCTAssertEqual(lowPower.plan?.settings.maxFrameRate, 30)
        XCTAssertEqual(lowPower.notice, "Recording at 30 fps: Low Power Mode limits the visual to 30 fps.")
        let plain = RecordingFrameRateCatalog.resolve(profile: .high, choice: .profileDefault, drawableWidth: phone.width,
                                                      drawableHeight: phone.height, capabilities: RateCapabilities())
        XCTAssertEqual(plain.plan?.settings, RecordingQualityCatalog.availability(of: .high, drawableWidth: phone.width,
                                                                                  drawableHeight: phone.height,
                                                                                  capabilities: RateCapabilities()).plan?.settings)
        XCTAssertNil(plain.notice)
    }

    func testEncoderLimitAndBothNotices() {
        let caps = RateCapabilities(encoderLimit: 30, hevc: false)
        let r = RecordingFrameRateCatalog.resolve(profile: .max, choice: .fps60, drawableWidth: phone.width,
                                                  drawableHeight: phone.height, capabilities: caps)
        XCTAssertEqual(r.plan?.profile, .standard)
        XCTAssertEqual(r.plan?.settings.maxFrameRate, 30)
        XCTAssertEqual(r.notice, "Recording at Standard: Needs HEVC, which this device cannot encode. "
                       + "Recording at 30 fps: This device encodes at most 30 fps at 884×1920.")
    }
}
