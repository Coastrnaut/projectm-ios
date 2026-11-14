// LFO.swift — clocked low-frequency oscillators, sine and triangle (MOD-007-R1 to R4, R6, R10;
// specs/156-mod-007-lfo, research MOD-007-D1 to D3, D5, contract L1 to L3).
//
// * The value is a pure function of the elapsed time since an origin, in integer nanoseconds:
//   φ = frac(phaseOffset + rate·t), value = clamp(center + amplitude/2 · w(φ), 0, 1), where w is
//   sin(2πφ) or the triangle with the same zero crossings and peaks (0, +1 at ¼, 0 at ½, −1 at ¾).
// * No accumulated state, so no drift. The phase splits t into whole seconds s and a remainder r; the
//   rounding error of rate·s is recovered exactly with a fused multiply-add, so the phase stays exact to
//   about 1e-16 cycles after hours or days (the acceptance tolerance is 1e-9).
// * The bank holds a scene's oscillators (at most 8) with one origin: the first sample after `set`.
//   `reduceFlashingMaximumRateHz` (3 Hz) is the effective-rate cap while Reduce flashing is on (FR-072,
//   ACC-012); the stored rate is unchanged.
// * MOD-009 (specs/165-mod-009-tempo-lfo, research MOD-009-D2, D3, contract T1 to T3): an optional `LFOSync` sets the
//   cycle in beats (¼…8); at a tempo the rate is BPM / 60 / beats (BPM clamped to 40…240), without one the stored
//   rate. The bank keeps a phase segment per synced slot and starts a new one, continuous, when the slot's effective
//   rate changes (tempo, tempo lost, Reduce flashing); at a constant rate it is the same exact closed form.
// * MOD-008 (specs/212-mod-008-stepped-lfo, research MOD-008-D1 to D6, contract S1 to S8): square (high while φ < duty
//   cycle, 0.05…0.95, default 0.5) and sample-and-hold (one seeded level per cycle, `SteppedRandom.level(seed:step:)`,
//   with an optional linear glide from the previous level). The step is the whole-cycle count from the same exact sum
//   as the phase (`cycle(…)`), and synced segments carry it across rate changes, so a level depends only on the seed
//   and the step, never on frame timing. Without a stored seed the seed derives from the slot.
// * Pure, allocation-free per sample; one owner (not `Sendable`), never from an audio callback
//   (Constitution VII). Foundation-free (the C math library only): builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The waveform of an oscillator; the raw value is the stored name.
public enum LFOShape: String, Sendable, Hashable, CaseIterable {
    case sine
    case triangle
    /// MOD-008: high for the first `LFO.dutyCycle` of each cycle, low for the rest.
    case square
    /// MOD-008: one seeded level per cycle (stored name `sampleHold`).
    case sampleHold

    /// The bipolar waveform (−1…1) at phase `phi` in 0…<1. Square uses a 50% duty here and sample-and-hold, which
    /// depends on the step and seed rather than the phase, reads 0 (the centre); `LFO.value(at:slot:)` evaluates both.
    public func wave(_ phi: Double) -> Double {
        switch self {
        case .square:
            return phi < 0.5 ? 1 : -1
        case .sampleHold:
            return 0
        case .sine:
            return sin(2 * Double.pi * phi)
        case .triangle:
            if phi < 0.25 { return 4 * phi }
            if phi < 0.75 { return 2 - 4 * phi }
            return 4 * phi - 4
        }
    }
}

/// Why an oscillator or a bank was refused.
public enum LFOError: Error, Sendable, Hashable, CustomStringConvertible {
    case invalidSettings(reason: String)
    case tooManyOscillators(limit: Int)

    public var description: String {
        switch self {
        case let .invalidSettings(reason): "invalid oscillator: \(reason)"
        case let .tooManyOscillators(limit): "at most \(limit) oscillators are allowed"
        }
    }
}

/// MOD-009: a tempo-synced cycle length in beats (one beat is a quarter note; contract T1).
public struct LFOSync: Sendable, Hashable {
    /// Beats per cycle: one of `allowedBeatsPerCycle`.
    public let beatsPerCycle: Double

    /// Straight lengths only (research MOD-009-D3); exact binary fractions, so stored numbers compare exactly.
    public static let allowedBeatsPerCycle: [Double] = [0.25, 0.5, 1, 2, 4, 8]
    public static let minimumBPM = 40.0
    public static let maximumBPM = 240.0

    public init(beatsPerCycle: Double) throws(LFOError) {
        guard Self.allowedBeatsPerCycle.contains(beatsPerCycle) else {
            throw .invalidSettings(reason: "the sync length must be ¼, ½, 1, 2, 4 or 8 beats")
        }
        self.beatsPerCycle = beatsPerCycle
    }

    /// Nil for no tempo (nil, non-finite or not positive); otherwise the BPM clamped to 40…240.
    public static func usableBPM(_ bpm: Double?) -> Double? {
        guard let bpm, bpm.isFinite, bpm > 0 else { return nil }
        return min(max(bpm, minimumBPM), maximumBPM)
    }

    /// Cycles per second at `bpm` (clamped to 40…240; a BPM `usableBPM` rejects reads as 40).
    public func rateHz(bpm: Double) -> Double {
        let tempo: Double = Self.usableBPM(bpm) ?? Self.minimumBPM
        return tempo / 60 / beatsPerCycle
    }
}

/// One low-frequency oscillator (contract L1, L2).
public struct LFO: Sendable, Hashable {
    public var shape: LFOShape
    /// Cycles per second (0.01…20).
    public var rateHz: Double
    /// The phase at the origin, in cycles (0…1; 1 is the same as 0).
    public var phaseOffset: Double
    /// The peak-to-peak swing as a fraction of 0…1 (0…1).
    public var amplitude: Double
    /// The middle of the swing (0…1).
    public var center: Double
    /// MOD-009: the tempo-synced cycle length; nil runs at `rateHz` (which stays the fallback without a tempo).
    public var sync: LFOSync?
    /// MOD-008: the fraction of a square cycle spent high (0.05…0.95).
    public var dutyCycle: Double
    /// MOD-008: the sample-and-hold seed; nil uses `SteppedRandom.defaultSeed(slot:)` for the oscillator's position.
    public var seed: UInt32?
    /// MOD-008: the fraction of a sample-and-hold step spent ramping from the previous level (0…1; 0 is a hard step).
    public var glide: Double

    public static let minimumRateHz = 0.01
    public static let maximumRateHz = 20.0
    public static let defaultPhaseOffset = 0.0
    public static let defaultAmplitude = 1.0
    public static let defaultCenter = 0.5
    public static let defaultDutyCycle = 0.5
    public static let minimumDutyCycle = 0.05
    public static let maximumDutyCycle = 0.95
    public static let defaultGlide = 0.0

    /// A validated oscillator; throws `LFOError.invalidSettings` when `validationProblem` is not nil.
    public init(shape: LFOShape, rateHz: Double, phaseOffset: Double = LFO.defaultPhaseOffset,
                amplitude: Double = LFO.defaultAmplitude, center: Double = LFO.defaultCenter, sync: LFOSync? = nil,
                dutyCycle: Double = LFO.defaultDutyCycle, seed: UInt32? = nil, glide: Double = LFO.defaultGlide) throws(LFOError) {
        self.shape = shape
        self.rateHz = rateHz
        self.phaseOffset = phaseOffset
        self.amplitude = amplitude
        self.center = center
        self.sync = sync
        self.dutyCycle = dutyCycle
        self.seed = seed
        self.glide = glide
        if let problem = validationProblem { throw .invalidSettings(reason: problem) }
    }

    /// Nil exactly when the settings are valid (MOD-007-R1).
    public var validationProblem: String? {
        guard rateHz.isFinite, rateHz >= Self.minimumRateHz, rateHz <= Self.maximumRateHz else {
            return "the rate must be \(Self.minimumRateHz)…\(Self.maximumRateHz) Hz"
        }
        guard phaseOffset.isFinite, phaseOffset >= 0, phaseOffset <= 1 else { return "the phase must be 0…1 cycle" }
        guard amplitude.isFinite, amplitude >= 0, amplitude <= 1 else { return "the amplitude must be 0…1" }
        guard center.isFinite, center >= 0, center <= 1 else { return "the center must be 0…1" }
        if let sync, !LFOSync.allowedBeatsPerCycle.contains(sync.beatsPerCycle) { return "the sync length is not allowed" }
        guard dutyCycle.isFinite, dutyCycle >= Self.minimumDutyCycle, dutyCycle <= Self.maximumDutyCycle else {
            return "the duty cycle must be \(Self.minimumDutyCycle)…\(Self.maximumDutyCycle)"
        }
        guard glide.isFinite, glide >= 0, glide <= 1 else { return "the glide must be 0…1" }
        return nil
    }

    /// MOD-009: the running rate: the synced rate at a usable tempo, else `rateHz`; at most `maximumRateHz`.
    public func effectiveRateHz(tempoBPM: Double?, maximumRateHz: Double = .infinity) -> Double {
        var rate: Double = rateHz
        if let sync, let bpm = LFOSync.usableBPM(tempoBPM) { rate = sync.rateHz(bpm: bpm) }
        return min(rate, maximumRateHz)
    }

    /// frac(phaseOffset + rateHz·t) in 0…<1, with t = `elapsedNanoseconds` (research MOD-007-D2).
    public func phase(elapsedNanoseconds: UInt64, rateHz rate: Double) -> Double {
        Self.phase(from: phaseOffset, elapsedNanoseconds: elapsedNanoseconds, rateHz: rate)
    }

    /// frac(start + rate·t) in 0…<1, exact for any running time: t is split into whole seconds and a remainder, and
    /// the rounding error of rate·seconds is recovered with a fused multiply-add (research MOD-007-D2; MOD-009 T2).
    public static func phase(from start: Double, elapsedNanoseconds: UInt64, rateHz rate: Double) -> Double {
        cycle(from: start, elapsedNanoseconds: elapsedNanoseconds, rateHz: rate).phase
    }

    /// MOD-008: the whole cycles and the phase of `startCycle + start + rate·t` from one exact sum (research
    /// MOD-008-D3): the phase is bit-identical to MOD-007's, and a time on a boundary is the new step at phase 0.
    public static func cycle(from start: Double, startCycle: Int64 = 0, elapsedNanoseconds: UInt64,
                             rateHz rate: Double) -> LFOCycle {
        let wholeSeconds = Double(elapsedNanoseconds / 1_000_000_000)   // exact below 2⁵³
        let remainder = Double(elapsedNanoseconds % 1_000_000_000) / 1e9
        let product: Double = rate * wholeSeconds
        let productError: Double = (-product).addingProduct(rate, wholeSeconds)   // exact rounding error of the product
        let productWhole: Double = product.rounded(.down)
        let productFraction: Double = product - productWhole                     // exact
        let cycles: Double = productFraction + productError + rate * remainder + start
        let cyclesWhole: Double = cycles.rounded(.down)
        var phi: Double = cycles - cyclesWhole
        var step: Int64 = startCycle &+ Self.wholeCycles(productWhole) &+ Self.wholeCycles(cyclesWhole)
        if !(phi < 1) {
            phi = 0
            step = step &+ 1
        }
        return LFOCycle(step: step, phase: phi)
    }

    /// A whole number of cycles as an integer (0 for a non-finite or out-of-range value, which valid rates never give).
    private static func wholeCycles(_ value: Double) -> Int64 {
        guard value.isFinite, abs(value) < 9.0e18 else { return 0 }
        return Int64(value)
    }

    /// MOD-008: the step and phase after `elapsedNanoseconds` at `rate`, from the phase offset.
    public func cycle(elapsedNanoseconds: UInt64, rateHz rate: Double) -> LFOCycle {
        Self.cycle(from: phaseOffset, elapsedNanoseconds: elapsedNanoseconds, rateHz: rate)
    }

    /// MOD-008: the sample-and-hold seed of the oscillator at `slot` (the stored seed, else the slot's default).
    public func effectiveSeed(slot: Int) -> UInt64 {
        if let seed { return UInt64(seed) }
        return SteppedRandom.defaultSeed(slot: slot)
    }

    /// MOD-008: the output (0…1) at `cycle` for the oscillator at `slot`: square uses the duty cycle, sample-and-hold
    /// the seeded level of the step (with its glide); sine and triangle are `value(atPhase:)`.
    public func value(at cycle: LFOCycle, slot: Int = 0) -> Double {
        let raw: Double
        switch shape {
        case .sine, .triangle:
            return value(atPhase: cycle.phase)
        case .square:
            raw = center + amplitude / 2 * (cycle.phase < dutyCycle ? 1 : -1)
        case .sampleHold:
            raw = center + amplitude * (heldLevel(at: cycle, seed: effectiveSeed(slot: slot)) - 0.5)
        }
        guard raw.isFinite else { return min(max(center, 0), 1) }
        return min(max(raw, 0), 1)
    }

    /// The step's level, ramped from the previous step's level during the glide (research MOD-008-D6).
    private func heldLevel(at cycle: LFOCycle, seed: UInt64) -> Double {
        let current: Double = SteppedRandom.level(seed: seed, step: cycle.step)
        guard glide > 0, cycle.phase < glide else { return current }
        let previous: Double = SteppedRandom.level(seed: seed, step: cycle.step &- 1)
        return previous + (current - previous) * (cycle.phase / glide)
    }

    /// The output (0…1) at phase `phi` (0…<1).
    public func value(atPhase phi: Double) -> Double {
        let raw: Double = center + amplitude / 2 * shape.wave(phi)
        guard raw.isFinite else { return min(max(center, 0), 1) }
        return min(max(raw, 0), 1)
    }

    /// MOD-009: the output after `elapsedNanoseconds` at a constant tempo (nil: none), at the effective rate.
    public func value(elapsedNanoseconds: UInt64, tempoBPM: Double?, maximumRateHz: Double = .infinity) -> Double {
        let rate: Double = effectiveRateHz(tempoBPM: tempoBPM, maximumRateHz: maximumRateHz)
        return value(at: cycle(elapsedNanoseconds: elapsedNanoseconds, rateHz: rate))
    }

    /// The output (0…1) after `elapsedNanoseconds`, running at min(rateHz, maximumRateHz); `slot` picks the default
    /// seed of an unseeded sample-and-hold oscillator (MOD-008).
    public func value(elapsedNanoseconds: UInt64, maximumRateHz: Double = .infinity, slot: Int = 0) -> Double {
        let rate: Double = min(rateHz, maximumRateHz)
        return value(at: cycle(elapsedNanoseconds: elapsedNanoseconds, rateHz: rate), slot: slot)
    }
}

/// A scene's oscillators with one shared origin (contract L3).
public final class LFOBank {
    /// At most this many oscillators per bank (and per scene).
    public static let maximumOscillators = 8
    /// The effective-rate cap while Reduce flashing is on: 3 cycles per second (FR-072, WCAG 2.3.1).
    public static let reduceFlashingMaximumRateHz = 3.0

    /// The oscillators by position; nil keeps the position of an unusable scene entry (it reads 0).
    public private(set) var oscillators: [LFO?] = []
    private var origin: UInt64?
    /// MOD-009: per slot, where a synced oscillator's current rate began (nil until its first sample; unused for free ones).
    private var segments: [LFOPhaseSegment?] = []

    public init() {}

    public var hasOscillators: Bool { oscillators.contains { (o: LFO?) -> Bool in o != nil } }

    /// MOD-009: whether any oscillator follows the tempo (the app reads the tempo only then).
    public private(set) var hasSyncedOscillators = false

    /// Validates and replaces every oscillator; the origin restarts at the next sample. Unchanged on error.
    public func set(_ oscillators: [LFO?]) throws(LFOError) {
        guard oscillators.count <= Self.maximumOscillators else { throw .tooManyOscillators(limit: Self.maximumOscillators) }
        for case let lfo? in oscillators {
            if let problem = lfo.validationProblem { throw .invalidSettings(reason: problem) }
        }
        self.oscillators = oscillators
        origin = nil
        segments = Array(repeating: nil, count: oscillators.count)   // MOD-009: allocated here, never per frame
        hasSyncedOscillators = oscillators.contains { (o: LFO?) -> Bool in o?.sync != nil }
    }

    /// Writes each slot's value at `timeNanoseconds` into `output` (0 for an empty or missing slot). The first call
    /// after `set` defines the origin; a time at or before the origin reads elapsed 0. Free oscillators are a pure
    /// function of the elapsed time (MOD-007); synced ones follow `tempoBPM` (nil: their stored rate) with a continuous
    /// phase (MOD-009 contract T3). Allocation-free.
    public func values(atNanoseconds timeNanoseconds: UInt64, tempoBPM: Double? = nil, maximumRateHz: Double = .infinity,
                       into output: UnsafeMutableBufferPointer<Double>) {
        let start: UInt64 = origin ?? timeNanoseconds
        origin = start
        let elapsed: UInt64 = timeNanoseconds > start ? timeNanoseconds - start : 0
        for i in output.indices {
            if i < oscillators.count, let lfo = oscillators[i] {
                if lfo.sync == nil {
                    output[i] = lfo.value(elapsedNanoseconds: elapsed, maximumRateHz: maximumRateHz, slot: i)
                } else {
                    let rate: Double = lfo.effectiveRateHz(tempoBPM: tempoBPM, maximumRateHz: maximumRateHz)
                    output[i] = lfo.value(at: syncedCycle(slot: i, lfo: lfo, rate: rate, origin: start, time: timeNanoseconds), slot: i)
                }
            } else {
                output[i] = 0
            }
        }
    }

    /// The step and phase of synced slot `slot` at `time` (research MOD-009-D2, MOD-008-D4): exact from the segment's
    /// start while the rate is unchanged; a changed rate starts a new segment at this time with the step and phase
    /// reached under the old one, so the step count continues.
    private func syncedCycle(slot: Int, lfo: LFO, rate: Double, origin: UInt64, time: UInt64) -> LFOCycle {
        var segment: LFOPhaseSegment = segments[slot]
            ?? LFOPhaseSegment(start: origin, phase: lfo.phaseOffset, rateHz: rate, startCycle: 0)
        if segment.rateHz != rate {
            let at: UInt64 = max(time, segment.start)
            let reached: LFOCycle = segment.cycle(at: at)
            segment = LFOPhaseSegment(start: at, phase: reached.phase, rateHz: rate, startCycle: reached.step)
        }
        segments[slot] = segment
        return segment.cycle(at: time)
    }
}

/// MOD-009: where a synced oscillator's current rate began (data-model "Phase segment").
struct LFOPhaseSegment: Sendable, Hashable {
    var start: UInt64
    /// Cycles at `start` (0…1).
    var phase: Double
    var rateHz: Double
    /// MOD-008: whole cycles completed before `start` (the step count continues across segments).
    var startCycle: Int64

    /// The step and phase at `time`; a time before `start` reads the start.
    func cycle(at time: UInt64) -> LFOCycle {
        let elapsed: UInt64 = time > start ? time - start : 0
        return LFO.cycle(from: phase, startCycle: startCycle, elapsedNanoseconds: elapsed, rateHz: rateHz)
    }
}

/// MOD-008: whole cycles since the origin (including the phase offset) and the phase within the current one.
public struct LFOCycle: Sendable, Hashable {
    /// The step number: whole cycles completed.
    public let step: Int64
    /// The phase in the current cycle (0…<1).
    public let phase: Double

    public init(step: Int64, phase: Double) {
        self.step = step
        self.phase = phase
    }
}
