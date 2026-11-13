// CompositeFlashGuard.swift — FX-019's strobe safety envelope on the finished composite
// (CMP-001-R10; ADR-0013 decision 6; research CMP-001-D4). T07 stub: gain 1 (pass-through) until
// CMP-001-T13.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class CompositeFlashGuard {
    let gainBuffer: MTLBuffer

    init(device: MTLDevice) throws(CompositorError) {
        var one: Float = 1
        guard let buffer = device.makeBuffer(bytes: &one, length: MemoryLayout<Float>.size, options: .storageModeShared) else {
            throw .pipelineUnavailable("flash guard gain buffer")
        }
        gainBuffer = buffer
    }

    func reset() {}

    func encode(composite: MTLTexture, commandBuffer: MTLCommandBuffer, frameDuration: Double, reduceFlashing: Bool) -> Bool {
        true
    }
}
#endif
