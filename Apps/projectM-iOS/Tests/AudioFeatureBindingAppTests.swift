// AudioFeatureBindingAppTests.swift — MOD-002-T10: a band bound to the glow intensity drives the
// bloom and the Reduce-flashing luminance model, and unbinding restores the manual intensity
// (MOD-002-R11, R13; FX-001-R10, FX-019). Deterministic: bands and frame times are passed in. Needs a
// Metal device (the simulator renders with the host GPU); skips without one.
import Metal
import ParameterGraph
import VisualEffects
import VisualGenerators
import VisualParameters
import XCTest
@testable import projectM_iOS

@MainActor
final class AudioFeatureBindingAppTests: XCTestCase {
    private static let bassToGlow = AudioFeatureBinding(source: .band(0), target: VisualParameterIDs.bloomIntensity,
                                                        outputStart: 0, outputEnd: 1)

    private func makeHost(glowEnabled: Bool = true) throws -> NativeSpectrumHost {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        return try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32,
                                           glow: BloomParameters(enabled: glowEnabled, intensity: 0.5))
    }

    private func apply(_ host: NativeSpectrumHost, band: Float, at time: UInt64) {
        let bands: [Float] = [band, 0.1, 0.1]
        bands.withUnsafeBufferPointer { host.applyModulation(bands: $0, timeNanoseconds: time) }
    }

    func testBassDrivesTheGlowAndUnbindRestoresTheManualIntensity() throws {
        let host = try makeHost()
        XCTAssertEqual(host.glowModulationReadout, "unbound, manual 0.50, effective 0.50")
        try host.bind(Self.bassToGlow)
        apply(host, band: 0.75, at: 1_000_000)
        XCTAssertEqual(host.effectiveGlow.intensity, 0.75)
        XCTAssertEqual(host.bloomParameters?.intensity, 0.75, "the bloom renders the effective intensity")
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
        XCTAssertTrue(host.glowActive)
        let white = LinearColor(red: 1, green: 1, blue: 1, alpha: 1)
        let limiterSees = try XCTUnwrap(host.downstreamLuminance).outputLuminance(ofFlatColor: white)
        XCTAssertEqual(limiterSees, BloomLuminanceModel(parameters: host.effectiveGlow).outputLuminance(ofFlatColor: white),
                       "Reduce flashing bounds the frame with the effective intensity")
        XCTAssertGreaterThan(limiterSees, BloomLuminanceModel(parameters: host.glow).outputLuminance(ofFlatColor: white))
        XCTAssertEqual(host.glowModulationReadout, "bound, manual 0.50, effective 0.75")

        XCTAssertTrue(host.unbind(VisualParameterIDs.bloomIntensity))
        XCTAssertEqual(host.effectiveGlow, host.glow, "unbind restores manual control")
        XCTAssertEqual(host.bloomParameters?.intensity, 0.5)
        XCTAssertEqual(host.glowModulationReadout, "unbound, manual 0.50, effective 0.50")
    }

    /// ANL-007-T11: a Kick binding on the glow follows the kick envelope the frame loop passes in
    /// (ANL-007-R11, R12).
    func testKickBindsAndDrivesTheGlow() throws {
        let host = try makeHost()
        try host.bind(AudioFeatureBinding(source: .kick, target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        XCTAssertEqual(host.bindings.map(\.source), [.kick])
        let bands: [Float] = [0.1, 0.1, 0.1]
        var time: UInt64 = 1_000_000
        for envelope: Float in [1, 0.25] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                host.applyModulation(bands: buffer, kick: envelope, timeNanoseconds: time)
            }
            time += 16_666_667
            XCTAssertEqual(host.effectiveGlow.intensity, envelope)
        }
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
    }

    /// ANL-010-T11: a Centroid binding on the glow follows the normalized centroid the frame loop
    /// passes in (ANL-010-R8, R9).
    func testCentroidBindsAndDrivesTheGlow() throws {
        let host = try makeHost()
        try host.bind(AudioFeatureBinding(source: .centroid, target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        XCTAssertEqual(host.bindings.map(\.source), [.centroid])
        let bands: [Float] = [0.1, 0.1, 0.1]
        var time: UInt64 = 1_000_000
        for centroid: Float in [0.25, 0.75] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                host.applyModulation(bands: buffer, kick: 1, centroid: centroid, timeNanoseconds: time)
            }
            time += 16_666_667
            XCTAssertEqual(host.effectiveGlow.intensity, centroid)
        }
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
    }

    /// ANL-014-T10: a Loudness binding on the glow follows the loudness envelope the frame loop
    /// passes in (ANL-014-R8, R9).
    func testLoudnessBindsAndDrivesTheGlow() throws {
        let host = try makeHost()
        try host.bind(AudioFeatureBinding(source: .loudness, target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        XCTAssertEqual(host.bindings.map(\.source), [.loudness])
        let bands: [Float] = [0.1, 0.1, 0.1]
        var time: UInt64 = 1_000_000
        for loudness: Float in [0.375, 0.875] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                host.applyModulation(bands: buffer, kick: 1, centroid: 0.5, loudness: loudness, timeNanoseconds: time)
            }
            time += 16_666_667
            XCTAssertEqual(host.effectiveGlow.intensity, loudness)
        }
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
    }

    /// ANL-008-T09: a Mid transient binding on the glow follows the mid transient value
    /// (envelope × confidence) the frame loop passes in (ANL-008-R8, R9).
    func testMidTransientBindsAndDrivesTheGlow() throws {
        let host = try makeHost()
        try host.bind(AudioFeatureBinding(source: .midTransient, target: VisualParameterIDs.bloomIntensity, outputStart: 0, outputEnd: 1))
        XCTAssertEqual(host.bindings.map(\.source), [.midTransient])
        let bands: [Float] = [0.1, 0.1, 0.1]
        var time: UInt64 = 1_000_000
        for value: Float in [0.75, 0.25] {
            bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
                host.applyModulation(bands: buffer, kick: 1, centroid: 0.5, loudness: 0.5, midTransient: value, timeNanoseconds: time)
            }
            time += 16_666_667
            XCTAssertEqual(host.effectiveGlow.intensity, value)
        }
        XCTAssertEqual(host.glow.intensity, 0.5, "the manual intensity is unchanged")
    }

    func testManualOnlyGlowSwitchCannotBeBoundAndAnOffGlowStaysOff() throws {
        let host = try makeHost(glowEnabled: false)
        XCTAssertThrowsError(try host.bind(AudioFeatureBinding(source: .band(0), target: VisualParameterIDs.bloomEnabled,
                                                               outputStart: 0, outputEnd: 1)))
        try host.bind(Self.bassToGlow)
        apply(host, band: 1, at: 1_000_000)
        XCTAssertFalse(host.glowActive, "on/off is manual only: the bound intensity does not switch the glow on")
    }
}
