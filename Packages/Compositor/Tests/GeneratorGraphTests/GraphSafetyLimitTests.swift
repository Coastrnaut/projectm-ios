// GraphSafetyLimitTests.swift — ACC-012-T09: the sensory safety profile's intensity limit caps a graph
// layer's speed before render (ACC-012-R3, R4). The phase a rendered frame advances by is the capped
// speed × frame time; at limit 1 the stored speed is used unchanged. Skips without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import FlashSafety
import GeneratorGraph
import Metal
import XCTest

final class GraphSafetyLimitTests: XCTestCase {
    func testIntensityLimitCapsTheRenderedSpeed() throws {
        let rig = try GraphGPURig()
        let layer = try rig.layer(GeneratorGraphExamples.hueRings)
        let cap: Double = layer.compiled.speedCap
        layer.setSpeed(cap)
        XCTAssertEqual(layer.effectiveSpeed, cap, "limit 1: unchanged")
        let strict = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        layer.intensityLimit = strict.limits.intensityLimit
        XCTAssertEqual(layer.effectiveSpeed, strict.speed(cap, cap: cap), accuracy: 1e-12, "the clamp's speed rule")
        XCTAssertEqual(layer.effectiveSpeed, cap * 0.25, accuracy: 1e-12)
        XCTAssertEqual(layer.speed, cap, "the stored speed is never changed")
        let driver = try GraphGPURig.Driver(rig: rig, layer: layer)
        try driver.step()   // the first frame has no duration
        let before: Double = layer.motion.phase
        try driver.step()
        let advanced: Double = layer.motion.phase - before
        XCTAssertEqual(advanced, cap * 0.25 / 60, accuracy: 1e-6, "the render input is the capped speed")
    }
}
#endif
