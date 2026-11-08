// MonotonicClock.swift — allocation-free monotonic time for real-time callbacks.
#if canImport(Darwin)
import Darwin
#endif

public enum MonotonicClock {
    /// Nanoseconds on a monotonic clock that keeps counting while the device sleeps is not
    /// required here; uptime is sufficient for intervals within a session.
    @inline(__always)
    public static func nowNanoseconds() -> UInt64 {
        #if canImport(Darwin)
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        #else
        let d = ContinuousClock.now - ContinuousClock.zeroReference
        let (s, atto) = d.components
        return UInt64(s) &* 1_000_000_000 &+ UInt64(atto / 1_000_000_000)
        #endif
    }

    public static func nowSeconds() -> Double {
        Double(nowNanoseconds()) / 1_000_000_000
    }
}

#if !canImport(Darwin)
private extension ContinuousClock {
    static let zeroReference = ContinuousClock.now
}
#endif
