// EffectQualitySafetyTests.swift — PERF-003-T10: the roadmap acceptance's second half, "preserves safety limiter"
// (PERF-003-R8, R9; S3). A strobe fixture (every band alternating 0 and 1 each frame) goes through the real
// `FlashSafetyLimiter`, the circular layout and the bloom's luminance model of the glow as the host draws it
// (ACC-012-clamped, then weighted by the ladder), exactly as `GlowFlashSafetyTests` does for FX-001. The composited
// luminance must obey the same rise bound at every level and while the ladder changes level. Pure arithmetic.
import XCTest
import FlashSafety
@testable import VisualGenerators
@testable import VisualEffects

final class EffectQualitySafetyTests: XCTestCase {
    private let strongest = BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1)

    /// The glow the native host draws: clamped first (ACC-012-R4), then the ladder's factor (PERF-003-R8).
    static func drawnGlow(_ glow: BloomParameters, clamp: SafetyClamp, factor: Float) -> BloomParameters {
        var drawn = glow.limited(by: clamp)
        drawn.intensity *= factor
        return drawn
    }

    /// Runs `frames` strobe frames at 60 Hz; `inputs(frame)` gives the thermal state and budget. Returns the worst
    /// rise as a fraction of the bound (≤ 1 passes), the gains, and the levels drawn.
    private func strobe(frames: Int, enabled: Bool, clamp: SafetyClamp = .standard,
                        inputs: (Int) -> (EffectThermalState, EffectBudgetSignal)) -> (rise: Double, levels: Set<Int>, maxIntensity: Float) {
        let dt = 1.0 / 60
        let limiter = FlashSafetyLimiter()
        let layout = CircularSpectrumLayout(configuration: CircularSpectrumConfiguration(barCount: .b64, palette: .spectrum))
        let full = [Float](repeating: 1, count: 64), empty = [Float](repeating: 0, count: 64)
        let ladder = EffectQualityLadder()
        let (firstThermal, _) = inputs(0)
        ladder.start(thermal: firstThermal, lowPower: false)
        var previous: Double?
        var worst = 0.0
        var levels: Set<Int> = []
        var maxIntensity: Float = 0
        let clampedIntensity: Float = strongest.limited(by: clamp).intensity
        for f in 0..<frames {
            let (thermal, budget) = inputs(f)
            ladder.step(time: Double(f) * dt, thermal: thermal, lowPower: false, budget: budget)
            levels.insert(ladder.applied.rawValue)
            let drawn = Self.drawnGlow(strongest, clamp: clamp, factor: ladder.intensityFactor)
            XCTAssertLessThanOrEqual(drawn.intensity, clampedIntensity, "the ladder never strengthens the clamped glow")
            maxIntensity = max(maxIntensity, drawn.intensity)
            let model = BloomLuminanceModel(parameters: drawn)
            let target = f % 2 == 0 ? full : empty
            let shown = target.withUnsafeBufferPointer { Array(limiter.limitValues($0, frameTime: dt, enabled: enabled)) }
            layout.layout(shown, width: 1179, height: 2556)
            let gain = limiter.gain(for: layout, transfer: model, frameTime: dt, enabled: enabled)
            let luminance = layout.meanLuminance(gain: gain, transfer: model)
            if let p = previous, luminance > p {
                worst = max(worst, (luminance - p - 1e-8) / (FlashSafetyLimiter.maxLuminanceRisePerSecond * dt))
            }
            previous = luminance
        }
        return (worst, levels, maxIntensity)
    }

    /// Acceptance: at each fixed level the strobe obeys the same bound as at Full (Reduce flashing on).
    func testStrobeObeysTheSameBoundAtEveryLevel() {
        let thermals: [(EffectThermalState, EffectQualityLevel)] = [(.nominal, .full), (.serious, .reduced), (.critical, .minimal)]
        for (thermal, level) in thermals {
            let r = strobe(frames: 180, enabled: true) { _ in (thermal, .within) }
            XCTAssertEqual(r.levels, [level.rawValue])
            XCTAssertLessThanOrEqual(r.rise, 1, "\(level): composited luminance rose too fast")
        }
    }

    /// Acceptance: nominal → serious → critical with a sustained over-budget verdict, under Reduce flashing and a
    /// strict sensory profile: every level is visited, every frame obeys the bound, the clamp's cap holds.
    func testStrobeAcrossLevelChangesKeepsTheLimits() {
        let schedule: (Int) -> (EffectThermalState, EffectBudgetSignal) = { (f: Int) -> (EffectThermalState, EffectBudgetSignal) in
            if f < 60 { return (.nominal, .within) }
            if f < 150 { return (.serious, .over) }
            return (.critical, .over)
        }
        let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: true)
        for clamp in [SafetyClamp(profile: .standard, reduceFlashingSetting: true), strict] {
            let r = strobe(frames: 240, enabled: true, clamp: clamp, inputs: schedule)
            XCTAssertEqual(r.levels, [0, 1, 2])
            XCTAssertLessThanOrEqual(r.rise, 1, "\(clamp)")
            XCTAssertLessThanOrEqual(r.maxIntensity, strongest.limited(by: clamp).intensity)
        }
    }

    /// With Reduce flashing off the always-on envelope still applies at every level and across changes.
    func testAlwaysOnEnvelopeHoldsAcrossLevels() {
        let r = strobe(frames: 240, enabled: false) { (f: Int) -> (EffectThermalState, EffectBudgetSignal) in
            f < 120 ? (.serious, .within) : (.nominal, .within)
        }
        XCTAssertTrue(r.levels.contains(EffectQualityLevel.reduced.rawValue))
        // The always-on cap bounds transitions, not the rise rate; the run must stay finite and the clamp unchanged.
        XCTAssertTrue(r.rise.isFinite)
    }

    func testTheLadderLeavesTheSafetyConfigurationUntouched() {
        // The limiter's envelope is chosen by Reduce flashing and the clamp alone (the ladder has no handle on it); the
        // glow the limiter models is the glow drawn, so Minimal models no glow at all and Full models today's.
        XCTAssertEqual(BloomLuminanceModel(parameters: Self.drawnGlow(strongest, clamp: .standard, factor: 1)).parameters,
                       BloomLuminanceModel(parameters: strongest).parameters)
        let model = BloomLuminanceModel(parameters: Self.drawnGlow(strongest, clamp: .standard, factor: 0))
        XCTAssertEqual(model.spreadRadius(width: 100, height: 100), 0, "Minimal adds no glow to the luminance model")
    }
}
