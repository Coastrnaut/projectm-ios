// ParticleTrailModelTests.swift — VIS-010-T03: the trail model on the CPU (VIS-010-R4 to R7, S1 to S3): frame-rate
// independent decay, half-lives, the 0.8 cap under continuous emission, the cut to exact 0, the envelope bound's
// recurrence, and the CPU half of the 10-minute fixture (36 000 frames at 60 Hz, fixed storage). Pure Swift: runs on
// Linux too. Clocks are injected (frame counts × frame durations).
import FlashSafety
import XCTest
@testable import VisualGenerators

final class ParticleTrailModelTests: XCTestCase {
    func testHalfLivesFollowLengthReduceMotionAndReduceFlashing() {
        XCTAssertEqual(ParticleTrails.halfLife(.off, reduceMotion: false, reduceFlashing: false), 0)
        XCTAssertEqual(ParticleTrails.halfLife(.short, reduceMotion: false, reduceFlashing: false), 0.1)
        XCTAssertEqual(ParticleTrails.halfLife(.long, reduceMotion: false, reduceFlashing: false), 0.3)
        XCTAssertEqual(ParticleTrails.halfLife(.short, reduceMotion: true, reduceFlashing: false), 0.05, "Reduce Motion: shorter")
        XCTAssertEqual(ParticleTrails.halfLife(.long, reduceMotion: false, reduceFlashing: true), 0.25, "Reduce flashing cap")
        XCTAssertEqual(ParticleTrails.halfLife(.long, reduceMotion: true, reduceFlashing: true), 0.15, accuracy: 1e-12)
        XCTAssertEqual(ParticleTrails.decay(frameDuration: 1.0 / 60, halfLife: 0), 0, "off: no history")
        XCTAssertEqual(ParticleTrails.decay(frameDuration: 0, halfLife: 0.3), 0.99, "0 s frame: the ceiling")
        XCTAssertEqual(ParticleTrails.decay(frameDuration: .nan, halfLife: 0.3), 0.99)
        XCTAssertEqual(ParticleTrails.decay(frameDuration: 5, halfLife: 0.1), 0.5, accuracy: 1e-12, "frame time clamped to 0.1 s")
    }

    /// A streak's value `seconds` after one stamp of `value`, at `fps`.
    private func streak(fps: Double, seconds: Double, length: ParticleTrailLength, value: Float = 0.8) -> Float {
        let model = ParticleTrailModel(width: 4, height: 4)
        let dt = 1 / fps
        let h = ParticleTrails.halfLife(length, reduceMotion: false, reduceFlashing: false)
        model.beginFrame(decay: ParticleTrails.decay(frameDuration: dt, halfLife: h))
        model.stamp(x0: 1, y0: 1, x1: 2, y1: 2, color: SIMD4<Float>(repeating: value))
        let frames = Int((seconds * fps).rounded())
        for _ in 0..<frames { model.beginFrame(decay: ParticleTrails.decay(frameDuration: dt, halfLife: h)) }
        return model.value(x: 1, y: 1).x
    }

    func testDecayIsFrameRateIndependent() {
        for length in [ParticleTrailLength.short, .long] {
            let h = length.halfLifeSeconds
            let expected = Float(0.8 * pow(0.5, 0.5 / h))
            let at30 = streak(fps: 30, seconds: 0.5, length: length)
            let at120 = streak(fps: 120, seconds: 0.5, length: length)
            XCTAssertEqual(at30, at120, accuracy: 0.01, "\(length): 30 vs 120 fps at 0.5 s (VIS-010-S2)")
            XCTAssertEqual(at30, expected, accuracy: 0.002, "\(length): halves every half-life")
            XCTAssertEqual(at120, expected, accuracy: 0.002)
        }
    }

    func testTrailsFadeToExactlyZeroAndResetClears() {
        XCTAssertEqual(streak(fps: 60, seconds: 1.5, length: .short), 0, "below 1/512 is cut to 0")
        let model = ParticleTrailModel(width: 2, height: 2)
        model.beginFrame(decay: 0.9)
        model.stamp(x0: 0, y0: 0, x1: 2, y1: 2, color: SIMD4<Float>(0.5, 0.25, 0.1, 0.5))
        model.reset()
        model.beginFrame(decay: 0.9)
        XCTAssertEqual(model.maximumChannel, 0, "a reset frame shows no history")
        XCTAssertEqual(ParticleTrails.accumulate(particle: SIMD4<Float>(0.2, 0, 0, 0.2), previous: SIMD4<Float>(repeating: 0.7),
                                                 decay: 0.5, reset: true), SIMD4<Float>(0.2, 0, 0, 0.2))
        XCTAssertEqual(ParticleTrails.accumulate(particle: .zero, previous: SIMD4<Float>(.nan, .infinity, -1, 0.6),
                                                 decay: 0.5, reset: false), SIMD4<Float>(0, 0, 0, 0.3), "non-finite never enters")
    }

    func testCapHoldsUnderContinuousEmission() {
        let model = ParticleTrailModel(width: 16, height: 16)
        var peak: Float = 0
        for f in 0..<600 {   // 10 s of continuous emission at 60 Hz with over-bright input, Long trails at the ceiling
            model.beginFrame(decay: ParticleTrails.maximumDecay)
            let x = f % 16
            model.stamp(x0: x, y0: 0, x1: x + 4, y1: 16, color: SIMD4<Float>(2, 1.5, 1, 1))
            model.stamp(x0: 0, y0: x, x1: 16, y1: x + 2, color: SIMD4<Float>(0.9, 0.9, 0.9, 0.9))
            peak = max(peak, model.maximumChannel)
        }
        XCTAssertLessThanOrEqual(peak, ParticleTrails.cap, "VIS-010-S3: no accumulated value above 0.8")
        XCTAssertEqual(peak, ParticleTrails.cap, "the cap is reached, so the test exercises it")
    }

    /// VIS-010-S1, CPU half: 10 minutes at 60 Hz (36 000 frames) with moving stamps, resets (as on resizes) and length
    /// changes; the two buffers keep their addresses and the values stay within the cap.
    func testTenMinuteFixtureKeepsFixedStorage() {
        let model = ParticleTrailModel(width: 16, height: 16)
        let addresses = model.storageAddresses
        let lengths: [ParticleTrailLength] = [.long, .short, .long, .short]
        let dt = 1.0 / 60
        var peak: Float = 0
        for f in 0..<36_000 {
            if f % 6_000 == 0 { model.reset() }   // a resize or restart every 100 s
            let length = lengths[(f / 9_000) % lengths.count]
            let h = ParticleTrails.halfLife(length, reduceMotion: f % 18_000 > 12_000, reduceFlashing: false)
            model.beginFrame(decay: ParticleTrails.decay(frameDuration: dt, halfLife: h))
            let x = (f / 3) % 16
            model.stamp(x0: x, y0: x / 2, x1: x + 2, y1: x / 2 + 2, color: SIMD4<Float>(0.8, 0.4, 0.2, 0.8))
            if f % 600 == 0 {
                XCTAssertEqual(model.storageAddresses, addresses)
                peak = max(peak, model.maximumChannel)
            }
        }
        XCTAssertEqual(model.storageAddresses, addresses, "no buffer was replaced in 10 minutes")
        XCTAssertLessThanOrEqual(peak, ParticleTrails.cap)
    }

    func testFlashBoundRecurrenceAndGainScaling() {
        let bound = ParticleTrailFlashBound()
        var particles = [FlashLevels](repeating: FlashLevels(luminance: 0.35, redness: 0.05), count: FlashZones.count)
        let background = FlashLevels(luminance: 0.05, redness: 0)
        for _ in 0..<200 {
            particles.withUnsafeBufferPointer { (p: UnsafeBufferPointer<FlashLevels>) -> Void in
                bound.advance(decay: 0.5, particleLevels: p, background: background)
            }
        }
        // A = 0.3 + 0.5 A → 0.6; redness 0.05 / 0.5 = 0.1.
        XCTAssertEqual(bound.accumulated[FlashZones.wholeFrame].luminance, 0.6, accuracy: 1e-9)
        XCTAssertEqual(bound.accumulated[3].redness, 0.1, accuracy: 1e-9)
        XCTAssertEqual(bound.shown(0, decay: 0.5).luminance, 0.3, accuracy: 1e-9)
        var out = [FlashLevels](repeating: FlashLevels(luminance: 0.1, redness: 0), count: FlashZones.count)
        out.withUnsafeMutableBufferPointer { (o: inout UnsafeMutableBufferPointer<FlashLevels>) -> Void in
            bound.add(gain: 0.5, decay: 0.5, into: o)
        }
        XCTAssertEqual(out[0].luminance, 0.1 + 0.5 * 0.3, accuracy: 1e-9, "the gain scales the trail")
        particles = [FlashLevels](repeating: FlashLevels(luminance: 0.9, redness: 0.9), count: FlashZones.count)
        particles.withUnsafeBufferPointer { (p: UnsafeBufferPointer<FlashLevels>) -> Void in
            bound.advance(decay: 0.99, particleLevels: p, background: .zero)
        }
        XCTAssertEqual(bound.accumulated[0].luminance, Double(ParticleTrails.cap), "capped at 0.8")
        bound.reset()
        XCTAssertEqual(bound.accumulated[0], .zero)
    }
}
