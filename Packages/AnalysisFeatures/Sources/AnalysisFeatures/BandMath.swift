// BandMath.swift — band values normalized to 0…1 for mappings (ANL-002-R8; research ANL-002-D6).
// Pure functions; `normalize(_:count:scale:)` works in place and allocates nothing. Zero maps to zero
// on both scales, so silence stays silent after normalization.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// How band values map to 0…1.
public enum BandScale: Sendable, Hashable {
    /// value / reference, clamped (reference 1.0 = a full-scale sine).
    case linear(reference: Float)
    /// (dBFS − floor) / −floor, clamped; floor < 0 (default −80 dB).
    case decibels(floorDecibels: Float)
}

public enum BandMath {
    public static let defaultFloorDecibels: Float = -80

    /// clamp(value / reference, 0, 1). NaN, ≤ 0 or an invalid reference (≤ 0, not finite) give 0;
    /// +∞ gives 1.
    @inlinable
    public static func normalizedLinear(_ value: Float, reference: Float = 1) -> Float {
        guard reference > 0, reference.isFinite, value > 0 else { return 0 }
        return min(1, value / reference)
    }

    /// clamp((20·log10 value − floor) / −floor, 0, 1). NaN, ≤ 0 or an invalid floor (≥ 0, not finite)
    /// give 0; +∞ gives 1.
    @inlinable
    public static func normalizedDecibels(_ value: Float, floorDecibels: Float = defaultFloorDecibels) -> Float {
        guard floorDecibels < 0, floorDecibels.isFinite, value > 0 else { return 0 }
        guard value.isFinite else { return 1 }
        let mapped = (20 * log10f(value) - floorDecibels) / -floorDecibels
        guard mapped.isFinite else { return 0 }
        return min(1, max(0, mapped))
    }

    /// Normalizes `values[0..<count]` in place.
    public static func normalize(_ values: UnsafeMutablePointer<Float>, count: Int, scale: BandScale) {
        switch scale {
        case .linear(let reference):
            for i in 0..<count { values[i] = normalizedLinear(values[i], reference: reference) }
        case .decibels(let floor):
            for i in 0..<count { values[i] = normalizedDecibels(values[i], floorDecibels: floor) }
        }
    }
}
