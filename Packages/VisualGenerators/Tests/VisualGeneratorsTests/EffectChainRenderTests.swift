// EffectChainRenderTests.swift — FX-001-T10: the effect chain (FX-001-R2, R12, R14, S7;
// contracts/post-process-effect.md). Skips where no Metal device exists.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
import XCTest
@testable import VisualGenerators
@testable import VisualEffects

final class EffectChainRenderTests: XCTestCase {
    private let format: MTLPixelFormat = .rgba16Float

    /// A "generator" that blits a fixed image into whatever texture it is given.
    private func blitSource(_ image: MTLTexture, commands: MTLCommandBuffer) -> (MTLTexture) -> Bool {
        { target in
            guard target.width == image.width, target.height == image.height,
                  let blit = commands.makeBlitCommandEncoder() else { return false }
            blit.copy(from: image, to: target)
            blit.endEncoding()
            return true
        }
    }

    private func runChain(_ rig: RenderRig, _ chain: EffectChain, input: PixelImage,
                          sourceTargets: inout [ObjectIdentifier]) throws -> [UInt8] {
        let image = try rig.upload(input, format: format)
        let output = try rig.makeTexture(width: input.width, height: input.height, format: format)
        try chain.prepare(width: input.width, height: input.height)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        let source = blitSource(image, commands: commands)
        var targets: [ObjectIdentifier] = []
        XCTAssertTrue(chain.encode(output: output, commandBuffer: commands) { target in
            targets.append(ObjectIdentifier(target))
            return source(target)
        })
        let buffer = try rig.encodeReadBack(output, commands: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed)
        sourceTargets = targets.map { $0 == ObjectIdentifier(output) ? ObjectIdentifier(RenderRig.self) : $0 }
        return RenderRig.bytes(of: buffer)
    }

    private func directBloom(_ rig: RenderRig, _ parameters: BloomParameters, input: PixelImage) throws -> [UInt8] {
        let effect = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: parameters) }
        try effect.prepare(width: input.width, height: input.height)
        let source = try rig.upload(input, format: format)
        let output = try rig.makeTexture(width: input.width, height: input.height, format: format)
        let commands = try XCTUnwrap(rig.queue.makeCommandBuffer())
        XCTAssertTrue(effect.encode(input: source, output: output, commandBuffer: commands))
        commands.commit()
        commands.waitUntilCompleted()
        return try rig.readBack(output)
    }

    private let input = PixelImage.patch(width: 120, height: 90, x0: 50, y0: 40, size: 10, color: Pixel(1, 1, 1, 1))

    func testNoActiveEffectLetsTheSourceDrawStraightIntoTheOutput() throws {
        let rig = try RenderRig()
        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: BloomParameters(enabled: false)) }
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
        XCTAssertEqual(chain.activeEffectCount, 0)
        var targets: [ObjectIdentifier] = []
        let bytes = try runChain(rig, chain, input: input, sourceTargets: &targets)
        XCTAssertEqual(targets, [ObjectIdentifier(RenderRig.self)], "the source drew into the output itself")
        XCTAssertEqual(bytes, rig.bytes(of: input, format: format), "VIS-001's picture, bit for bit (FX-001-S7)")
    }

    func testOneBloomMatchesTheEffectAppliedDirectly() throws {
        let rig = try RenderRig()
        let p = BloomParameters(enabled: true, intensity: 0.9, radius: 0.05, threshold: 0.4)
        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: p) }
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
        XCTAssertEqual(chain.activeEffectCount, 1)
        var targets: [ObjectIdentifier] = []
        let bytes = try runChain(rig, chain, input: input, sourceTargets: &targets)
        XCTAssertEqual(targets.count, 1)
        XCTAssertNotEqual(targets[0], ObjectIdentifier(RenderRig.self), "the source drew into the chain's image")
        XCTAssertEqual(bytes, try directBloom(rig, p, input: input))
    }

    func testTwoEffectsPingPongAndApplyInOrder() throws {
        let rig = try RenderRig()
        let p1 = BloomParameters(enabled: true, intensity: 0.5, radius: 0.02, threshold: 0.5)
        let p2 = BloomParameters(enabled: true, intensity: 0.7, radius: 0.06, threshold: 0.3)
        let b1 = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: p1) }
        let b2 = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: p2) }
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [b1, b2])
        var targets: [ObjectIdentifier] = []
        let bytes = try runChain(rig, chain, input: input, sourceTargets: &targets)
        // Expected: b2(b1(input)), computed with two direct passes.
        let first = rig.decode(try directBloom(rig, p1, input: input), width: input.width, height: input.height, format: format)
        XCTAssertEqual(bytes, try directBloom(rig, p2, input: first))
    }

    func testResizeReallocatesOncePerSizeAndParametersNeverReallocate() throws {
        let rig = try RenderRig()
        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format,
                                                    parameters: BloomParameters(enabled: true, intensity: 1, radius: 0.005)) }
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
        try chain.prepare(width: 120, height: 90)
        let g0 = chain.resourceGeneration, e0 = bloom.resourceGeneration
        try chain.prepare(width: 120, height: 90)
        XCTAssertEqual(chain.resourceGeneration, g0, "same size: nothing created")
        XCTAssertEqual(bloom.resourceGeneration, e0)
        for radius: Float in [0.06, 0.03, 0.005] {   // D changes 2 → … ; still no texture created (FX-001-R12)
            bloom.parameters = BloomParameters(enabled: true, intensity: 1, radius: radius)
            try chain.prepare(width: 120, height: 90)
            XCTAssertEqual(bloom.resourceGeneration, e0, "radius \(radius)")
        }
        try chain.prepare(width: 90, height: 120)
        XCTAssertEqual(chain.resourceGeneration, g0 + 1)
        XCTAssertEqual(bloom.resourceGeneration, e0 + 1)
        // Correct at the new size.
        let rotated = PixelImage.patch(width: 90, height: 120, x0: 40, y0: 50, size: 10, color: Pixel(1, 1, 1, 1))
        var targets: [ObjectIdentifier] = []
        let p = bloom.parameters
        let bytes = try runChain(rig, chain, input: rotated, sourceTargets: &targets)
        XCTAssertEqual(bytes, try directBloom(rig, p, input: rotated))
    }

    func testTogglingTheEffectSwitchesBetweenDirectDrawingAndTheChain() throws {
        let rig = try RenderRig()
        let bloom = try rig.build { try BloomEffect(device: rig.device, pixelFormat: format, parameters: BloomParameters(enabled: true, intensity: 1)) }
        let chain = try EffectChain(device: rig.device, pixelFormat: format, effects: [bloom])
        var targets: [ObjectIdentifier] = []
        _ = try runChain(rig, chain, input: input, sourceTargets: &targets)
        XCTAssertNotEqual(targets, [ObjectIdentifier(RenderRig.self)])
        bloom.parameters.enabled = false
        let bytes = try runChain(rig, chain, input: input, sourceTargets: &targets)
        XCTAssertEqual(targets, [ObjectIdentifier(RenderRig.self)])
        XCTAssertEqual(bytes, rig.bytes(of: input, format: format))
        XCTAssertThrowsError(try EffectChain(device: rig.device, pixelFormat: .bgra8Unorm_srgb, effects: [bloom]),
                             "an effect of another pixel format is refused")
    }
}
#endif
