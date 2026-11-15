// CymaticRenderTests.swift — VIS-019-T06 (VIS-019-R1, R4, R6, R7, R14; S1 to S4; contract C2 to C5): the cymatic lines on
// the real Metal pipeline. The mask view (rgba16Float: the blended displacement in red) shows two pure tones (AUD-016
// sines through the real ANL-002 reducer) settling to nodal masks that differ in ≥ 50% of their combined line pixels and
// agree with the CPU mirror away from the mask's edge; a tone followed by the settle time of silence draws a frame
// bit-identical to a generator that only ever saw silence (Reduce Motion off and on); two renders are identical; extreme
// bands and times render finite in 0…1; a range change applies in place; entering the mode and a loop restart reset to
// rest. No byte-size assertion (the simulator misreports texture allocation sizes). Without a Metal device the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class CymaticRenderTests: XCTestCase {
    private static let width = 96
    private static let height = 72

    private func context(_ frame: Int) -> VisualFrameContext {
        VisualFrameContext(timeNanoseconds: CymaticFixture.nanoseconds(frame), frameDuration: 1.0 / 60, reduceFlashing: false)
    }

    private func make(_ rig: RenderRig, bands: CymaticBandRange = .all, reduceMotion: Bool = false,
                      format: MTLPixelFormat = .rgba16Float) throws -> NoiseFieldGenerator {
        try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: format,
                                    configuration: .cymatic(CymaticSettings(bands: bands), reduceMotion: reduceMotion))
        }
    }

    /// Draws 60 Hz frames `start ..< start + frames`, `bands(f)` per frame, and reads back the last one.
    @discardableResult
    private func render(_ rig: RenderRig, generator: NoiseFieldGenerator, from start: Int = 0, frames: Int,
                        bands: (Int) -> [Float]) throws -> PixelImage {
        let texture = try rig.makeTexture(width: Self.width, height: Self.height, format: generator.pixelFormat)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        for f in start..<(start + frames) {
            let drawn: Bool = bands(f).withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context(f))
            }
            XCTAssertTrue(drawn)
        }
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return rig.decode(RenderRig.bytes(of: buffer), width: Self.width, height: Self.height, format: generator.pixelFormat)
    }

    private func maskView(_ rig: RenderRig, generator: NoiseFieldGenerator) throws -> PixelImage {
        let state = try generator.makeCymaticMaskPipeline(format: .rgba16Float)
        let texture = try rig.makeTexture(width: Self.width, height: Self.height, format: .rgba16Float)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(generator.encodeCymaticMask(into: texture, commandBuffer: commands, state: state))
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
        return rig.decode(RenderRig.bytes(of: buffer), width: Self.width, height: Self.height, format: .rgba16Float)
    }

    /// S1 on the GPU: two pure tones, two figures; the GPU field agrees with the CPU mirror.
    func testPureTonesChangeTheGPUNodalPatternAndAgreeWithTheCPU() throws {
        let rig = try RenderRig()
        var masks: [[Bool]] = []
        var targets: [Int] = []
        for frequency in [100.0, 1_000.0] {
            let tone = try CymaticFixture.toneBands(frequency)
            let generator = try make(rig)
            try render(rig, generator: generator, frames: 61) { (_: Int) -> [Float] in tone }
            let weights = generator.cymaticDrive.weights
            targets.append(generator.cymaticDrive.target)
            let view = try maskView(rig, generator: generator)
            var mask: [Bool] = []
            var compared = 0
            for y in 0..<Self.height {
                for x in 0..<Self.width {
                    let gpu: Float = view[x, y].x
                    mask.append(CymaticField.onMask(gpu))
                    let q = CymaticField.plate(pixel: SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5), width: Self.width, height: Self.height)
                    let cpu: Float = CymaticField.blended(at: q, weights: weights)
                    XCTAssertEqual(gpu, cpu, accuracy: 0.01, "pixel \(x), \(y)")
                    if abs(abs(cpu) - CymaticField.maskHalfWidth) > 0.01 {   // away from the mask's edge
                        compared += 1
                        XCTAssertEqual(CymaticField.onMask(gpu), CymaticField.onMask(cpu), "pixel \(x), \(y)")
                    }
                }
            }
            XCTAssertGreaterThan(compared, Self.width * Self.height * 9 / 10)
            masks.append(mask)
        }
        XCTAssertNotEqual(targets[0], targets[1])
        let d = CymaticFixture.difference(masks[0], masks[1])
        XCTAssertGreaterThanOrEqual(d, CymaticFixture.threshold)
        print("VIS-019 GPU: 100 Hz → mode \(targets[0]), 1 kHz → mode \(targets[1]); masks differ in \(String(format: "%.1f", d * 100))% of their line pixels")
    }

    /// S2 on the GPU: a tone, then the settle time of silence, draws the never-excited generator's frame bit for bit.
    func testSilenceSettlesToTheRestFrameBitForBit() throws {
        let rig = try RenderRig()
        let tone = try CymaticFixture.toneBands(1_000)
        let silence = [Float](repeating: 0, count: 64)
        for reduceMotion in [false, true] {
            let settleFrames = Int(CymaticDrive.settleSeconds(reduceMotion: reduceMotion) * 60)
            let excited = try make(rig, reduceMotion: reduceMotion, format: .bgra8Unorm_srgb)
            try render(rig, generator: excited, frames: 60) { (_: Int) -> [Float] in tone }
            XCTAssertFalse(excited.cymaticDrive.isAtRest)
            let settled = try render(rig, generator: excited, from: 60, frames: settleFrames) { (_: Int) -> [Float] in silence }
            XCTAssertTrue(excited.cymaticDrive.isAtRest, "Reduce Motion \(reduceMotion)")
            let fresh = try make(rig, reduceMotion: reduceMotion, format: .bgra8Unorm_srgb)
            let baseline = try render(rig, generator: fresh, frames: 60 + settleFrames) { (_: Int) -> [Float] in silence }
            XCTAssertEqual(excited.lastGain, 1)
            XCTAssertEqual(fresh.lastGain, 1)
            XCTAssertEqual(excited.cymaticUniforms, fresh.cymaticUniforms)
            XCTAssertEqual(settled, baseline, "Reduce Motion \(reduceMotion): the rest frame, bit for bit")
            XCTAssertGreaterThan(baseline.pixels.map(luminance).max() ?? 0, 0.1, "the rest cross is drawn")
        }
    }

    /// S3, S4: two renders from scratch are identical; extreme bands and a huge time jump render finite in 0…1.
    func testRendersAreDeterministicAndFinite() throws {
        let rig = try RenderRig()
        let bands = CymaticFixture.lit(30, level: 0.7)
        let a = try render(rig, generator: try make(rig), frames: 20) { (_: Int) -> [Float] in bands }
        let b = try render(rig, generator: try make(rig), frames: 20) { (_: Int) -> [Float] in bands }
        XCTAssertEqual(a, b)
        var wild = [Float](repeating: 1e6, count: 64)
        wild[0] = .nan; wild[1] = .infinity; wild[2] = -.infinity; wild[40] = -5
        let generator = try make(rig, reduceMotion: true)
        try render(rig, generator: generator, frames: 10) { (_: Int) -> [Float] in wild }
        let image = try render(rig, generator: generator, from: 1_000_000_000, frames: 2) { (_: Int) -> [Float] in wild }
        for p in image.pixels {
            for k in 0..<4 { XCTAssertTrue(p[k].isFinite && p[k] >= 0 && p[k] <= 1, "\(p)") }
        }
        XCTAssertLessThanOrEqual(image.pixels.map(luminance).max() ?? 1, 0.8 + 1e-3, "below full white")
        XCTAssertTrue(generator.cymaticUniforms.allSatisfy(\.isFinite))
    }

    /// A range change applies in place; a loop restart and re-entry start at rest (contract C2).
    func testRangeChangesInPlaceAndReentryStartsAtRest() throws {
        let rig = try RenderRig()
        let generator = try make(rig)
        let high = CymaticFixture.lit(50)
        try render(rig, generator: generator, frames: 61) { (_: Int) -> [Float] in high }
        XCTAssertEqual(generator.cymaticDrive.target, 7)
        generator.configuration = .cymatic(CymaticSettings(bands: .low))
        try render(rig, generator: generator, from: 61, frames: 6) { (_: Int) -> [Float] in high }
        XCTAssertEqual(generator.cymaticDrive.target, CymaticField.restIndex, "out of Low: silence")
        XCTAssertGreaterThan(generator.cymaticDrive.weights[7], 0, "the blend continues (no reset)")
        generator.restartLoop()
        XCTAssertEqual(generator.cymaticDrive, CymaticDrive())
        generator.configuration = NoiseFieldConfiguration()
        try render(rig, generator: generator, frames: 2) { (_: Int) -> [Float] in high }
        generator.configuration = .cymatic(.default)
        let again = try render(rig, generator: generator, frames: 20) { (_: Int) -> [Float] in high }
        let fresh = try render(rig, generator: try make(rig), frames: 20) { (_: Int) -> [Float] in high }
        XCTAssertEqual(again, fresh, "re-entering draws a fresh generator's frames")
    }
}
#endif
