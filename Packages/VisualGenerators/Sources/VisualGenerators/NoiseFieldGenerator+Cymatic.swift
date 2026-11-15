// NoiseFieldGenerator+Cymatic.swift — VIS-019's frame step in the noise field generator (contract C2) and the tests-only
// mask view (research VIS-019-D5), kept out of NoiseFieldGenerator.swift so the shared generator gains only one-line
// hooks. Per frame: entering the mode resets the drive to rest; the drive advances on the frame context's clock with the
// bands of the selected range; the 40-float block is written from the drive's frame; the 64 flash samples come from the
// CPU mirror. No allocation.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

extension NoiseFieldGenerator {
    /// VIS-019: one frame's drive step, uniform block and flash samples.
    func advanceCymatic(settings: CymaticSettings, bands: UnsafeBufferPointer<Float>, context: VisualFrameContext, entering: Bool,
                        width: Int, height: Int) {
        if entering { cymaticDrive.reset() }
        cymaticDrive.advance(bands: bands, range: settings.bands, timeNanoseconds: context.timeNanoseconds,
                             reduceMotion: configuration.reduceMotion)
        let frame: CymaticFrame = writeCymaticUniforms()
        flashAreas.sampleCymatic(frame: frame, paletteStops: paletteStopsBlock, width: width, height: height)
    }

    /// VIS-019: writes the block from the drive's frame; returns the frame.
    @discardableResult
    func writeCymaticUniforms() -> CymaticFrame {
        let frame: CymaticFrame = cymaticDrive.frame
        for k in 0..<CymaticField.modeCount {
            let mode: CymaticMode = CymaticField.modes[k]
            cymUniforms[4 * k] = mode.n
            cymUniforms[4 * k + 1] = mode.m
            cymUniforms[4 * k + 2] = mode.sign
            cymUniforms[4 * k + 3] = frame.weights[k]
        }
        let base: Int = 4 * CymaticField.modeCount
        cymUniforms[base] = frame.amplitude
        cymUniforms[base + 1] = frame.width
        cymUniforms[base + 2] = frame.paletteT
        cymUniforms[base + 3] = frame.fill
        return frame
    }

    /// VIS-019 (tests): the cymatic block the next draw uses.
    var cymaticUniforms: [Float] { (0..<CymaticShader.uniformFloats).map { (k: Int) -> Float in cymUniforms[k] } }

    /// VIS-019-D5 (tests): a pipeline drawing each pixel's blended displacement in red and line intensity in green.
    func makeCymaticMaskPipeline(format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        guard let vertex = library.makeFunction(name: "vis_noise_vertex"),
              let fragment = library.makeFunction(name: "vis_cym_mask_fragment") else {
            throw VisualGeneratorError.pipelineUnavailable("shader functions missing")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "VIS-019 Cymatic mask (tests)"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = format
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// VIS-019 (tests): draws the mask view of the drive's current frame into `target` with `state`.
    func encodeCymaticMask(into target: MTLTexture, commandBuffer: MTLCommandBuffer, state: MTLRenderPipelineState) -> Bool {
        guard configuration.cymatic != nil else { return false }
        writeCymaticUniforms()
        writeSharedUniforms(width: target.width, height: target.height, gain: 1)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(sharedUniformBlock, length: Self.uniformFloats * MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentBytes(cymUniforms, length: CymaticShader.uniformFloats * MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }
}
#endif
