// MetalOutputPacing.swift — OUT-013 (specs/281-out-013-frame-pacing, contract C4; research OUT-013-D2, D4): the Metal
// visuals' frames in flight. Native spectra, Camera, Photo, Video and Text each own one.
//
// * `begin()` before the drawable request: false while two frames are in flight (the tick is dropped and counted; the
//   frame loop returns as it did when `nextDrawable()` gave nothing). Never waits.
// * `nextDrawable(from:refreshInterval:)` times the request with the host clock; a nil drawable returns the slot
//   (counted), a wait longer than half the refresh interval skips the next tick (OUT-013-R7).
// * `track(_:)` adds the command buffer's completed handler, which returns the slot from Metal's thread (atomics only).
// * `configure(_:)` states the layer's drawable policy (three drawables, the 1 s timeout on; OUT-013-R6).
// * DEBUG `holdCompletions`: completions are kept (a slow output) until `releaseHeldCompletions()` (tests). The held
//   list can never exceed the bound, because no frame begins while it is full.
import FrameTiming
import Metal
import QuartzCore

@MainActor
final class MetalOutputPacing {
    let gate: OutputFrameGate
    private let clock: () -> CFTimeInterval
    #if DEBUG
    /// Tests: completions are held instead of returning the slot (a slow output).
    var holdCompletions = false
    private let held = HeldCompletions()
    #endif

    init(gate: OutputFrameGate = OutputFrameGate(), clock: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.gate = gate
        self.clock = clock
    }

    /// The counts (OUT-013-R5).
    var counts: OutputPacingCounts { gate.counts }

    /// OUT-013-R6: three drawables and a bounded drawable wait, stated rather than assumed.
    static func configure(_ layer: CAMetalLayer) {
        layer.maximumDrawableCount = 3
        layer.allowsNextDrawableTimeout = true
    }

    /// True: render this tick. False: dropped (counted).
    func begin() -> Bool {
        gate.tryBegin()
    }

    /// The next drawable after a successful `begin()`; nil returns the slot (counted). The wait is timed.
    func nextDrawable(from layer: CAMetalLayer, refreshInterval: Double) -> CAMetalDrawable? {
        let start: CFTimeInterval = clock()
        let drawable: CAMetalDrawable? = layer.nextDrawable()
        gate.noteDrawableWait(clock() - start, refreshInterval: refreshInterval)
        if drawable == nil { gate.abandon() }
        return drawable
    }

    /// A begun frame that will not be committed (nothing drawn, no command buffer).
    func abandon() {
        gate.abandon()
    }

    /// Before `commit`: the frame leaves flight when the GPU completes it.
    func track(_ commands: MTLCommandBuffer) {
        let gate = self.gate
        #if DEBUG
        if holdCompletions {
            held.add(gate)
            return
        }
        #endif
        commands.addCompletedHandler { (_: MTLCommandBuffer) in gate.complete() }
    }

    #if DEBUG
    /// Tests: the held frames complete now.
    func releaseHeldCompletions() {
        held.releaseAll()
    }

    /// Tests: frames held now (never above the bound).
    var heldCount: Int { held.count }
    #endif
}

#if DEBUG
/// The held completions of a "slow output" (tests).
@MainActor
private final class HeldCompletions {
    private var gates: [OutputFrameGate] = []
    var count: Int { gates.count }
    func add(_ gate: OutputFrameGate) { gates.append(gate) }
    func releaseAll() {
        for gate in gates { gate.complete() }
        gates.removeAll()
    }
}
#endif
