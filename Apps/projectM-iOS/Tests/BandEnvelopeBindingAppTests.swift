// BandEnvelopeBindingAppTests.swift — MOD-015-T09 (MOD-015-R5, R6, S4): in the app, a binding from band 1's slow
// envelope (`audio.bandEnvelope.slow.0`) drives the glow intensity along the slow profile's closed form through
// `NativeSpectrumHost`'s frame evaluation, and the inspector names the source "Band 1 slow". Deterministic: frame
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
final class BandEnvelopeBindingAppTests: XCTestCase {
    private static let frame: UInt64 = 16_666_667   // 60 fps
    private static let origin: UInt64 = 1_000_000_000

    func testSlowEnvelopeBindingDrivesTheGlowAlongItsProfile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                               glow: BloomParameters(enabled: true, intensity: 0.5))
        let source = AudioFeatureSource.bandEnvelope(0, .slow)
        try host.bind(AudioFeatureBinding(source: source, target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        XCTAssertEqual(host.bindings.map(\.source), [source])
        XCTAssertEqual(source.inspectorName, "Band 1 slow")
        XCTAssertEqual(AudioFeatureSource.bandEnvelope(3, .fast).inspectorName, "Band 4 fast")
        let tau: Double = BandEnvelopeProfile.slow.envelope.attackSeconds
        let bands: [Float] = [1, 0.1, 0.1]
        for index in 0...60 {   // 1 s of full band 1; the first frame starts the clock
            let elapsed = UInt64(index) * Self.frame
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                host.applyModulation(bands: buffer, timeNanoseconds: Self.origin + elapsed)
            }
            let expected: Double = 1 - exp(-Double(elapsed) / 1e9 / tau)
            XCTAssertEqual(Double(host.effectiveGlow.intensity), expected, accuracy: 1e-5, "frame \(index)")
        }
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
    }
}
