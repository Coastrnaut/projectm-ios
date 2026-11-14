// NonFiniteOutputCounter.swift — FX-002-R7 (research FX-002-D4; ADR-0047): the buffers `cmp_output` counts
// non-finite composite pixels into (fragment buffer index 1). The screen pass binds `counter`; recording and
// capture passes bind `sink`, so a recorded or captured frame is not counted twice. Two 4-byte shared buffers
// per compositor or bus, created once; nothing per frame. Not Sendable: one thread drives its owner.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

final class NonFiniteOutputCounter {
    /// The screen pass's counter (relaxed atomic adds on the GPU).
    let counter: MTLBuffer
    /// Bound by every other output pass; never read.
    let sink: MTLBuffer

    init(device: MTLDevice) throws(CompositorError) {
        guard let counter = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared),
              let sink = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared) else {
            throw .pipelineUnavailable("tone map counter buffers")
        }
        counter.contents().storeBytes(of: 0, as: UInt32.self)
        sink.contents().storeBytes(of: 0, as: UInt32.self)
        counter.label = "FX-002 non-finite output pixels"
        sink.label = "FX-002 non-finite sink"
        self.counter = counter
        self.sink = sink
    }

    /// Non-finite composite pixels the screen pass met so far (exact once the last frame's command buffer completed).
    var count: UInt32 { counter.contents().load(as: UInt32.self) }
}
#endif
