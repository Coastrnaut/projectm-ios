// MetalGPUFrameTimes.swift — the whole frame's GPU time from committed command buffers (PERF-001-R6;
// contracts/frame-stage-timer.md C5; research PERF-001-D3).
//
// No completion handler (it would allocate a closure per frame and run on a Metal thread): the frame thread
// keeps the last few committed command buffers and, at its next frames, reads `gpuStartTime`/`gpuEndTime` of
// those that completed. A start time of 0 or less means the platform gave none (unavailable, not 0 ms).
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

public final class MetalGPUFrameTimes {
    public static let slotCount = 4
    private var pending: [MTLCommandBuffer?] = Array(repeating: nil, count: MetalGPUFrameTimes.slotCount)
    private var nextSlot = 0

    public init() {}

    /// Keeps a committed command buffer until it completes; when every slot is busy the oldest is dropped.
    public func track(_ commandBuffer: MTLCommandBuffer) {
        pending[nextSlot] = commandBuffer
        nextSlot = (nextSlot + 1) % Self.slotCount
    }

    /// Records the GPU time of every completed command buffer and forgets it; failed ones are dropped.
    public func drain(into timer: FrameStageTimer) {
        for slot in 0..<Self.slotCount {
            guard let buffer = pending[slot] else { continue }
            switch buffer.status {
            case .completed:
                pending[slot] = nil
                let start: Double = buffer.gpuStartTime
                let end: Double = buffer.gpuEndTime
                guard start > 0, end > 0 else { continue }   // no GPU timestamps: unavailable
                timer.recordFrameGPU(seconds: end - start)   // a negative or non-finite value is rejected
            case .error:
                pending[slot] = nil
            default:
                continue
            }
        }
    }

    public func reset() {
        for slot in 0..<Self.slotCount { pending[slot] = nil }
        nextSlot = 0
    }
}
#endif
