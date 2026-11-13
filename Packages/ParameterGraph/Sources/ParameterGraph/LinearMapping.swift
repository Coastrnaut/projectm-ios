// LinearMapping.swift — scales a source value into a bounded destination range (MOD-003-R1 to R8;
// research MOD-003-D1 to D4; contract specs/034-mod-003-linear-mapping/contracts/linear-mapping.md).
//
// * Input: the source's place in the input range, always clamped to 0…1 (a non-finite place → 0).
// * Output: the precise two-branch interpolation of C++20 `std::lerp` (WG21 P0811): exactly the
//   start at 0 and exactly the end at 1 for every finite pair of ends, never outside the ends, and
//   monotonic in the position, including constant (start = end) and inverted (end < start) ranges.
//   When the ends have opposite signs or include zero the result is bit-identical to MOD-002's
//   `(1 − s)·start + s·end`; otherwise it differs by at most 2 units in the last place.
// * Pure and allocation-free: four stored scalars, arithmetic only. Curves (MOD-004) shape the
//   position, then interpolate.

public struct LinearMapping: Sendable, Hashable {
    /// The source values mapped to position 0 and 1 (valid when finite, minimum below maximum).
    public var inputMinimum: Double
    public var inputMaximum: Double
    /// The values at position 0 and 1 (valid when finite); an end below the start inverts.
    public var outputStart: Double
    public var outputEnd: Double

    public init(inputMinimum: Double = 0, inputMaximum: Double = 1, outputStart: Double, outputEnd: Double) {
        self.inputMinimum = inputMinimum
        self.inputMaximum = inputMaximum
        self.outputStart = outputStart
        self.outputEnd = outputEnd
    }

    /// 0…1 → 0…1.
    public static let identity = LinearMapping(outputStart: 0, outputEnd: 1)

    /// All four bounds finite and the input minimum below the maximum. An invalid mapping still never
    /// traps; callers such as bindings refuse it before use (MOD-003-R8).
    public var isValid: Bool {
        inputMinimum.isFinite && inputMaximum.isFinite && outputStart.isFinite && outputEnd.isFinite
            && inputMinimum < inputMaximum
    }

    /// The output falls as the input rises.
    public var isInverted: Bool { outputEnd < outputStart }

    /// Every input maps to the same value.
    public var isConstant: Bool { outputEnd == outputStart }

    /// The input's place in the input range, clamped to 0…1 (contract L1).
    public func position(of input: Double) -> Double {
        Self.clampedPosition((input - inputMinimum) / (inputMaximum - inputMinimum))
    }

    /// The output at `position` (clamped first, non-finite → 0): exact ends, bounded, monotonic (contract L2, L3).
    public func interpolate(_ position: Double) -> Double {
        Self.interpolate(from: outputStart, to: outputEnd, at: position)
    }

    /// `interpolate(position(of: input))` (contract L4).
    public func map(_ input: Double) -> Double { interpolate(position(of: input)) }

    /// `position` limited to 0…1; a non-finite position (NaN or ±∞) reads 0, as in MOD-002.
    public static func clampedPosition(_ position: Double) -> Double {
        min(max(position.isFinite ? position : 0, 0), 1)
    }

    /// The value between `start` and `end` at `position` (clamped to 0…1 first; non-finite → 0).
    public static func interpolate(from start: Double, to end: Double, at position: Double) -> Double {
        let t = clampedPosition(position)
        if (start <= 0 && end >= 0) || (start >= 0 && end <= 0) {
            // Opposite signs (or a zero end): exact at both ends, no subtraction of the ends.
            return t * end + (1 - t) * start
        }
        if t == 1 { return end }
        let x = start + t * (end - start)
        // Rounding may step past the end; never let it (keeps the result bounded and monotonic).
        return end > start ? min(end, x) : max(end, x)
    }
}
