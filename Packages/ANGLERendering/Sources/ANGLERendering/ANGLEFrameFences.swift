// ANGLEFrameFences.swift — OUT-013 (specs/281-out-013-frame-pacing, contract C3; research OUT-013-D2, D3): projectM's
// frames in flight on ANGLE. ANGLE submits the Metal work itself, so a frame's completion is observed through a GL ES
// 3.0 fence inserted after the frame and polled with a zero timeout at the next ticks, on the render (main) thread.
// Nothing waits. The ring has the gate's capacity, so it never grows; a fence that cannot be created completes its
// frame at once (the gate is never left holding a slot).
import CANGLE
import FrameTiming

@MainActor
final class ANGLEFrameFences {
    let gate: OutputFrameGate
    private var fences: [UnsafeMutableRawPointer] = []
    #if DEBUG
    /// Tests: fences read as unsignalled while set (a slow output).
    var holdFences = false
    #endif

    init(gate: OutputFrameGate) {
        self.gate = gate
        fences.reserveCapacity(gate.policy.maxFramesInFlight)
    }

    /// Fences outstanding (tests; never above the gate's bound).
    var outstanding: Int { fences.count }

    /// After a presented frame, with its context current.
    func frameSubmitted() {
        guard let fence = PMANGLEFenceInsert() else {
            gate.complete()
            return
        }
        fences.append(fence)
    }

    /// Retires every signalled fence, oldest first (fences signal in order), with the context current.
    func poll() {
        #if DEBUG
        if holdFences { return }
        #endif
        while let first = fences.first, PMANGLEFencePoll(first) != 0 {
            PMANGLEFenceDelete(first)
            fences.removeFirst()
            gate.complete()
        }
    }

    /// Releases every fence (surface loss, teardown), with the context current; their frames count as completed.
    func drain() {
        for fence in fences {
            PMANGLEFenceDelete(fence)
            gate.complete()
        }
        fences.removeAll(keepingCapacity: true)
    }
}
