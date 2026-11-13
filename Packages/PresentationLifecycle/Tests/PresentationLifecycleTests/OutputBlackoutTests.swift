// OUT-010-T04, T09: the output blackout's state machine with a fake frame clock (no wall clock).
// "Within one frame" is counted in frames: the first frame after a Black out tap is black
// (OUT-010-S1). The restore fade and fast toggling are measured on a white picture with
// FlashSafety's analysis (OUT-010-S3). Pure Swift: host and Linux.
import FlashSafety
import Foundation
import PresentationLifecycle
import XCTest

final class OutputBlackoutTests: XCTestCase {
    private enum Tap { case blackOut, restore }

    /// The luminance a white picture shows under the cover (Core Animation blends encoded values:
    /// the shown encoded value is 1 − opacity).
    private static func whiteLuminance(_ blackout: OutputBlackout) -> Double {
        let e = 1 - blackout.coverOpacity
        return e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4)
    }

    /// Runs `frames` frames of `dt`; `taps(i)` happen before frame i is presented. Returns each
    /// frame's white luminance and the model after the run.
    private func run(_ start: OutputBlackout = OutputBlackout(), frames: Int, dt: Double, reduceFlashing: Bool,
                     taps: (Int, OutputBlackout) -> Tap?) -> (luminance: [Double], model: OutputBlackout) {
        var model = start
        var shown: [Double] = []
        shown.reserveCapacity(frames)
        for i in 0..<frames {
            switch taps(i, model) {
            case .blackOut?: model.blackOut()
            case .restore?: model.restore()
            case nil: break
            }
            model.advance(frameTime: dt, reduceFlashing: reduceFlashing)
            shown.append(Self.whiteLuminance(model))
        }
        return (shown, model)
    }

    // MARK: - One frame (OUT-010-R2, S1)

    func testBlackOutMakesTheNextFrameBlackFromEveryPhase() {
        let dt = 1.0 / 60
        // Phases reached by a short script; Black out is tapped between two frames.
        var fading = OutputBlackout()
        fading.blackOut(); fading.restore(); fading.advance(frameTime: 0.3, reduceFlashing: false)
        XCTAssertEqual(fading.phase, .fadingIn)
        var waiting = fading
        waiting.blackOut(); waiting.restore()
        XCTAssertEqual(waiting.phase, .restoreWaiting)
        for start in [OutputBlackout(), fading, waiting] {
            var model = start
            model.blackOut()
            XCTAssertTrue(model.isBlack, "black before the call returns (\(start.phase))")
            XCTAssertEqual(model.coverOpacity, 1)
            model.advance(frameTime: dt, reduceFlashing: false)
            XCTAssertEqual(Self.whiteLuminance(model), 0, "the next frame is black (\(start.phase))")
            XCTAssertEqual(model.phase, .blackedOut)
            XCTAssertTrue(model.isBlackoutRequested)
        }
    }

    func testEveryFrameAfterTheTapIsBlackUntilRestore() {
        // A live picture for 30 frames, Black out before frame 30, nothing else for 2 s.
        let (shown, model) = run(frames: 150, dt: 1.0 / 60, reduceFlashing: false) { (i: Int, _: OutputBlackout) -> Tap? in
            i == 30 ? .blackOut : nil
        }
        XCTAssertEqual(shown[29], 1, "live before the tap")
        XCTAssertTrue(shown[30...].allSatisfy { (l: Double) -> Bool in l == 0 }, "black from the first frame after the tap")
        XCTAssertEqual(model.phase, .blackedOut)
        XCTAssertFalse(model.needsFrames, "no frames needed while simply black")
    }

    func testRestoreNeverBrightensWithoutAFrame() {
        var model = OutputBlackout()
        model.blackOut()
        model.restore()
        XCTAssertEqual(model.phase, .fadingIn)
        XCTAssertTrue(model.isBlack, "restore alone shows nothing")
        XCTAssertTrue(model.needsFrames)
        model.restore()   // a second tap is ignored
        XCTAssertEqual(model.phase, .fadingIn)
        XCTAssertTrue(model.isBlack)
    }

    func testFrameTimesAreClamped() {
        for bad in [Double.nan, -1, .infinity, 5] {
            var model = OutputBlackout()
            model.blackOut()
            model.restore()
            model.advance(frameTime: bad, reduceFlashing: false)
            XCTAssertLessThanOrEqual(model.luminanceFactor, OutputBlackout.maxFrameTime / 1 + 1e-12,
                                     "a stall of \(bad) advances at most 0.1 s")
        }
    }

    func testCoverOpacityGivesAWhitePictureTheLuminanceFactor() {
        for f in stride(from: 0.0, through: 1.0, by: 0.05) {
            let a = OutputBlackout.coverOpacity(forLuminanceFactor: f)
            let e = 1 - a
            let l = e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4)
            XCTAssertEqual(l, f, accuracy: 1e-9, "f = \(f)")
        }
        XCTAssertEqual(OutputBlackout.coverOpacity(forLuminanceFactor: .nan), 1, "NaN reads as black")
    }

    // MARK: - Fade (OUT-010-R6)

    func testTheFadeLastsOneSecondOrFourWithReduceFlashing() {
        for (reduce, seconds) in [(false, 1.0), (true, 4.0)] {
            let dt = 1.0 / 60
            var model = OutputBlackout()
            model.blackOut()
            model.restore()
            var frames = 0
            while model.phase == .fadingIn, frames < 1_000 {
                model.advance(frameTime: dt, reduceFlashing: reduce)
                frames += 1
            }
            XCTAssertEqual(model.phase, .live)
            XCTAssertEqual(model.luminanceFactor, 1)
            XCTAssertEqual(Double(frames), seconds * 60, accuracy: 1, "reduce flashing \(reduce)")
            XCTAssertFalse(model.needsFrames, "the spacing has passed by the end of the fade")
        }
    }

    func testAWhitePictureRisesAtMostAQuarterPerSecondWithReduceFlashing() {
        for dt in [1.0 / 120, 1.0 / 60, 1.0 / 24] {
            let (shown, _) = run(frames: Int(5 / dt), dt: dt, reduceFlashing: true) { (i: Int, _: OutputBlackout) -> Tap? in
                i == 0 ? .blackOut : (i == 1 ? .restore : nil)
            }
            let report = FlashAnalysis.analyze(shown, frameTimes: Array(repeating: dt, count: shown.count), threshold: 0.10)
            XCTAssertLessThanOrEqual(report.maxRise, 0.25 * dt + 1e-9, "dt \(dt)")
            XCTAssertEqual(shown.last ?? 0, 1, accuracy: 1e-9, "fully restored")
        }
    }

    // MARK: - Restore spacing and toggling (OUT-010-R7, S3)

    func testARestoreWithinOneSecondOfTheLastWaitsBlackThenFades() {
        let dt = 1.0 / 60
        var model = OutputBlackout()
        model.blackOut()
        model.restore()                                   // start 1 at t = 0
        for _ in 0..<12 { model.advance(frameTime: dt, reduceFlashing: false) }   // 0.2 s
        model.blackOut()
        model.restore()
        XCTAssertEqual(model.phase, .restoreWaiting, "0.2 s after the last start")
        XCTAssertTrue(model.isBlackoutRequested)
        var frames = 0
        while model.phase == .restoreWaiting {
            model.advance(frameTime: dt, reduceFlashing: false)
            frames += 1
            if model.phase == .restoreWaiting { XCTAssertTrue(model.isBlack, "black while waiting") }
        }
        XCTAssertEqual(Double(frames + 12) * dt, 1, accuracy: dt + 1e-9, "the fade starts 1 s after the previous start")
        XCTAssertEqual(model.phase, .fadingIn)
        model.blackOut()
        XCTAssertTrue(model.isBlack, "Black out during a wait or fade is immediate")
    }

    func testFastestTogglingStaysWithinTheFlashBudget() {
        // Every pattern: a tap on every frame (alternating), every 0.15 s, and the adversary that
        // blacks out the moment a white picture reaches the 0.10 threshold and restores at once.
        let patterns: [(String, (Int, OutputBlackout) -> Tap?)] = [
            ("every frame", { (i: Int, _: OutputBlackout) -> Tap? in i % 2 == 0 ? .blackOut : .restore }),
            ("every 0.15 s", { (i: Int, _: OutputBlackout) -> Tap? in
                guard i % 9 == 0 else { return nil }
                return (i / 9) % 2 == 0 ? .blackOut : .restore }),
            ("adversary", { (_: Int, m: OutputBlackout) -> Tap? in
                if m.phase == .blackedOut { return .restore }
                if m.phase == .live || m.luminanceFactor >= 0.1 { return .blackOut }
                return nil }),
        ]
        for reduce in [false, true] {
            let budget = reduce ? 4 : 6
            for dt in [1.0 / 60, 1.0 / 120] {
                for (name, taps) in patterns {
                    // Frame 0 is live, so the first Black out is a counted fall.
                    let (shown, _) = run(frames: Int(6 / dt), dt: dt, reduceFlashing: reduce) { (i: Int, m: OutputBlackout) -> Tap? in
                        i == 0 ? nil : taps(i - 1, m)
                    }
                    // The envelope's 2 ms window tolerance, conservatively.
                    let report = FlashAnalysis.analyze(shown, frameTimes: Array(repeating: dt, count: shown.count),
                                                       threshold: 0.10, window: 1.002)
                    XCTAssertLessThanOrEqual(report.maxTransitionsPerWindow, 4, "\(name), dt \(dt), reduce \(reduce)")
                    XCTAssertLessThanOrEqual(report.maxTransitionsPerWindow, budget)
                    if reduce { XCTAssertLessThanOrEqual(report.maxRise, 0.25 * dt + 1e-9, "\(name): rise rate") }
                    XCTAssertGreaterThan(report.transitions, 0, "\(name): the pattern does toggle the output")
                }
            }
        }
    }
}
