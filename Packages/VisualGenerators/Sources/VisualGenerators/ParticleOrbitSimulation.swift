// ParticleOrbitSimulation.swift — the particle orbit's state and fixed-step motion (VIS-009-R2 to R6, R9;
// contracts/particle-orbit.md C1; research VIS-009-D3, D4, D5).
//
// 256 slots, each with a phase, an angular speed and a radial offset drawn from SplitMix64 (three draws per slot, in
// slot order, so changing the particle count never changes another slot), and a FIFO of 16 pending beats, all
// allocated in `init` (Constitution VII). Time is the injected frame clock in monotonic nanoseconds; steps follow
// VIS-008's schedule (step k starts at anchor + ⌊k·10⁹/240⌋). Per step: beats due at the step's start set the pulse to
// 1; the radius moves toward the target by a one-pole step limited to rate·Δt; the pulse decays; every drawn slot's
// phase advances. The target is set per frame (`setTarget(base:bass:)`) and held between frames. No clock is read; no
// allocation. Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public final class ParticleOrbitSimulation {
    public static let capacity = ParticleOrbitConfiguration.capacity
    public static let beatQueueCapacity = ParticleOrbitConfiguration.beatQueueCapacity
    /// Δt, seconds.
    public static let stepSeconds = 1.0 / Double(ParticleOrbitConfiguration.stepsPerSecond)
    private static let twoPi = 2 * Double.pi

    public var configuration: ParticleOrbitConfiguration {
        didSet {
            configuration = configuration.clamped()
            if configuration.seed != oldValue.seed { reseed() }
        }
    }

    private let phases: UnsafeMutablePointer<Double>
    private let speeds: UnsafeMutablePointer<Double>
    private let offsets: UnsafeMutablePointer<Double>
    private let beatTimes: UnsafeMutablePointer<UInt64>
    private var queueHead = 0
    private var queueCount = 0
    /// Step 0's start; nil until the first advance after a reset.
    public private(set) var anchorNanoseconds: UInt64?
    /// Steps run since the anchor.
    public private(set) var stepIndex: UInt64 = 0

    /// The current orbit radius (R).
    public private(set) var radius: Double
    /// The radius the orbit moves toward (R), from the last `setTarget`.
    public private(set) var targetRadius: Double
    /// The beat pulse, 1 at a beat decaying to 0.
    public private(set) var pulse = 0.0
    /// Fixed steps run since the last reset.
    public private(set) var stepsRun = 0
    /// Σ particles advanced over all steps since the last reset (the work counter, research VIS-009-D5).
    public private(set) var particleSteps = 0
    /// Beats applied, and beats that did not fit in the queue.
    public private(set) var beatsApplied = 0
    public private(set) var droppedBeats = 0
    /// Long gaps skipped (VIS-008-R3's rule).
    public private(set) var skippedGaps = 0

    public init(configuration: ParticleOrbitConfiguration = ParticleOrbitConfiguration()) {
        let c = configuration.clamped()
        self.configuration = c
        let r0: Double = ParticleOrbitConfiguration.targetRadius(base: c.radius, bass: 0, depth: c.bassDepth)
        radius = r0
        targetRadius = r0
        let n = Self.capacity
        phases = .allocate(capacity: n); phases.initialize(repeating: 0, count: n)
        speeds = .allocate(capacity: n); speeds.initialize(repeating: 0, count: n)
        offsets = .allocate(capacity: n); offsets.initialize(repeating: 1, count: n)
        beatTimes = .allocate(capacity: Self.beatQueueCapacity); beatTimes.initialize(repeating: 0, count: Self.beatQueueCapacity)
        reseed()
    }

    deinit {
        let n = Self.capacity
        phases.deinitialize(count: n); phases.deallocate()
        speeds.deinitialize(count: n); speeds.deallocate()
        offsets.deinitialize(count: n); offsets.deallocate()
        beatTimes.deinitialize(count: Self.beatQueueCapacity); beatTimes.deallocate()
    }

    // Storage introspection for the allocation tests.
    var storageAddresses: [UInt] {
        [UInt(bitPattern: phases), UInt(bitPattern: speeds), UInt(bitPattern: offsets), UInt(bitPattern: beatTimes)]
    }

    /// Particles drawn now.
    public var count: Int { configuration.particleCount }
    /// Slot `k`'s phase (radians, 0…2π), speed factor (× `angularSpeed`, before Reduce Motion) and radial offset.
    public func phase(_ k: Int) -> Double { phases[k] }
    public func speed(_ k: Int) -> Double { speeds[k] }
    public func offset(_ k: Int) -> Double { offsets[k] }
    /// Beats waiting for their step.
    public var pendingBeats: Int { queueCount }

    /// The loop restart: reseeds every slot, radius = target = the base, no pulse, no queued beat, no anchor.
    public func reset() {
        reseed()
        let r0: Double = ParticleOrbitConfiguration.targetRadius(base: configuration.radius, bass: 0, depth: configuration.bassDepth)
        radius = r0
        targetRadius = r0
        pulse = 0
        queueHead = 0
        queueCount = 0
        anchorNanoseconds = nil
        stepIndex = 0
        stepsRun = 0
        particleSteps = 0
        beatsApplied = 0
        droppedBeats = 0
        skippedGaps = 0
    }

    private func reseed() {
        var rng = SplitMix64(seed: configuration.seed)
        let spread: Double = ParticleOrbitConfiguration.offsetSpread
        for k in 0..<Self.capacity {
            phases[k] = Self.twoPi * rng.unit()
            speeds[k] = ParticleOrbitConfiguration.speedLow + ParticleOrbitConfiguration.speedSpan * rng.unit()
            offsets[k] = 1 + spread * (2 * rng.unit() - 1)
        }
    }

    /// VIS-009-R3: the target for this frame's steps (held until the next call).
    public func setTarget(base: Double, bass: Double) {
        targetRadius = ParticleOrbitConfiguration.targetRadius(base: base, bass: bass, depth: configuration.bassDepth)
    }

    /// Queues a beat at `nanoseconds` (the frame clock). Returns false when the queue is full (counted).
    @discardableResult
    public func enqueueBeat(atNanoseconds nanoseconds: UInt64) -> Bool {
        guard queueCount < Self.beatQueueCapacity else {
            droppedBeats += 1
            return false
        }
        beatTimes[(queueHead + queueCount) % Self.beatQueueCapacity] = nanoseconds
        queueCount += 1
        return true
    }

    /// The start of step `k` after the anchor, nanoseconds (exact integer arithmetic).
    static func stepOffset(_ k: UInt64) -> UInt64 {
        k &* 1_000_000_000 / UInt64(ParticleOrbitConfiguration.stepsPerSecond)
    }

    /// Runs every step that ends at or before `nanoseconds` (at most 240; the rest of a longer gap is skipped and the
    /// anchor moves to `nanoseconds`). The first call after a reset only sets the anchor. Earlier times do nothing.
    public func advance(toNanoseconds nanoseconds: UInt64) {
        guard let anchor = anchorNanoseconds else {
            anchorNanoseconds = nanoseconds
            stepIndex = 0
            return
        }
        guard nanoseconds >= anchor else { return }
        let c = configuration
        let dt: Double = Self.stepSeconds
        let gain: Double = 1 - exp(-dt / c.effectiveRadiusTimeConstant)
        let limit: Double = c.effectiveRadiusRate * dt
        let decay: Double = exp(-dt / ParticleOrbitConfiguration.pulseTimeConstant)
        let turn: Double = c.angularSpeed * c.speedScale * dt
        var steps = 0
        while steps < ParticleOrbitConfiguration.maximumStepsPerAdvance {
            let end: UInt64 = anchor &+ Self.stepOffset(stepIndex &+ 1)
            guard end <= nanoseconds else { return }
            applyBeats(atOrBefore: anchor &+ Self.stepOffset(stepIndex))
            step(gain: gain, limit: limit, decay: decay, turn: turn, count: c.particleCount)
            stepIndex &+= 1
            steps += 1
        }
        if anchor &+ Self.stepOffset(stepIndex &+ 1) <= nanoseconds {
            anchorNanoseconds = nanoseconds   // a stall: skip the rest of the gap
            stepIndex = 0
            skippedGaps += 1
        }
    }

    private func applyBeats(atOrBefore start: UInt64) {
        while queueCount > 0, beatTimes[queueHead] <= start {
            pulse = 1
            beatsApplied += 1
            queueHead = (queueHead + 1) % Self.beatQueueCapacity
            queueCount -= 1
        }
    }

    private func step(gain: Double, limit: Double, decay: Double, turn: Double, count: Int) {
        let delta: Double = min(max((targetRadius - radius) * gain, -limit), limit)
        radius = min(max(radius + delta, ParticleOrbitConfiguration.minimumRadius), ParticleOrbitConfiguration.maximumRadius)
        pulse *= decay
        for k in 0..<count {
            var p: Double = phases[k] + speeds[k] * turn
            if p >= Self.twoPi { p -= Self.twoPi }
            phases[k] = p
        }
        stepsRun += 1
        particleSteps += count
    }
}
