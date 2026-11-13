// BloomFlashSafetyRenderTests.swift — FX-001-T14 (GPU): generator → bloom → read back, Reduce
// flashing on, bands alternating 0/1 every frame; the mean luminance measured on the composited
// pixels rises at most 0.25 per second of frame time (+0.002 for rasterization and half-float
// rounding) (FX-001-R10, S4). Skips where no Metal device exists.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators
@testable import VisualEffects

final class BloomFlashSafetyRenderTests: XCTestCase {
    func testMeasuredCompositedLuminanceRiseIsBounded() throws {
        let rig = try RenderRig()
        let format: MTLPixelFormat = .rgba16Float
        let size = 256
        // The ring stays within 0.7 radius units, so the halo (E ≤ 20 px here) stays in frame.
        let configuration = CircularSpectrumConfiguration(barCount: .b64, innerRadius: 0.3, lengthScale: 0.4, palette: .mono)
        let parameters = BloomParameters(enabled: true, intensity: 1, radius: 0.06, threshold: 0.1, knee: 1)
        let generator = try rig.build { try CircularSpectrumGenerator(device: rig.device, pixelFormat: format, configuration: configuration) }
        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: parameters) }
        generator.downstreamLuminance = BloomLuminanceModel(parameters: parameters)
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
        try chain.prepare(width: size, height: size)
        let output = try rig.makeTexture(width: size, height: size, format: format)
        let full = [Float](repeating: 1, count: 64), empty = [Float](repeating: 0, count: 64)
        let dt = 1.0 / 60
        var previous: Double?
        var worstRise = 0.0, peak = 0.0, worstModelGap = 0.0
        for f in 0..<120 {
            let bands = f % 2 == 0 ? full : empty
            let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
            let context = VisualFrameContext(timeNanoseconds: UInt64(f) * 16_666_667, frameDuration: dt, reduceFlashing: true)
            let drawn = bands.withUnsafeBufferPointer { b in
                chain.encode(output: output, commandBuffer: commands) { target in
                    generator.encode(into: target, commandBuffer: commands, bands: b, context: context)
                }
            }
            XCTAssertTrue(drawn, "frame \(f)")
            let buffer = try rig.encodeReadBack(output, commands: commands)
            commands.commit()
            commands.waitUntilCompleted()
            let image = rig.decode(RenderRig.bytes(of: buffer), width: size, height: size, format: format)
            let mean = image.pixels.reduce(0.0) { $0 + luminance($1) } / Double(size * size)
            let modeled = generator.layout.meanLuminance(gain: generator.lastGain, transfer: BloomLuminanceModel(parameters: parameters))
            worstModelGap = max(worstModelGap, mean - modeled)
            peak = max(peak, mean)
            if let p = previous { worstRise = max(worstRise, mean - p) }
            previous = mean
        }
        let bound = FlashSafetyLimiter.maxLuminanceRisePerSecond * dt
        print("FX-001 flash GPU on \(rig.device.name): worst rise \(String(format: "%.5f", worstRise)) (bound \(String(format: "%.5f", bound)) + 0.002), peak \(String(format: "%.4f", peak)), worst measured − modeled \(String(format: "%.5f", worstModelGap))")
        XCTAssertLessThanOrEqual(worstRise, bound + 0.002)
        XCTAssertGreaterThan(peak, 0.01, "the frames were not blank")
    }
}
#endif
