// ParticleFountainSimulation.swift — the particle fountain's state and fixed-step physics (VIS-008-R2 to R6, R9;
// contracts/particle-fountain.md C1; research VIS-008-D3, D4).
//
// A pool of 512 particles (dense: slots 0..<liveCount, a dead particle is replaced by the last one) and a FIFO of
// 32 pending onsets, both allocated in `init` (Constitution VII). Time is the injected frame clock in monotonic
// nanoseconds: step k starts at anchor + ⌊k·10⁹/240⌋, so the schedule does not depend on how frames divide time.
// `advance(toNanoseconds:)` runs every step that ends at or before the target; before step k it spawns every
// queued onset whose time is at or before the step's start (FIFO, so the generator's draws come in a fixed order).
// Semi-implicit Euler: v ← v + (g − k·v)Δt, then p ← p + v·Δt. Each particle carries its own gravity, drag and
// life, captured at spawn, so a configuration change applies to later bursts. No clock is read; no allocation.
// Not Sendable: one owner.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One particle. Lengths in R (half the output's shorter side) from the emitter, y up; seconds.
public struct FountainParticle: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var age: Double
    public var life: Double
    public var gravity: Double
    public var drag: Double
    /// 0 for the first particle spawned since the last reset, then +1.
    public var sequence: Int

    public init(x: Double, y: Double, vx: Double, vy: Double, age: Double, life: Double, gravity: Double, drag: Double,
                sequence: Int) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.age = age
        self.life = life
        self.gravity = gravity
        self.drag = drag
        self.sequence = sequence
    }

    static let zero = FountainParticle(x: 0, y: 0, vx: 0, vy: 0, age: 0, life: 1, gravity: 0, drag: 0, sequence: 0)
}

public final class ParticleFountainSimulation {
    public static let capacity = ParticleFountainConfiguration.capacity
    public static let onsetQueueCapacity = ParticleFountainConfiguration.onsetQueueCapacity
    /// Δt, seconds.
    public static let stepSeconds = 1.0 / Double(ParticleFountainConfiguration.stepsPerSecond)

    public var configuration: ParticleFountainConfiguration {
        didSet { configuration = configuration.clamped() }
    }

    private let particles: UnsafeMutablePointer<FountainParticle>
    private let onsetTimes: UnsafeMutablePointer<UInt64>
    private let onsetStrengths: UnsafeMutablePointer<Float>
    private let onsetThresholds: UnsafeMutablePointer<Float>
    private var queueHead = 0
    private var queueCount = 0
    private var rng: SplitMix64
    /// Step 0's start; nil until the first advance after a reset.
    public private(set) var anchorNanoseconds: UInt64?
    /// Steps run since the anchor.
    public private(set) var stepIndex: UInt64 = 0

    /// Particles alive now (≤ capacity).
    public private(set) var liveCount = 0
    /// Particles spawned since the last reset (the next particle's sequence).
    public private(set) var spawnedCount = 0
    /// Particles of bursts that did not fit in the pool.
    public private(set) var droppedParticles = 0
    /// Onsets that did not fit in the queue.
    public private(set) var droppedOnsets = 0
    /// Steps skipped by long gaps (VIS-008-R3).
    public private(set) var skippedGaps = 0

    public init(configuration: ParticleFountainConfiguration = ParticleFountainConfiguration()) {
        self.configuration = configuration.clamped()
        rng = SplitMix64(seed: configuration.seed)
        particles = .allocate(capacity: Self.capacity)
        particles.initialize(repeating: .zero, count: Self.capacity)
        onsetTimes = .allocate(capacity: Self.onsetQueueCapacity)
        onsetTimes.initialize(repeating: 0, count: Self.onsetQueueCapacity)
        onsetStrengths = .allocate(capacity: Self.onsetQueueCapacity)
        onsetStrengths.initialize(repeating: 0, count: Self.onsetQueueCapacity)
        onsetThresholds = .allocate(capacity: Self.onsetQueueCapacity)
        onsetThresholds.initialize(repeating: 0, count: Self.onsetQueueCapacity)
    }

    deinit {
        particles.deinitialize(count: Self.capacity); particles.deallocate()
        onsetTimes.deinitialize(count: Self.onsetQueueCapacity); onsetTimes.deallocate()
        onsetStrengths.deinitialize(count: Self.onsetQueueCapacity); onsetStrengths.deallocate()
        onsetThresholds.deinitialize(count: Self.onsetQueueCapacity); onsetThresholds.deallocate()
    }

    // Storage introspection for the allocation tests.
    var storageAddresses: [UInt] {
        [UInt(bitPattern: particles), UInt(bitPattern: onsetTimes), UInt(bitPattern: onsetStrengths),
         UInt(bitPattern: onsetThresholds)]
    }

    /// Forgets every particle and pending onset, restores the seed and the anchor (the host's loop restart).
    public func reset() {
        liveCount = 0
        spawnedCount = 0
        droppedParticles = 0
        droppedOnsets = 0
        skippedGaps = 0
        queueHead = 0
        queueCount = 0
        anchorNanoseconds = nil
        stepIndex = 0
        rng = SplitMix64(seed: configuration.seed)
    }

    /// Onsets waiting for their step.
    public var pendingOnsets: Int { queueCount }

    /// Live particle `i` (0..<liveCount).
    public func particle(_ i: Int) -> FountainParticle { particles[i] }

    /// The live particles (tests and diagnostics; allocates).
    public var liveParticles: [FountainParticle] { (0..<liveCount).map { (i: Int) -> FountainParticle in particles[i] } }

    /// The start of step `k` after the anchor, nanoseconds (exact integer arithmetic).
    static func stepOffset(_ k: UInt64) -> UInt64 {
        k &* 1_000_000_000 / UInt64(ParticleFountainConfiguration.stepsPerSecond)
    }

    /// Where the simulation stands: the start of the next step (nil before the first advance).
    public var simulatedNanoseconds: UInt64? { anchorNanoseconds.map { $0 &+ Self.stepOffset(stepIndex) } }

    /// Queues an onset at `nanoseconds` (the frame clock). Returns false when the queue is full (counted).
    @discardableResult
    public func enqueueOnset(atNanoseconds nanoseconds: UInt64, strength: Float, threshold: Float) -> Bool {
        guard queueCount < Self.onsetQueueCapacity else {
            droppedOnsets += 1
            return false
        }
        let slot = (queueHead + queueCount) % Self.onsetQueueCapacity
        onsetTimes[slot] = nanoseconds
        onsetStrengths[slot] = strength
        onsetThresholds[slot] = threshold
        queueCount += 1
        return true
    }

    /// Runs every step that ends at or before `nanoseconds` (at most 240; the rest of a longer gap is skipped and
    /// the anchor moves to `nanoseconds`). The first call after a reset only sets the anchor. Earlier times do
    /// nothing.
    public func advance(toNanoseconds nanoseconds: UInt64) {
        guard let anchor = anchorNanoseconds else {
            anchorNanoseconds = nanoseconds
            stepIndex = 0
            return
        }
        guard nanoseconds >= anchor else { return }
        var steps = 0
        while steps < ParticleFountainConfiguration.maximumStepsPerAdvance {
            let end: UInt64 = anchor &+ Self.stepOffset(stepIndex &+ 1)
            guard end <= nanoseconds else { return }
            spawnDue(atOrBefore: anchor &+ Self.stepOffset(stepIndex))
            step()
            stepIndex &+= 1
            steps += 1
        }
        if anchor &+ Self.stepOffset(stepIndex &+ 1) <= nanoseconds {
            anchorNanoseconds = nanoseconds   // a stall: skip the rest of the gap
            stepIndex = 0
            skippedGaps += 1
        }
    }

    private func spawnDue(atOrBefore start: UInt64) {
        while queueCount > 0, onsetTimes[queueHead] <= start {
            spawnBurst(strength: onsetStrengths[queueHead], threshold: onsetThresholds[queueHead])
            queueHead = (queueHead + 1) % Self.onsetQueueCapacity
            queueCount -= 1
        }
    }

    /// VIS-008-R2, R9: a burst at the emitter; truncated when the pool is full (counted).
    private func spawnBurst(strength: Float, threshold: Float) {
        let c = configuration
        let n = ParticleFountainConfiguration.burstSize(strength: strength, threshold: threshold, reduceMotion: c.reduceMotion)
        let scale: Double = c.timeScale
        let gravity: Double = c.effectiveGravity, drag: Double = c.effectiveDrag, life: Double = c.effectiveLife
        let cone: Double = ParticleFountainConfiguration.coneHalfAngle
        let low: Double = ParticleFountainConfiguration.minimumSpeed
        let span: Double = ParticleFountainConfiguration.maximumSpeed - low
        for i in 0..<n {
            guard liveCount < Self.capacity else {
                droppedParticles += n - i
                return
            }
            let angle: Double = (2 * rng.unit() - 1) * cone
            let speed: Double = (low + span * rng.unit()) * scale
            particles[liveCount] = FountainParticle(x: 0, y: 0, vx: speed * sin(angle), vy: speed * cos(angle), age: 0,
                                                    life: life, gravity: gravity, drag: drag, sequence: spawnedCount)
            liveCount += 1
            spawnedCount += 1
        }
    }

    /// One Δt for every live particle; the dead are removed (the last particle takes the slot).
    private func step() {
        let dt: Double = Self.stepSeconds
        let floor: Double = ParticleFountainConfiguration.floorHeight
        let side: Double = ParticleFountainConfiguration.sideBound
        var i = 0
        while i < liveCount {
            var p = particles[i]
            p.vx += (-p.drag * p.vx) * dt
            p.vy += (-p.gravity - p.drag * p.vy) * dt
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.age += dt
            if p.age >= p.life || p.y < floor || abs(p.x) > side {
                liveCount -= 1
                particles[i] = particles[liveCount]
            } else {
                particles[i] = p
                i += 1
            }
        }
    }
}
