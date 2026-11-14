// CurveMappingAppTests.swift — MOD-004-T08: a binding with a curve drives the glow end to end in the app's
// native spectrum host, and ACC-012's safety clamp still caps it before render (MOD-004-R6, R11, S5).
// Deterministic: bands and frame times are passed in. Needs a Metal device (the simulator renders with the
// host GPU); skips without one.
import FlashSafety
import Metal
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class CurveMappingAppTests: XCTestCase {
    private func makeHost() throws -> NativeSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                           glow: BloomParameters(enabled: true, intensity: 0.5))
    }

    private func apply(_ host: NativeSpectrumHost, band: Float, at time: UInt64) {
        let bands: [Float] = [band, 0.1, 0.1]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            host.applyModulation(bands: buffer, timeNanoseconds: time)
        }
    }

    private static func curved(_ curve: MappingCurve) -> AudioFeatureBinding {
        AudioFeatureBinding(source: .band(0), target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1, curve: curve)
    }

    func testCurvedBindingDrivesTheGlow() throws {
        let host = try makeHost()
        try host.bind(Self.curved(.easeIn(exponent: 2)))
        XCTAssertEqual(host.bindings.map(\.curve), [.easeIn(exponent: 2)])
        var time: UInt64 = 1_000_000
        let rows: [(band: Float, intensity: Float)] = [(0.5, 0.25), (1, 1), (0, 0)]
        for row in rows {
            apply(host, band: row.band, at: time)
            time += 16_666_667
            XCTAssertEqual(host.effectiveGlow.intensity, row.intensity, "band \(row.band)")
            XCTAssertEqual(host.bloomParameters?.intensity, row.intensity, "the bloom renders the curved intensity")
        }
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
    }

    func testInvalidCurveIsRefusedByTheHost() throws {
        let host = try makeHost()
        let bad = MappingCurve.piecewise([CurvePoint(x: 0.6, y: 0.5), CurvePoint(x: 0.4, y: 0.7)])
        XCTAssertThrowsError(try host.bind(Self.curved(bad)))
        XCTAssertEqual(host.bindings, [])
    }

    func testSafetyClampCapsACurvedBinding() throws {
        let host = try makeHost()
        try host.bind(Self.curved(.logarithmic(strength: 1000)))
        var time: UInt64 = 1_000_000
        for preset: SensorySafetyPreset in [.reduced, .strict] {
            let clamp = SafetyClamp(profile: SensorySafetyProfile(preset: preset), reduceFlashingSetting: false)
            AppCoordinator.applySafety(clamp, renderer: nil, native: host, compositors: [])
            for band: Float in [0.05, 0.5, 1] {
                apply(host, band: band, at: time)
                time += 16_666_667
                let cap: Float = Float(clamp.limits.intensityLimit)
                XCTAssertLessThanOrEqual(host.bloomParameters?.intensity ?? 2, cap + 1e-6, "\(preset.rawValue), band \(band)")
            }
            XCTAssertEqual(host.bloomParameters?.intensity ?? -1, Float(clamp.limits.intensityLimit), accuracy: 1e-6,
                           "\(preset.rawValue): a steep curve at full input reaches the cap, not past it")
        }
    }
}
