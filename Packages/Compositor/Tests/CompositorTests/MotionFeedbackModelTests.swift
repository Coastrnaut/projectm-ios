// FX-009-T03: the plain-Swift model of Trails (FX-009-R2, R3, R7, R13; S2, S5). CPU only; runs on Linux and on the Mac
// in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL -DANALYSIS_NO_ACCELERATE). Frame durations are injected:
// no clock is read.
import Compositor
import FlashSafety
import Foundation
import XCTest

final class MotionFeedbackModelTests: XCTestCase {
    private func on(_ halfLife: Double) -> MotionFeedback { MotionFeedback(isEnabled: true, halfLifeSeconds: halfLife) }

    /// The fade after `seconds` of frames at `fps`, multiplying the per-frame decays (what the GPU history does).
    private func fade(_ feedback: MotionFeedback, fps: Double, seconds: Double) -> Double {
        let frames: Int = Int((seconds * fps).rounded())
        let duration: Double = 1 / fps
        var level: Double = 1
        for _ in 0..<frames { level *= feedback.decay(frameDuration: duration) }
        return level
    }

    func testHalfLifeIsFrameRateIndependentAt60And120() {
        for halfLife in [0.1, 0.2, 0.5] {
            let feedback: MotionFeedback = on(halfLife)
            for fps in [60.0, 120.0] {
                let one: Double = fade(feedback, fps: fps, seconds: halfLife)
                let two: Double = fade(feedback, fps: fps, seconds: 2 * halfLife)
                XCTAssertEqual(one, 0.5, accuracy: 0.005, "one half-life at \(fps) fps, h = \(halfLife)")
                XCTAssertEqual(two, 0.25, accuracy: 0.0025, "two half-lives at \(fps) fps, h = \(halfLife)")
            }
        }
    }

    func testDecayRangeAndCeiling() {
        let longest: MotionFeedback = on(MotionFeedback.longestHalfLife)
        let at60: Double = longest.decay(frameDuration: 1.0 / 60)
        let at120: Double = longest.decay(frameDuration: 1.0 / 120)
        XCTAssertLessThanOrEqual(at60, 0.98, "inside 0…0.98 at 60 fps")
        XCTAssertEqual(at60, 0.9772, accuracy: 0.0001)
        XCTAssertEqual(at120, 0.9885, accuracy: 0.0001)
        XCTAssertEqual(longest.decay(frameDuration: 1.0 / 240), MotionFeedback.maximumDecay, "the ceiling binds above 120 fps")
        XCTAssertEqual(longest.decay(frameDuration: 0), MotionFeedback.maximumDecay, "frame 0 / a repeated time")
        XCTAssertEqual(longest.decay(frameDuration: .nan), MotionFeedback.maximumDecay, "NaN counts as 0 s")
        XCTAssertEqual(longest.decay(frameDuration: -1), MotionFeedback.maximumDecay, "negative counts as 0 s")
        XCTAssertEqual(on(0.05).decay(frameDuration: 0.1), 0.25, accuracy: 1e-12, "a stall fades by the clamped 0.1 s")
        XCTAssertEqual(MotionFeedback.off.decay(frameDuration: 1.0 / 60), 0, "inactive: no history")
    }

    func testClampingAndActivity() {
        XCTAssertFalse(MotionFeedback.off.isActive)
        XCTAssertEqual(MotionFeedback.off.halfLifeSeconds, 0.20)
        XCTAssertTrue(on(0.2).isActive)
        XCTAssertFalse(on(0).isActive)
        XCTAssertFalse(on(.nan).isActive)
        XCTAssertEqual(on(.nan).clamped.halfLifeSeconds, MotionFeedback.defaultHalfLife)
        XCTAssertEqual(on(5).clamped.halfLifeSeconds, 0.5)
        XCTAssertEqual(on(-.infinity).clamped.halfLifeSeconds, 0.05)
        XCTAssertEqual(on(0.3).clamped, on(0.3))
    }

    private func clamp(_ preset: SensorySafetyPreset, reduce: Bool = false, custom: Double = 0.5) -> SafetyClamp {
        let limits = SensorySafetyLimits(flashesPerSecond: 3, riseLimitPerSecond: nil, intensityLimit: custom)
        return SafetyClamp(profile: SensorySafetyProfile(preset: preset, custom: limits), reduceFlashingSetting: reduce)
    }

    func testSafetyCapsTheHalfLife() {
        let longest: MotionFeedback = on(0.5)
        XCTAssertEqual(longest.limited(by: .standard), longest, "Standard leaves the value unchanged")
        XCTAssertEqual(longest.limited(by: clamp(.strict)).halfLifeSeconds, 0.125, accuracy: 1e-12, "Strict: 0.25 × 0.5 s")
        XCTAssertEqual(longest.limited(by: clamp(.reduced)).halfLifeSeconds, 0.25, accuracy: 1e-12, "Reduced: 0.5 × 0.5 s")
        XCTAssertEqual(longest.limited(by: clamp(.standard, reduce: true)).halfLifeSeconds, 0.25, accuracy: 1e-12,
                       "Reduce flashing on Standard")
        XCTAssertEqual(on(0.1).limited(by: clamp(.strict)), on(0.1), "a value under the cap is kept")
        let zero: MotionFeedback = longest.limited(by: clamp(.custom, custom: 0))
        XCTAssertFalse(zero.isActive, "a Custom intensity limit of 0 turns Trails off")
        XCTAssertEqual(MotionFeedback.off.limited(by: clamp(.strict)), .off)
        // Strict's decay at 60 fps is below Standard's: shorter trails.
        XCTAssertLessThan(longest.limited(by: clamp(.strict)).decay(frameDuration: 1.0 / 60), longest.decay(frameDuration: 1.0 / 60))
    }

    func testBlendReference() {
        let red = SIMD4<Float>(1, 0, 0, 1)
        let blue = SIMD4<Float>(0, 0, 1, 1)
        XCTAssertEqual(MotionFeedback.blend(current: blue, previous: red, decay: 0.9, reset: true), blue, "reset: current only")
        let trailed: SIMD4<Float> = MotionFeedback.blend(current: blue, previous: red, decay: 0.5, reset: false)
        XCTAssertEqual(trailed, SIMD4<Float>(0.5, 0, 1, 1))
        // A still picture stays itself; the result never exceeds the brighter input.
        let grey = SIMD4<Float>(0.3, 0.3, 0.3, 0.6)
        XCTAssertEqual(MotionFeedback.blend(current: grey, previous: grey, decay: 0.99, reset: false), grey)
        var random = GradeTestRandom(seed: 9)
        for _ in 0..<2_000 {
            let a: Float = Float(random.uniform(0...1))
            let b: Float = Float(random.uniform(0...1))
            let c = SIMD4<Float>(Float(random.uniform(0...1)) * a, Float(random.uniform(0...1)) * a, Float(random.uniform(0...1)) * a, a)
            let p = SIMD4<Float>(Float(random.uniform(0...1)) * b, Float(random.uniform(0...1)) * b, Float(random.uniform(0...1)) * b, b)
            let d: Float = Float(random.uniform(0...1))
            let o: SIMD4<Float> = MotionFeedback.blend(current: c, previous: p, decay: d, reset: false)
            for k in 0..<4 { XCTAssertLessThanOrEqual(o[k], max(c[k], p[k])) }
            for k in 0..<3 { XCTAssertLessThanOrEqual(o[k], o.w, "premultiplied stays valid") }
        }
    }

    func testNonFiniteValuesDoNotSpread() {
        let nan = SIMD4<Float>(.nan, 0, 0, 1)
        let red = SIMD4<Float>(1, 0, 0, 1)
        let passed: SIMD4<Float> = MotionFeedback.blend(current: nan, previous: red, decay: 0.9, reset: false)
        XCTAssertTrue(passed.x.isNaN, "a non-finite composite pixel is passed to the output pass unchanged")
        let history = SIMD4<Float>(.infinity, .nan, -3, 7)
        let clean: SIMD4<Float> = MotionFeedback.blend(current: .zero, previous: history, decay: 0.5, reset: false)
        XCTAssertEqual(clean, SIMD4<Float>(0, 0, 0, 0.5), "non-finite history reads 0, negatives 0, alpha at most 1")
    }

    func testCodableRoundTrip() throws {
        let value: MotionFeedback = on(0.33)
        let data: Data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(MotionFeedback.self, from: data), value)
    }
}
