// CAM-008-T02, T05, T10: the person mask's rules (policy, schedule, bitmap), the masker (bounded rate,
// one analysis in flight, failure and unsupported paths, reset, memory only) and a probe of the real
// Vision request on a synthetic still. The probe records whether Vision runs on this host or Simulator;
// it is never device evidence (research CAM-008-D8).
import CameraLayer
import XCTest

final class PersonMaskTests: XCTestCase {
    func testPolicyPausesWhenWarmAndSlowsDownWhenSavingPower() {
        XCTAssertEqual(PersonMaskPolicy.plan(thermal: .nominal, reducedPower: false), .run(quality: .balanced, stride: 2))
        XCTAssertEqual(PersonMaskPolicy.plan(thermal: .fair, reducedPower: false), .run(quality: .balanced, stride: 2))
        XCTAssertEqual(PersonMaskPolicy.plan(thermal: .nominal, reducedPower: true), .run(quality: .fast, stride: 3))
        XCTAssertEqual(PersonMaskPolicy.plan(thermal: .serious, reducedPower: false), .paused, "CAM-008-R6")
        XCTAssertEqual(PersonMaskPolicy.plan(thermal: .critical, reducedPower: true), .paused)
        for thermal in PersonMaskThermal.allCases {
            for reduced in [false, true] {
                if case let .run(quality, _) = PersonMaskPolicy.plan(thermal: thermal, reducedPower: reduced) {
                    XCTAssertNotEqual(quality, .accurate, "accurate is never used for video (D4)")
                }
            }
        }
    }

    func testScheduleStartsTheFirstPictureThenEveryStrideAndNeverTwoAtOnce() {
        var schedule = PersonMaskSchedule(stride: 2)
        var started: [Int] = []
        for picture in 1...7 {
            if schedule.offer() {
                started.append(picture)
                schedule.finish()
            }
        }
        XCTAssertEqual(started, [1, 3, 5, 7], "every second picture (CAM-008-R4)")

        var busy = PersonMaskSchedule(stride: 2)
        XCTAssertTrue(busy.offer())
        for _ in 0..<5 { XCTAssertFalse(busy.offer(), "never a second analysis in flight") }
        busy.finish()
        XCTAssertTrue(busy.offer(), "the next picture after the analysis finished")

        var three = PersonMaskSchedule(stride: 3)
        var count = 0
        for _ in 1...9 where three.offer() { count += 1; three.finish() }
        XCTAssertEqual(count, 3, "every third picture when saving power")

        var reset = PersonMaskSchedule(stride: 3)
        XCTAssertTrue(reset.offer()); reset.finish()
        XCTAssertFalse(reset.offer())
        reset.reset()
        XCTAssertTrue(reset.offer(), "after a camera switch the first picture starts at once")
    }

    func testBitmapValidationAndModes() {
        XCTAssertNil(PersonMaskBitmap(width: 2, height: 2, bytes: [0, 0, 0], space: .texture))
        XCTAssertNil(PersonMaskBitmap(width: 0, height: 2, bytes: [], space: .texture))
        let mask = try? XCTUnwrap(PersonMaskBitmap.rectangle(width: 4, height: 2, x0: 1, y0: 0, x1: 3, y1: 1))
        XCTAssertEqual(mask?.bytes, [0, 255, 255, 0, 0, 0, 0, 0])
        XCTAssertEqual(mask?.coverage(u: 0.4, v: 0.2), 1)
        XCTAssertEqual(mask?.coverage(u: 0.9, v: 0.9), 0)
        XCTAssertEqual(PersonMaskBitmap.rectangle(width: 2, height: 2, x0: 3, y0: 3, x1: 1, y1: 1)?.bytes, [0, 0, 0, 0])
        XCTAssertEqual(CameraPersonMaskMode.allCases.map(\.rawValue), ["off", "person", "background"])
        XCTAssertEqual(CameraPersonMaskMode.allCases.map(\.title), ["Off", "Person", "Background"], "CAM-008-R8")
    }
}

#if canImport(CoreVideo) && canImport(Metal) && !COMPOSITOR_NO_METAL
import CoreVideo
import os

/// Collects analysis jobs instead of running them, so a test decides when an analysis finishes.
private final class HeldJobs: @unchecked Sendable {
    private let jobs = OSAllocatedUnfairLock<[@Sendable () -> Void]>(initialState: [])
    var runner: PersonMasker.Runner {
        { [self] (job: @escaping @Sendable () -> Void) -> Void in jobs.withLock { $0.append(job) } }
    }
    var count: Int { jobs.withLock { $0.count } }
    func runAll() {
        let pending: [@Sendable () -> Void] = jobs.withLock { (j: inout [@Sendable () -> Void]) -> [@Sendable () -> Void] in
            defer { j = [] }
            return j
        }
        for job in pending { job() }
    }
}

final class PersonMaskerTests: XCTestCase {
    private let immediately: PersonMasker.Runner = { (job: @escaping @Sendable () -> Void) -> Void in job() }

    private func picture(width: Int = 8, height: Int = 6) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private var fixture: PersonMaskBitmap { PersonMaskBitmap.rectangle(width: 8, height: 6, x0: 2, y0: 1, x1: 6, y1: 5)! }

    func testAnalysesEverySecondPictureAndKeepsTheNewestMask() throws {
        let segmenter = FixturePersonSegmenter(mask: fixture)
        let masker = PersonMasker(segmenter: segmenter, runner: immediately)
        let pixels = try picture()
        masker.offer(pixels, rotation: .none, position: .back)
        XCTAssertEqual(segmenter.calls, 0, "nothing while the choice is Off")
        masker.isEnabled = true
        for _ in 0..<6 { masker.offer(pixels, rotation: .none, position: .back) }
        XCTAssertEqual(segmenter.calls, 3, "CAM-008-R4: every second picture")
        let mask = try XCTUnwrap(masker.latestMask())
        XCTAssertEqual(mask.bitmap, fixture)
        XCTAssertEqual(mask.position, .back)
        XCTAssertEqual(mask.serial, 3)
        masker.plan = PersonMaskPolicy.plan(thermal: .nominal, reducedPower: true)
        masker.reset()
        for _ in 0..<6 { masker.offer(pixels, rotation: .none, position: .back) }
        XCTAssertEqual(segmenter.calls, 5, "every third picture when saving power")
        XCTAssertEqual(masker.availability, .available)
    }

    func testOneAnalysisInFlightAndStaleResultsAreDropped() throws {
        let held = HeldJobs()
        let masker = PersonMasker(segmenter: FixturePersonSegmenter(mask: fixture), runner: held.runner)
        masker.isEnabled = true
        let pixels = try picture()
        for _ in 0..<10 { masker.offer(pixels, rotation: .none, position: .back) }
        XCTAssertEqual(held.count, 1, "never a second analysis while one is in flight")
        XCTAssertNil(masker.latestMask(), "no mask before the analysis finishes: the layer draws the Off picture")
        masker.reset()   // the camera switched while the analysis ran
        held.runAll()
        XCTAssertNil(masker.latestMask(), "a mask of the previous camera is dropped (CAM-008-R7)")
        masker.offer(pixels, rotation: .none, position: .front)
        held.runAll()
        XCTAssertEqual(masker.latestMask()?.position, .front)
        masker.isEnabled = false
        XCTAssertNil(masker.latestMask(), "turning the choice Off drops the mask")
    }

    func testFailureIsStickyAndUnsupportedNeverRuns() throws {
        let pixels = try picture()
        let failing = FixturePersonSegmenter(mask: fixture, fails: true)
        let masker = PersonMasker(segmenter: failing, runner: immediately)
        masker.isEnabled = true
        XCTAssertEqual(masker.availability, .available)
        for _ in 0..<6 { masker.offer(pixels, rotation: .none, position: .back) }
        XCTAssertEqual(failing.calls, 1, "a failed segmenter is not retried every frame")
        XCTAssertEqual(masker.availability, .failed)
        XCTAssertNil(masker.latestMask())

        let unsupported = FixturePersonSegmenter(mask: fixture, supported: false)
        let none = PersonMasker(segmenter: unsupported, runner: immediately)
        none.isEnabled = true
        for _ in 0..<4 { none.offer(pixels, rotation: .none, position: .back) }
        XCTAssertEqual(unsupported.calls, 0)
        XCTAssertEqual(none.availability, .unsupported)
    }

    @MainActor
    func testWarmDevicePausesAndCoolingResumes() throws {
        let segmenter = FixturePersonSegmenter(mask: fixture)
        let masker = PersonMasker(segmenter: segmenter, runner: immediately)
        var reported: [PersonMaskAvailability] = []
        masker.onAvailabilityChange = { (a: PersonMaskAvailability) -> Void in reported.append(a) }
        masker.isEnabled = true
        masker.plan = PersonMaskPolicy.plan(thermal: .serious, reducedPower: false)
        let pixels = try picture()
        for _ in 0..<4 { masker.offer(pixels, rotation: .none, position: .back) }
        XCTAssertEqual(segmenter.calls, 0, "CAM-008-R6: no analysis while warm")
        XCTAssertEqual(masker.availability, .paused)
        masker.plan = PersonMaskPolicy.plan(thermal: .fair, reducedPower: false)
        masker.offer(pixels, rotation: .none, position: .back)
        XCTAssertEqual(segmenter.calls, 1)
        XCTAssertEqual(reported, [.paused, .available])
    }

    /// CAM-008-S4, R7: the masking sources use no file, network, defaults or logging API.
    func testMaskingSourcesNeverStoreOrSendMasks() throws {
        let sources: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/CameraLayer")
        let forbidden: [String] = ["FileManager", "write(to", "URL" + "Session", "UserDefaults", "Logger(", "os_log", "print(", "NSLog"]
        for name in ["PersonMask.swift", "PersonMasker.swift", "PersonSegmenting.swift"] {
            let text: String = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            for word in forbidden { XCTAssertFalse(text.contains(word), "\(name) uses \(word)") }
        }
    }
}
#endif

#if canImport(Vision) && canImport(CoreVideo) && canImport(Metal) && !COMPOSITOR_NO_METAL
import CoreVideo

final class VisionPersonSegmenterProbeTests: XCTestCase {
    /// CAM-008-T10: runs the real request once on a synthetic 64 × 48 still turned a quarter. Records the
    /// outcome; passes either way (whether Vision runs here is a fact about this host, not the app).
    /// 2026-11-14: on the Mac host it ran (mask 384 × 512, upright for a quarter turn, nothing covered); on the
    /// iOS 27.2 Simulator it threw "E5RT is not supported". Neither is device evidence.
    func testVisionRequestOnASyntheticStill() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let rowBytes: Int = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<48 {
                for x in 0..<64 {
                    let v = UInt8((x * 4) & 255)
                    let i: Int = y * rowBytes + x * 4
                    bytes[i] = v; bytes[i + 1] = UInt8(y * 5); bytes[i + 2] = 128; bytes[i + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let segmenter = VisionPersonSegmenter()
        #if targetEnvironment(simulator)
        XCTAssertFalse(segmenter.isSupported, "the Simulator reports unsupported (Vision cannot run there)")
        #else
        XCTAssertTrue(segmenter.isSupported)
        #endif
        do {
            let mask = try segmenter.segment(pixels, rotation: .clockwise90, quality: .balanced)
            XCTAssertEqual(mask.bytes.count, mask.width * mask.height)
            let covered: Int = mask.bytes.filter { (b: UInt8) -> Bool in b > 127 }.count
            print("CAM-008 Vision probe: ran, mask \(mask.width)x\(mask.height), space \(mask.space), covered \(covered)")
        } catch {
            print("CAM-008 Vision probe: did not run here: \(error)")
        }
    }
}
#endif
