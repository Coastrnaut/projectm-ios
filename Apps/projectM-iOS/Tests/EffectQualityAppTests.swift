// EffectQualityAppTests.swift — PERF-003-T09 (specs/173-perf-003-adaptive-quality): the native host's adaptive
// effect quality with injected thermal state, Low Power, budget and time. The roadmap acceptance ("Simulated
// thermal stress lowers effect quality and preserves safety limiter") on the real host: the level steps down before
// the governor's frame-rate cap, the bloom's plan really gets cheaper, the drawn glow never exceeds the ACC-012-
// clamped glow, and the luminance model the limiter uses follows it. Needs a Metal device (skips without one).
import Diagnostics
import FlashSafety
import Metal
import Rendering
import VisualEffects
import VisualGenerators
import XCTest
@testable import projectM_iOS

@MainActor
final class EffectQualityAppTests: XCTestCase {
    private let glow = BloomParameters(enabled: true, intensity: 0.8, radius: 0.04, threshold: 0.5, knee: 0.5)

    private func host(thermal: EffectThermalState = .nominal, glow: BloomParameters? = nil) throws -> NativeSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, style: .circular, barCount: .b32, glow: glow ?? self.glow)
        try host.bloom?.prepare(width: 1179, height: 2556)   // the frame loop does this on its first frame
        host.thermalOverride = thermal
        host.lowPowerOverride = false
        host.refreshQuality()
        host.startEffectQuality()
        host.stepEffectQuality(time: 0)
        return host
    }

    /// Steps at 60 Hz for `seconds` after `from` with the given inputs; returns the time reached.
    @discardableResult
    private func run(_ host: NativeSpectrumHost, from: Double, seconds: Double, thermal: EffectThermalState,
                     budget: EffectBudgetSignal = .unavailable, check: ((NativeSpectrumHost) -> Void)? = nil) -> Double {
        if host.thermalOverride != thermal {
            host.thermalOverride = thermal
            host.refreshQuality()
        }
        host.effectBudget = budget
        var t = from
        for i in 1...Int((seconds * 60).rounded()) {
            t = from + Double(i) / 60
            host.stepEffectQuality(time: t)
            check?(host)
        }
        return t
    }

    /// Acceptance: nominal → serious → critical. The effect level drops first; the 30 fps cap follows only at critical.
    func testThermalStressLowersTheGlowBeforeTheFrameRate() throws {
        let host = try host()
        let fullPlan = try XCTUnwrap(host.bloom?.plan)
        XCTAssertEqual(host.effectQualityLevel, .full)
        XCTAssertEqual(host.qualitySettings, QualitySettings.full)
        XCTAssertEqual(host.effectQualityLine, "effect quality full")

        var t = run(host, from: 0, seconds: 1, thermal: .serious)
        XCTAssertEqual(host.effectQualityLevel, .reduced)
        XCTAssertEqual(host.qualitySettings.maxFramesPerSecond, 60, "serious: the glow is reduced instead of the frame rate")
        let reducedPlan = try XCTUnwrap(host.bloom?.plan)
        XCTAssertLessThan(reducedPlan.blurWork, fullPlan.blurWork)
        XCTAssertLessThanOrEqual(reducedPlan.blurRadius, (fullPlan.blurRadius + 1) / 2)
        XCTAssertTrue(host.glowActive)
        XCTAssertEqual(host.effectQualityLine, "effect quality reduced (thermal)")

        t = run(host, from: t, seconds: 1, thermal: .critical)
        XCTAssertEqual(host.effectQualityLevel, .minimal)
        XCTAssertFalse(host.glowActive, "Minimal: no glow pass")
        XCTAssertNil(host.downstreamLuminance, "the limiter models no glow")
        XCTAssertEqual(host.qualitySettings, QualitySettings(maxFramesPerSecond: 30, renderScale: 0.75), "critical: the cap follows")
    }

    /// Without an adaptable effect the governor is exactly FR-049's table.
    func testGlowOffKeepsTodaysGovernor() throws {
        let host = try host(thermal: .serious, glow: BloomParameters())
        XCTAssertEqual(host.qualitySettings, QualityGovernor.settings(thermal: .serious, lowPower: false))
        XCTAssertEqual(host.qualitySettings.maxFramesPerSecond, 30)
        host.glow = glow
        XCTAssertEqual(host.qualitySettings.maxFramesPerSecond, 60, "switching the glow on defers the serious cap")
    }

    /// R3: a sustained over-budget verdict steps down; R4: recovery after 10 s good; the drawn glow never exceeds the
    /// clamped glow and the luminance model follows the drawn glow at every step (R8).
    func testBudgetStepsDownAndTheDrawnGlowNeverExceedsTheClamp() throws {
        let host = try host()
        host.safetyClamp = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: true)
        let cap: Float = glow.limited(by: host.safetyClamp).intensity
        let check: (NativeSpectrumHost) -> Void = { (h: NativeSpectrumHost) -> Void in
            XCTAssertLessThanOrEqual(h.effectiveGlow.intensity, cap)
            if let model = h.downstreamLuminance as? BloomLuminanceModel {
                XCTAssertEqual(model.parameters, h.effectiveGlow.clamped(), "the limiter models the glow drawn")
            }
        }
        var t = run(host, from: 0, seconds: 3.2, thermal: .nominal, budget: .over, check: check)
        XCTAssertEqual(host.effectLadder.target, .reduced)
        t = run(host, from: t, seconds: 1, thermal: .nominal, budget: .within, check: check)
        XCTAssertEqual(host.effectQualityLevel, .reduced)
        XCTAssertEqual(host.effectQualityLine, "effect quality reduced (budget)")
        XCTAssertEqual(host.effectiveGlow.intensity, cap, "the fade is back to full weight")
        let builds = try XCTUnwrap(host.bloom?.planBuildCount)
        t = run(host, from: t, seconds: 5, thermal: .nominal, budget: .within, check: check)
        XCTAssertEqual(host.bloom?.planBuildCount, builds, "holding a level rebuilds nothing (R12)")
        run(host, from: t, seconds: 5.5, thermal: .nominal, budget: .within, check: check)
        XCTAssertEqual(host.effectQualityLevel, .full)
        XCTAssertEqual(host.effectiveGlow, glow.limited(by: host.safetyClamp), "Full is today's glow exactly")
    }

    func testExportCarriesTheLevel() {
        let quality = AppCoordinator.exportEffectQuality(level: .reduced, reason: .thermal)
        XCTAssertEqual(quality, DiagnosticsSnapshot.FrameTimings.EffectQuality(level: "reduced", reason: "thermal"))
        XCTAssertEqual(AppCoordinator.exportEffectQuality(level: .full, reason: nil).reason, nil)
        XCTAssertNil(NativeSpectrumHost.launchThermalOverride, "unit tests launch without the argument")
    }
}
