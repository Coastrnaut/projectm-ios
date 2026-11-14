// SteppedRandom.swift — MOD-008: the seeded, counter-based levels of sample-and-hold oscillators (MOD-008-R3, R5;
// specs/212-mod-008-stepped-lfo, research MOD-008-D1, D2, contract S3, S5).
//
// A step's level is a pure function of (seed, step number): SplitMix64's finalizer of the pre-mixed seed plus the
// step, mapped to 0…<1 with 53 bits. No generator state is carried between frames, so frame rate, dropped frames
// and jitter can never change a level, and any step is computed directly. Integer-only and Foundation-free: the
// same levels on every platform (Linux included).

/// Seeded step levels for sample-and-hold oscillators.
public enum SteppedRandom {
    /// The level of step `step` for `seed`, in 0…<1 (research MOD-008-D1).
    public static func level(seed: UInt64, step: Int64) -> Double {
        let hashed: UInt64 = mix(mix(seed) &+ UInt64(bitPattern: step))
        return Double(hashed >> 11) * 0x1p-53
    }

    /// The seed of an oscillator without a stored one: 2³² + its position, outside the stored 32-bit range so it
    /// never equals a stored seed (research MOD-008-D2).
    public static func defaultSeed(slot: Int) -> UInt64 {
        (UInt64(1) << 32) &+ UInt64(truncatingIfNeeded: max(slot, 0))
    }

    /// SplitMix64's output function (Steele, Lea and Flood 2014): a bijective 64-bit mix.
    static func mix(_ value: UInt64) -> UInt64 {
        var z: UInt64 = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
