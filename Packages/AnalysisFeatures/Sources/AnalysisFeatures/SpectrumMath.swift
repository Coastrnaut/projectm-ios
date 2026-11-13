// SpectrumMath.swift — conversions on linear magnitudes (ANL-001-R4).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum SpectrumMath {
    /// Floor for 0 and anything below it; the same floor as AudioCore's level meter.
    public static let floorDecibels: Float = -120

    /// 20·log10(magnitude) relative to full scale (a full-scale sine reads 0 dB), clamped to
    /// `floorDecibels`. Non-finite or non-positive input reads the floor; +∞ reads the largest
    /// finite value.
    @inlinable
    public static func decibels(_ magnitude: Float) -> Float {
        guard magnitude > 0, !magnitude.isNaN else { return floorDecibels }
        guard magnitude.isFinite else { return .greatestFiniteMagnitude }
        let db = 20 * log10f(magnitude)
        return db.isFinite ? max(floorDecibels, db) : floorDecibels
    }
}
