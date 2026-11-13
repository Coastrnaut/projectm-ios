// PortableRealFFT.swift — the portable real FFT (research ANL-001-D3). Used on every platform
// without Accelerate (Linux CI) and selectable on Apple platforms for comparison.
//
// An N-point real input is packed into N/2 complex points z[n] = x[2n] + i·x[2n+1] (the same
// packing as vDSP's real FFT), transformed with an iterative radix-2 decimation-in-time FFT, and
// split into the one-sided real spectrum:
//   X[k] = E[k] + e^(−2πik/N)·O[k],  E = (Z[k] + conj Z[M−k])/2,  O = −i(Z[k] − conj Z[M−k])/2.
// Twiddles come from one table of cos/sin(2πj/8192), j = 0…4096, computed in Double and rounded to
// Float once; a size N uses every (8192/N)-th entry. After init nothing allocates.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

final class PortableRealFFT {
    private static let tableSize = FFTSize.maximum.rawValue           // 8,192
    private let cosTable: UnsafeMutablePointer<Float>                // 4,097 entries
    private let sinTable: UnsafeMutablePointer<Float>
    private let re: UnsafeMutablePointer<Float>                      // 4,096 entries (N/2 max)
    private let im: UnsafeMutablePointer<Float>
    private let tableCount = FFTSize.maximum.rawValue / 2 + 1
    private let half = FFTSize.maximum.rawValue / 2

    init() {
        cosTable = .allocate(capacity: tableCount)
        sinTable = .allocate(capacity: tableCount)
        for j in 0..<tableCount {
            let angle = 2 * Double.pi * Double(j) / Double(PortableRealFFT.tableSize)
            // Exact values at the quarter points keep the transform of simple inputs clean.
            let (c, s): (Double, Double)
            switch j {
            case 0: (c, s) = (1, 0)
            case PortableRealFFT.tableSize / 4: (c, s) = (0, 1)
            case PortableRealFFT.tableSize / 2: (c, s) = (-1, 0)
            default: (c, s) = (cos(angle), sin(angle))
            }
            (cosTable + j).initialize(to: Float(c))
            (sinTable + j).initialize(to: Float(s))
        }
        re = .allocate(capacity: half)
        re.initialize(repeating: 0, count: half)
        im = .allocate(capacity: half)
        im.initialize(repeating: 0, count: half)
    }

    deinit {
        cosTable.deinitialize(count: tableCount); cosTable.deallocate()
        sinTable.deinitialize(count: tableCount); sinTable.deallocate()
        re.deinitialize(count: half); re.deallocate()
        im.deinitialize(count: half); im.deallocate()
    }

    /// Raw one-sided DFT magnitudes |X[k]|, k = 0…N/2, of the N real samples at `input`.
    func rawMagnitudes(_ input: UnsafePointer<Float>, size: FFTSize, into output: UnsafeMutablePointer<Float>) {
        let n = size.rawValue
        let m = n / 2
        let bits = size.log2 - 1
        // Pack with bit-reversed order (the first stage of the in-place DIT FFT).
        for j in 0..<m {
            let r = Int(UInt32(truncatingIfNeeded: j).bitReversed >> UInt32(32 - bits))
            re[r] = input[2 * j]
            im[r] = input[2 * j + 1]
        }
        // Butterflies.
        var length = 2
        while length <= m {
            let halfLength = length / 2
            let step = PortableRealFFT.tableSize / length
            var start = 0
            while start < m {
                for j in 0..<halfLength {
                    let wr = cosTable[j * step]
                    let wi = -sinTable[j * step]
                    let a = start + j
                    let b = a + halfLength
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }
                start += length
            }
            length <<= 1
        }
        // Split into the real spectrum.
        output[0] = abs(re[0] + im[0])
        output[m] = abs(re[0] - im[0])
        let step = PortableRealFFT.tableSize / n
        for k in 1..<m {
            let zr = re[k], zi = im[k]
            let cr = re[m - k], ci = -im[m - k]               // conj Z[M−k]
            let er = 0.5 * (zr + cr), ei = 0.5 * (zi + ci)
            // O = −i·(Z − C)/2 = ((Zi − Ci)/2, −(Zr − Cr)/2)
            let or = 0.5 * (zi - ci), oi = -0.5 * (zr - cr)
            let wr = cosTable[k * step], wi = -sinTable[k * step]   // e^(−2πik/N)
            let xr = er + (or * wr - oi * wi)
            let xi = ei + (or * wi + oi * wr)
            output[k] = (xr * xr + xi * xi).squareRoot()
        }
    }
}

private extension UInt32 {
    var bitReversed: UInt32 {
        var v = self
        v = ((v >> 1) & 0x5555_5555) | ((v & 0x5555_5555) << 1)
        v = ((v >> 2) & 0x3333_3333) | ((v & 0x3333_3333) << 2)
        v = ((v >> 4) & 0x0F0F_0F0F) | ((v & 0x0F0F_0F0F) << 4)
        v = ((v >> 8) & 0x00FF_00FF) | ((v & 0x00FF_00FF) << 8)
        return (v >> 16) | (v << 16)
    }
}
