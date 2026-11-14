// EnvelopeBindingAppTests.swift — MOD-005-T08: in the app, a band bound to the glow intensity with a
// slow attack and a fast release makes the effective glow rise slowly and fall quickly, matching the
// one-pole curve 1 − exp(−t/τ) (MOD-005-R1 to R3, S4; contract E1). Deterministic: bands and frame
// times are passed in. Needs a Metal device (the simulator renders with the host GPU); skips without one.
import Foundation
import Metal
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class EnvelopeBindingAppTests: XCTestCase {
    private static let frame: UInt64 = 16_666_667   // 60 fps
    private static let attack = 0.5
    private static let release = 0.05

    private func apply(_ host: NativeSpectrumHost, band: Float, at time: UInt64) {
        let bands: [Float] = [band, 0.1, 0.1]
        bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            host.applyModulation(bands: buffer, timeNanoseconds: time)
        }
    }

    func testSlowAttackAndFastReleaseDriveTheGlow() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.5))
        try host.bind(AudioFeatureBinding(source: .band(0), target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1,
                                          envelope: AudioFeatureEnvelope(attackSeconds: Self.attack, releaseSeconds: Self.release)))
        var time: UInt64 = 1_000_000_000
        apply(host, band: 0, at: time)   // starts the clock at signal 0
        XCTAssertEqual(host.effectiveGlow.intensity, 0)

        // Slow rise: 0.5 s of band 1 reaches one attack constant (63.2 %), not the full level.
        for _ in 0..<30 { time += Self.frame; apply(host, band: 1, at: time) }
        let risen: Double = 1 - exp(-0.500_000_01 / Self.attack)
        XCTAssertEqual(Double(host.effectiveGlow.intensity), risen, accuracy: 0.01, "one attack constant after 0.5 s")
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")

        // Fast fall: 0.05 s of band 0 covers one release constant; 0.25 s nearly reaches 0.
        for _ in 0..<3 { time += Self.frame; apply(host, band: 0, at: time) }
        XCTAssertEqual(Double(host.effectiveGlow.intensity), risen * exp(-0.050_000_001 / Self.release), accuracy: 0.01,
                       "one release constant after 0.05 s")
        for _ in 0..<12 { time += Self.frame; apply(host, band: 0, at: time) }
        XCTAssertLessThan(host.effectiveGlow.intensity, 0.01, "five release constants after 0.25 s")
        XCTAssertEqual(host.bloomParameters?.intensity, host.effectiveGlow.intensity, "the bloom renders the effective intensity")
    }
}
