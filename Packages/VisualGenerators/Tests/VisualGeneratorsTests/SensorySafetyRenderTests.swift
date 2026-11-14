// SensorySafetyRenderTests.swift — ACC-012-T14 (GPU): generator → bloom → read back.
// * Standard is bit-identical (ACC-012-R6, S2): 30 frames of alternating bands rendered without the
//   profile and with the Standard clamp applied (glow limited by it, its envelope passed explicitly through
//   `VisualFrameContext.flashLimits`) give the same bytes.
// * Strict holds (ACC-012-R2, R3): the bloom gets intensity 0.25 and the composited mean luminance rises at
//   most 0.10 per second of frame time (+0.002 rasterization and half-float rounding, as FX-001-T14).
// Skips where no Metal device exists.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal
import XCTest
@testable import VisualEffects
@testable import VisualGenerators

final class SensorySafetyRenderTests: XCTestCase {
    private let size = 128
    private let format: MTLPixelFormat = .rgba16Float
    private let parameters = BloomParameters(enabled: true, intensity: 0.8, radius: 0.04, threshold: 0.1, knee: 1)

    /// Renders `frames` frames and returns each frame's raw bytes and mean luminance.
    private func render(rig: RenderRig, glow: BloomParameters, reduceFlashing: Bool, flashLimits: FlashEnvelopeConfiguration?,
                        frames: Int) throws -> (bytes: [[UInt8]], means: [Double], bloomIntensity: Float) {
        let configuration = CircularSpectrumConfiguration(barCount: .b64, innerRadius: 0.3, lengthScale: 0.4, palette: .mono)
        let generator = try rig.build { try CircularSpectrumGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: glow) }
        generator.downstreamLuminance = BloomLuminanceModel(parameters: glow)
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
        try chain.prepare(width: size, height: size)
        let output = try rig.makeTexture(width: size, height: size, format: format)
        let full = [Float](repeating: 1, count: 64)
        let empty = [Float](repeating: 0, count: 64)
        let dt: Double = 1.0 / 60
        var bytes: [[UInt8]] = []
        var means: [Double] = []
        for f in 0..<frames {
            let bands: [Float] = f % 2 == 0 ? full : empty
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let time: UInt64 = UInt64(f) * 16_666_667
            let context = VisualFrameContext(timeNanoseconds: time, frameDuration: dt, reduceFlashing: reduceFlashing,
                                             flashLimits: flashLimits)
            let drawn: Bool = bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                chain.encode(output: output, commandBuffer: commands) { (target: MTLTexture) -> Bool in
                    generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
                }
            }
            XCTAssertTrue(drawn, "frame \(f)")
            let buffer = try rig.encodeReadBack(output, commands: commands)
            commands.commit()
            commands.waitUntilCompleted()
            let raw: [UInt8] = RenderRig.bytes(of: buffer)
            bytes.append(raw)
            let image = rig.decode(raw, width: size, height: size, format: format)
            let total: Double = image.pixels.reduce(0.0) { (sum: Double, p: Pixel) -> Double in sum + luminance(p) }
            means.append(total / Double(size * size))
        }
        return (bytes, means, bloom.parameters.intensity)
    }

    func testStandardProfileRendersBitIdenticalFrames() throws {
        let rig = try RenderRig()
        let clamp = SafetyClamp.standard
        let without = try render(rig: rig, glow: parameters, reduceFlashing: false, flashLimits: nil, frames: 30)
        let explicit: FlashEnvelopeConfiguration = clamp.flashLimitsOverride ?? clamp.flashConfiguration
        let with = try render(rig: rig, glow: parameters.limited(by: clamp), reduceFlashing: clamp.reducesFlashing,
                              flashLimits: explicit, frames: 30)
        var differing = 0
        for f in 0..<30 where without.bytes[f] != with.bytes[f] { differing += 1 }
        print("ACC-012 Standard bit identity on \(rig.device.name): \(differing) of 30 frames differ")
        XCTAssertEqual(differing, 0)
        XCTAssertGreaterThan(without.means.max() ?? 0, 0.01, "the frames were not blank")
    }

    func testStrictProfileCapsGlowAndRiseRate() throws {
        let rig = try RenderRig()
        let clamp = SafetyClamp(profile: SensorySafetyProfile(preset: .strict), reduceFlashingSetting: false)
        let glow: BloomParameters = parameters.limited(by: clamp)
        let run = try render(rig: rig, glow: glow, reduceFlashing: clamp.reducesFlashing, flashLimits: clamp.flashLimitsOverride,
                             frames: 90)
        XCTAssertEqual(run.bloomIntensity, 0.25, accuracy: 1e-6, "the bloom renders the clamped intensity")
        var worstRise = 0.0
        for f in 1..<run.means.count { worstRise = max(worstRise, run.means[f] - run.means[f - 1]) }
        let bound: Double = 0.10 / 60
        print("ACC-012 Strict on \(rig.device.name): worst rise \(String(format: "%.5f", worstRise)) (bound \(String(format: "%.5f", bound)) + 0.002)")
        XCTAssertLessThanOrEqual(worstRise, bound + 0.002)
        XCTAssertGreaterThan(run.means.max() ?? 0, 0.005, "the frames were not blank")
    }
}
#endif
