// MonotonicClock.swift — allocation-free monotonic time for real-time callbacks.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum MonotonicClock {
    /// Nanoseconds on a monotonic clock (uptime). Intervals within a session only.
    @inline(__always)
    public static func nowNanoseconds() -> UInt64 {
        #if canImport(Darwin)
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        #elseif canImport(Glibc) || canImport(Musl)
        var ts = timespec()
        clock_gettime(CLOCK_MONOTONIC, &ts)
        return UInt64(ts.tv_sec) &* 1_000_000_000 &+ UInt64(ts.tv_nsec)
        #else
        // Fallback: offset from a reference captured before the first reading, so the
        // difference can never be negative.
        let reference = MonotonicClock.reference
        let (s, atto) = (ContinuousClock.now - reference).components
        return UInt64(max(0, s)) &* 1_000_000_000 &+ UInt64(max(0, atto) / 1_000_000_000)
        #endif
    }

    public static func nowSeconds() -> Double {
        Double(nowNanoseconds()) / 1_000_000_000
    }

    #if !canImport(Darwin) && !canImport(Glibc) && !canImport(Musl)
    private static let reference = ContinuousClock.now
    #endif
}
