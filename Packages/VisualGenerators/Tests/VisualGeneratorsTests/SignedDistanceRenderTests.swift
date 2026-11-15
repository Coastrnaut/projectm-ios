// SignedDistanceRenderTests.swift — VIS-017-T06 (VIS-017-R1, R3 to R5, R12; S1 to S3; contract C2 to C4): the SDF shapes on
// the real Metal pipeline. The step-count view (rgba16Float, integers exact) shows every pixel's march within its
// preset's cap, High marching further than Low allows; a render with extreme bands, a huge time and a time jump is
// finite and in 0…1 everywhere; two renders are identical; GPU and CPU mirror agree on hit or miss away from
// silhouettes; a quality change applies in place; entering the mode and a loop restart reset the pose. No byte-size
// assertion (the simulator misreports texture allocation sizes). Without a Metal device the tests skip.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators

final class SignedDistanceRenderTests: XCTestCase {
    private static let width = 96
    private static let height = 72

    private func context(_ nanoseconds: UInt64) -> VisualFrameContext {
        VisualFrameContext(timeNanoseconds: nanoseconds, frameDuration: 1.0 / 60, reduceFlashing: false)
    }

    /// Draws `frames` 60 Hz frames of `bands` (optionally an extra frame at `lastTime`) and reads back the target.
    private func render(_ rig: RenderRig, generator: NoiseFieldGenerator, bands: [Float], frames: Int = 6,
                        lastTime: UInt64? = nil, format: MTLPixelFormat = .rgba16Float) throws -> PixelImage {
        let texture = try rig.makeTexture(width: Self.width, height: Self.height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        var times: [UInt64] = (0..<frames).map { (f: Int) -> UInt64 in UInt64(f) * 1_000_000_000 / 60 }
        if let lastTime { times.append(lastTime) }
        for t in times {
            let drawn: Bool = bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
                generator.encode(into: texture, commandBuffer: commands, bands: b, context: context(t))
            }
            XCTAssertTrue(drawn)
        }
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, "\(String(describing: commands.error))")
        return rig.decode(RenderRig.bytes(of: buffer), width: Self.width, height: Self.height, format: format)
    }

    private func make(_ rig: RenderRig, quality: SignedDistanceQuality, format: MTLPixelFormat = .rgba16Float) throws -> NoiseFieldGenerator {
        try rig.build {
            try NoiseFieldGenerator(device: rig.device, pixelFormat: format,
                                    configuration: .signedDistance(SignedDistanceSettings(quality: quality)))
        }
    }

    private func stepCounts(_ rig: RenderRig, generator: NoiseFieldGenerator) throws -> PixelImage {
        let state = try generator.makeStepCountPipeline(format: .rgba16Float)
        let texture = try rig.makeTexture(width: Self.width, height: Self.height, format: .rgba16Float)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(generator.encodeStepCounts(into: texture, commandBuffer: commands, state: state))
        let buffer = try rig.encodeReadBack(texture, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
        return rig.decode(RenderRig.bytes(of: buffer), width: Self.width, height: Self.height, format: .rgba16Float)
    }

    /// S1 on the GPU: per preset, no pixel's march exceeds the cap; High needs more steps than Low's cap somewhere.
    func testQualityPresetsBoundTheGPUStepCounts() throws {
        let rig = try RenderRig()
        var maxima: [SignedDistanceQuality: Float] = [:]
        for quality in SignedDistanceQuality.allCases {
            let generator = try make(rig, quality: quality)
            _ = try render(rig, generator: generator, bands: [Float](repeating: 0.5, count: 64))
            let steps = try stepCounts(rig, generator: generator)
            let maximum: Float = steps.pixels.map(\.x).max() ?? 0
            XCTAssertLessThanOrEqual(maximum, Float(quality.stepCap), "\(quality)")
            XCTAssertEqual(steps.pixels.map(\.x).min(), 0, "corners miss the bounding sphere: no steps")
            XCTAssertGreaterThan(steps.pixels.filter { (p: Pixel) -> Bool in p.y > 0.5 }.count, 200, "the shapes are hit")
            maxima[quality] = maximum
        }
        XCTAssertEqual(maxima[.low], Float(SignedDistanceQuality.low.stepCap), "grazing rays reach Low's cap")
        XCTAssertGreaterThan(maxima[.high] ?? 0, Float(SignedDistanceQuality.low.stepCap))
        print("VIS-017 GPU step-count maxima: \(SignedDistanceQuality.allCases.map { "\($0.rawValue) \(Int(maxima[$0] ?? 0))/\($0.stepCap)" })")
    }

    /// S2 on the GPU: NaN, ±infinity and huge bands, a huge time and a time jump: every value finite and in 0…1.
    func testExtremeInputsRenderFinite() throws {
        let rig = try RenderRig()
        let generator = try make(rig, quality: .high)
        var bands = [Float](repeating: 1e6, count: 64)
        bands[0] = .nan; bands[1] = .infinity; bands[2] = -.infinity; bands[30] = -5
        let image = try render(rig, generator: generator, bands: bands, lastTime: 1_000_000_000 * 1_000_000_000)
        for p in image.pixels {
            for k in 0..<4 { XCTAssertTrue(p[k].isFinite && p[k] >= 0 && p[k] <= 1, "\(p)") }
        }
        XCTAssertGreaterThan(image.pixels.map(luminance).max() ?? 0, 0.05, "the shapes are lit")
        XCTAssertTrue(generator.signedDistanceUniforms.allSatisfy(\.isFinite))
    }

    /// S3: two renders from scratch are identical, and GPU and CPU agree on hit or miss away from silhouettes.
    func testRendersAreDeterministicAndAgreeWithTheCPUMirror() throws {
        let rig = try RenderRig()
        let bands = [Float](repeating: 0.4, count: 64)
        let first = try make(rig, quality: .medium)
        let a = try render(rig, generator: first, bands: bands)
        let b = try render(rig, generator: try make(rig, quality: .medium), bands: bands)
        XCTAssertEqual(a, b)
        let steps = try stepCounts(rig, generator: first)
        let pose = first.signedDistanceDrive.pose
        var compared = 0
        for y in Swift.stride(from: 2, to: Self.height - 2, by: 3) {
            for x in Swift.stride(from: 2, to: Self.width - 2, by: 3) {
                let hits: [Bool] = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)].map { (d: (Int, Int)) -> Bool in
                    let p = SignedDistanceScene.offset(pixel: SIMD2<Float>(Float(x + d.0) + 0.5, Float(y + d.1) + 0.5),
                                                       width: Self.width, height: Self.height)
                    let ray = SignedDistanceScene.ray(p)
                    return SignedDistanceScene.march(origin: ray.origin, direction: ray.direction, pose: pose, quality: .medium).kind != nil
                }
                guard hits.allSatisfy({ (h: Bool) -> Bool in h == hits[0] }) else { continue }   // near a silhouette
                compared += 1
                XCTAssertEqual(steps[x, y].y > 0.5, hits[0], "pixel \(x), \(y)")
            }
        }
        XCTAssertGreaterThan(compared, 500)
    }

    /// Quality changes in place; entering the mode and a loop restart start from the rest pose (contract C2).
    func testQualityChangesInPlaceAndReentryResetsThePose() throws {
        let rig = try RenderRig()
        let generator = try make(rig, quality: .low)
        let bands = [Float](repeating: 0.8, count: 64)
        _ = try render(rig, generator: generator, bands: bands, frames: 30)
        let turned = generator.signedDistanceDrive.angle
        XCTAssertGreaterThan(turned, 0)
        generator.configuration = .signedDistance(SignedDistanceSettings(quality: .high))
        let texture = try rig.makeTexture(width: 8, height: 8, format: .rgba16Float)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        _ = bands.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> Bool in
            generator.encode(into: texture, commandBuffer: commands, bands: b, context: context(UInt64(31) * 1_000_000_000 / 60))
        }
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(generator.signedDistanceUniforms[0], 96, "High's cap from the next frame")
        XCTAssertGreaterThan(generator.signedDistanceDrive.angle, turned, "the pose keeps turning")
        generator.restartLoop()
        XCTAssertEqual(generator.signedDistanceDrive, SignedDistanceDrive())
        // Back to the plain field and in again: the rest pose (re-entry resets the drive).
        generator.configuration = NoiseFieldConfiguration()
        _ = try render(rig, generator: generator, bands: bands, frames: 2, format: .rgba16Float)
        generator.configuration = .signedDistance(.default)
        let again = try render(rig, generator: generator, bands: bands)
        let fresh = try render(rig, generator: try make(rig, quality: .medium), bands: bands)
        XCTAssertEqual(again, fresh, "re-entering draws a fresh generator's frames")
    }
}
#endif
