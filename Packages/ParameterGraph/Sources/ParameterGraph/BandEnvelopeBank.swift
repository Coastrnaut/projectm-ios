// BandEnvelopeBank.swift — fast, medium and slow envelopes of every band (MOD-015-R1 to R4, R7 to R9;
// specs/199-mod-015-envelope-follower-bank, research MOD-015-D1 to D3, contract band-envelopes B1 to B6, B8).
//
// * Each envelope is MOD-005's one-pole `AudioFeatureEnvelope` (reused, not redefined): attack τ while the band is
//   above the envelope, release τ otherwise. The bank computes the two coefficients `1 − e^(−Δt/τ)` once per
//   profile per frame and applies exactly `AudioFeatureEnvelope.step`'s update and clamps, so each envelope equals
//   `step` bit for bit (6 `exp` per frame instead of one per envelope).
// * Deterministic: the only clock is the frame time in integer nanoseconds passed to `advance`, with
//   `AudioFeatureModulator`'s Δt rules (first advance and non-increasing time 0, at most 0.25 s).
// * Independent: an envelope reads only its own band and its own profile's constants.
// * Storage for 128 bands × 3 profiles is allocated in `init`; `advance` and `values` allocate nothing. One owner
//   (not `Sendable`), never from an audio callback (Constitution VII).
// Foundation-free (the C math library only): builds on Linux.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A band envelope's speed (MOD-015-R2): fixed one-pole attack and release time constants (τ, MOD-005).
public enum BandEnvelopeProfile: String, Sendable, Hashable, CaseIterable {
    /// Attack 10 ms, release 80 ms: follows hits.
    case fast
    /// Attack 80 ms, release 350 ms: follows phrases.
    case medium
    /// Attack 400 ms, release 1.6 s: follows sections.
    case slow

    /// The position in the bank's band-major layout (`band · 3 + index`).
    public var index: Int {
        switch self {
        case .fast: 0
        case .medium: 1
        case .slow: 2
        }
    }

    /// The profile's attack and release time constants.
    public var envelope: AudioFeatureEnvelope {
        switch self {
        case .fast: AudioFeatureEnvelope(attackSeconds: 0.010, releaseSeconds: 0.080)
        case .medium: AudioFeatureEnvelope(attackSeconds: 0.080, releaseSeconds: 0.350)
        case .slow: AudioFeatureEnvelope(attackSeconds: 0.400, releaseSeconds: 1.600)
        }
    }
}

public final class BandEnvelopeBank {
    /// The most bands followed; further bands are ignored (contract B5).
    public static let maximumBands = AudioFeatureSource.maximumBandIndex + 1
    /// Envelopes per band.
    public static let profileCount = 3
    /// The longest elapsed time one `advance` applies, as for bindings.
    public static let maximumStepSeconds = AudioFeatureModulator.maximumStepSeconds

    /// The time constants by profile index (fast, medium, slow).
    public let profiles: [AudioFeatureEnvelope]
    private let state: UnsafeMutableBufferPointer<Double>
    private let coefficients: UnsafeMutableBufferPointer<Double>   // [attack, release] per profile
    /// The band count of the last advance (0 before the first).
    public private(set) var bandCount = 0
    private var lastTime: UInt64?

    /// The documented profiles (MOD-015-R2).
    public convenience init() {
        self.init(checked: BandEnvelopeProfile.allCases.map { (p: BandEnvelopeProfile) -> AudioFeatureEnvelope in p.envelope })
    }

    /// Custom time constants by profile index (tests of independence); nil unless exactly three valid envelopes.
    public convenience init?(profiles: [AudioFeatureEnvelope]) {
        guard profiles.count == Self.profileCount, profiles.allSatisfy(\.isValid) else { return nil }
        self.init(checked: profiles)
    }

    private init(checked profiles: [AudioFeatureEnvelope]) {
        self.profiles = profiles
        state = .allocate(capacity: Self.maximumBands * Self.profileCount)
        state.initialize(repeating: 0)
        coefficients = .allocate(capacity: Self.profileCount * 2)
        coefficients.initialize(repeating: 0)
    }

    deinit {
        state.deallocate()
        coefficients.deallocate()
    }

    /// Every envelope back to 0 and the clock forgotten (the next advance has Δt 0).
    public func reset() {
        for i in state.indices { state[i] = 0 }
        bandCount = 0
        lastTime = nil
    }

    /// Advances every band's three envelopes toward `bands` at `timeNanoseconds` (contract B2, B3, B5).
    public func advance(bands: UnsafeBufferPointer<Float>, timeNanoseconds: UInt64) {
        let count = min(bands.count, Self.maximumBands)
        if count != bandCount {
            for i in state.indices { state[i] = 0 }
            bandCount = count
        }
        var elapsed = 0.0
        if let last = lastTime {
            if timeNanoseconds > last {
                elapsed = min(Double(timeNanoseconds - last) / 1e9, Self.maximumStepSeconds)
                lastTime = timeNanoseconds
            }
        } else {
            lastTime = timeNanoseconds
        }
        for p in 0..<Self.profileCount {
            coefficients[2 * p] = Self.coefficient(tau: profiles[p].attackSeconds, elapsed: elapsed)
            coefficients[2 * p + 1] = Self.coefficient(tau: profiles[p].releaseSeconds, elapsed: elapsed)
        }
        for b in 0..<count {
            let raw = Double(bands[b])
            let goal: Double = raw.isFinite ? min(max(raw, 0), 1) : 0
            for p in 0..<Self.profileCount {
                let i = b * Self.profileCount + p
                let current = state[i]
                let a: Double = goal > current ? coefficients[2 * p] : coefficients[2 * p + 1]
                state[i] = min(max(current + (goal - current) * a, 0), 1)
            }
        }
    }

    /// The step fraction over `elapsed` for time constant `tau`, as `AudioFeatureEnvelope.step` computes it:
    /// τ = 0 is instant (1) even with no elapsed time; no elapsed time is 0.
    private static func coefficient(tau: Double, elapsed: Double) -> Double {
        guard tau > 0 else { return 1 }
        guard elapsed > 0 else { return 0 }
        return 1 - exp(-elapsed / tau)
    }

    /// The envelopes of the last advance, band-major (`band · 3 + profile.index`), `bandCount · 3` values; borrowed:
    /// valid until the next `advance` or `reset`. Pass it as `AudioFeatureFrame.bandEnvelopes`.
    public var values: UnsafeBufferPointer<Double> {
        UnsafeBufferPointer(start: state.baseAddress, count: bandCount * Self.profileCount)
    }

    /// One envelope's value; 0 for a band beyond `bandCount`.
    public func value(band: Int, profile: BandEnvelopeProfile) -> Double {
        guard band >= 0, band < bandCount else { return 0 }
        return state[band * Self.profileCount + profile.index]
    }
}
