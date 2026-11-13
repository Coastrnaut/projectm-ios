// CMP-003-T06 (US2: fades; CMP-003-R5 to R7, R10; S3). CPU only: runs on the Mac host and in the
// Linux shape. Time is a fixed sequence of frame durations (no wall clock).
import Compositor
import XCTest

final class LayerOpacityAnimatorTests: XCTestCase {
    private let frame = 1.0 / 60

    /// Runs `frames` frames of `frame` seconds and returns the values shown.
    private func run(_ animator: inout LayerOpacityAnimator, frames: Int, dt: Double? = nil) -> [Double] {
        (0..<frames).map { (_: Int) -> Double in animator.advance(by: dt ?? frame) }
    }

    private func assertMonotonic(_ values: [Double], increasing: Bool, _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertTrue(increasing ? b >= a : b <= a, "\(message): \(a) then \(b)", file: file, line: line)
        }
    }

    func testLinearFadeEndsExactlyAndIsMonotonic() throws {
        var a = LayerOpacityAnimator(opacity: 0)
        XCTAssertEqual(a.value, 0)
        XCTAssertFalse(a.isAnimating)
        try a.setOpacity(1, duration: 1, curve: .linear)
        XCTAssertEqual(a.value, 0, "the fade starts from the shown value")
        XCTAssertTrue(a.isAnimating)
        let values = run(&a, frames: 70)
        assertMonotonic([0] + values, increasing: true, "linear rise")
        XCTAssertEqual(values[29], 0.5, accuracy: 1e-9, "half way after 0.5 s")
        // 60 frames of 1/60 s sum to 1 s give or take one rounding unit; from frame 61 on it is exact.
        for v in values[60...] { XCTAssertEqual(v, 1, "exactly the target once the duration has elapsed") }
        XCTAssertFalse(a.isAnimating)
        XCTAssertEqual(a.target, 1)
    }

    func testEaseInOutEndsExactlyIsMonotonicAndSlowAtTheEnds() throws {
        var a = LayerOpacityAnimator(opacity: 1)
        try a.setOpacity(0, duration: 1, curve: .easeInOut)
        let eased = run(&a, frames: 61)
        var l = LayerOpacityAnimator(opacity: 1)
        try l.setOpacity(0, duration: 1, curve: .linear)
        let linear = run(&l, frames: 61)
        assertMonotonic([1] + eased, increasing: false, "ease-in-out fall")
        XCTAssertEqual(eased[60], 0, "exact end")
        XCTAssertGreaterThan(eased[5], linear[5], "slower than linear near the start (falling: stays higher)")
        XCTAssertLessThan(eased[54], linear[54], "slower than linear near the end (falling: already lower)")
        XCTAssertEqual(eased[29], 0.5, accuracy: 1e-9, "symmetric: half way at half time")
    }

    func testRetargetStartsFromTheShownValue() throws {
        var a = LayerOpacityAnimator(opacity: 0)
        try a.setOpacity(1, duration: 1)
        _ = run(&a, frames: 24)   // 0.4 s
        let shown = a.value
        XCTAssertEqual(shown, 0.4, accuracy: 1e-9)
        try a.setOpacity(0, duration: 0.5, curve: .easeInOut)
        XCTAssertEqual(a.value, shown, "no jump at the retarget")
        let next = a.advance(by: frame)
        XCTAssertLessThan(next, shown)
        XCTAssertGreaterThan(next, shown - 0.05, "continuous: one frame's progress")
        let rest = run(&a, frames: 40)
        assertMonotonic([shown, next] + rest, increasing: false, "towards the new target")
        XCTAssertEqual(rest.last, 0)
    }

    func testZeroDurationIsImmediate() throws {
        var a = LayerOpacityAnimator(opacity: 1)
        try a.setOpacity(0.25, duration: 0)
        XCTAssertEqual(a.value, 0.25)
        XCTAssertFalse(a.isAnimating)
        XCTAssertEqual(a.advance(by: frame), 0.25)
        a.setOpacity(0.75, transition: .immediate)
        XCTAssertEqual(a.advance(by: 0), 0.75)
    }

    func testInvalidRequestsAreRefusedAndChangeNothing() throws {
        var a = LayerOpacityAnimator(opacity: 0.5)
        let before = a
        XCTAssertThrowsError(try a.setOpacity(.nan, duration: 1)) { XCTAssertEqual($0 as? LayerOpacityError, .nonFiniteTarget) }
        XCTAssertThrowsError(try a.setOpacity(.infinity, duration: 1)) { XCTAssertEqual($0 as? LayerOpacityError, .nonFiniteTarget) }
        XCTAssertThrowsError(try a.setOpacity(1, duration: -0.1)) { XCTAssertEqual($0 as? LayerOpacityError, .negativeDuration) }
        XCTAssertThrowsError(try a.setOpacity(1, duration: .infinity)) { XCTAssertEqual($0 as? LayerOpacityError, .nonFiniteDuration) }
        XCTAssertThrowsError(try LayerOpacityTransition(duration: .nan)) { XCTAssertEqual($0 as? LayerOpacityError, .nonFiniteDuration) }
        XCTAssertEqual(a, before, "refusals change nothing")
        a.setOpacity(.nan, transition: .immediate)
        XCTAssertEqual(a, before, "a non-finite target through a transition is ignored")
    }

    func testOutOfRangeTargetsAreClampedAndBadFrameTimesDoNotMove() throws {
        var a = LayerOpacityAnimator(opacity: 2)
        XCTAssertEqual(a.value, 1, "init clamps")
        XCTAssertEqual(LayerOpacityAnimator(opacity: .nan).value, 1, "non-finite reads 1 (LayerCompositeSettings' rule)")
        try a.setOpacity(-3, duration: 0)
        XCTAssertEqual(a.value, 0)
        try a.setOpacity(7, duration: 1)
        XCTAssertEqual(a.target, 1)
        XCTAssertEqual(a.advance(by: -1), 0, "negative frame time does not move")
        XCTAssertEqual(a.advance(by: .nan), 0, "non-finite frame time does not move")
        XCTAssertEqual(a.advance(by: 0.25), 0.25, accuracy: 1e-12)
    }

    func testStackSetSettingsChangesOnlyThatEntry() throws {
        let kind = LayerKind("test.opacity")
        var stack = LayerStack()
        let a = try stack.add(LayerDescriptor(kind: kind))
        let b = try stack.add(LayerDescriptor(kind: kind))
        try stack.setSettings(LayerCompositeSettings(opacity: 0.3), of: b)
        XCTAssertEqual(stack.entry(b)?.settings.opacity, 0.3)
        XCTAssertEqual(stack.entry(a)?.settings, LayerCompositeSettings())
        XCTAssertEqual(stack.ids, [a, b], "order unchanged")
        let before = stack
        XCTAssertThrowsError(try stack.setSettings(LayerCompositeSettings(), of: LayerInstanceID(rawValue: 99))) {
            XCTAssertEqual($0 as? LayerStackError, .unknownLayer(LayerInstanceID(rawValue: 99)))
        }
        XCTAssertEqual(stack, before, "a refusal leaves the stack unchanged")
    }

    func testAStallAdvancesByAtMostTheClockClamp() throws {
        // The compositor feeds the frame clock's durations, which clamp a stall to 0.1 s (CMP-001-R3).
        var clock = LayerFrameClock()
        var a = LayerOpacityAnimator(opacity: 0)
        try a.setOpacity(1, duration: 1)
        let times: [UInt64] = [0, 16_666_667, 2_016_666_667, 2_033_333_334]   // a 2 s stall after frame 1
        var values: [Double] = []
        for t in times {
            let f = clock.next(presentationTimeNanoseconds: t, outputWidth: 64, outputHeight: 64, contentScale: 1, reduceFlashing: false)
            values.append(a.advance(by: f.frameDuration))
        }
        XCTAssertEqual(values[0], 0, "frame 0 has duration 0")
        XCTAssertEqual(values[2] - values[1], 0.1, accuracy: 1e-9, "the stall counts as 0.1 s")
        XCTAssertLessThan(values[3], 1, "the fade is not completed by the stall")
    }
}
