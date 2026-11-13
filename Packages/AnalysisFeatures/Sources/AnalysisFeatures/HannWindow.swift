// HannWindow.swift — periodic Hann windows, w[n] = 0.5 − 0.5·cos(2πn/N) (ANL-001-R3; research
// ANL-001-D4). Computed in Double and rounded to Float once; the same window as the AUD-016
// reference DFT, so the catalog's bins and its A·N/4 peak apply unchanged.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum HannWindow {
    /// The window for `size` as an array (tests and setup only; allocates).
    static func table(for size: FFTSize) -> [Float] {
        let n = size.rawValue
        return (0..<n).map { value(n: $0, size: n) }
    }

    @inline(__always)
    static func value(n: Int, size: Int) -> Float {
        // Exact at n = 0 (0) and n = N/2 (1); symmetric because cos(2π(N−n)/N) is evaluated as
        // cos of the reflected index.
        let reflected = n <= size / 2 ? n : size - n
        return Float(0.5 - 0.5 * cos(2 * Double.pi * Double(reflected) / Double(size)))
    }
}

/// Every size's window in one preallocated block, owned by an analyzer.
final class HannWindowTables {
    private let storage: UnsafeMutablePointer<Float>
    private let count: Int

    init() {
        count = FFTSize.allCases.reduce(0) { $0 + $1.rawValue }
        storage = .allocate(capacity: count)
        var offset = 0
        for size in FFTSize.allCases {
            for n in 0..<size.rawValue { (storage + offset + n).initialize(to: HannWindow.value(n: n, size: size.rawValue)) }
            offset += size.rawValue
        }
    }

    deinit {
        storage.deinitialize(count: count)
        storage.deallocate()
    }

    /// Start of the window for `size` (N values). Sizes are stored in ascending order, so the
    /// offset of N is 512 + 1,024 + … + N/2 = N − 512.
    @inline(__always)
    func window(for size: FFTSize) -> UnsafePointer<Float> {
        UnsafePointer(storage + (size.rawValue - FFTSize.n512.rawValue))
    }
}
