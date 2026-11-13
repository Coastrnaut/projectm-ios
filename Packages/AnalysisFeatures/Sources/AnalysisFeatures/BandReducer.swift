// BandReducer.swift — magnitude spectrum → 16/32/64/128 log-frequency bands (ANL-002-R1, R4, R5, R7,
// R9, R11, R12; research ANL-002-D3, D5; contracts/band-reducer.md).
//
// Per frame: one pass squares the sanitized magnitudes into a power scratch (non-finite or ≤ 0 → 0,
// clamped to 1e15 so squares and sums stay finite), then each band is one weighted dot product over
// its contiguous bins (vDSP_dotpr, or an ordered Float loop on the portable path), times the band's
// scale, square-rooted: the amplitude of the sine carrying the band's power.
//
// Real-time safety (Constitution VII): the 20 tables of the reducer's sample rate (4 counts × 5 sizes)
// are flattened into preallocated memory in `init`; `reduce(magnitudes:size:bandCount:into:)` only
// reads and writes preallocated memory, so switching size or count allocates nothing. Not Sendable:
// confined to the worker that owns it (ANL-001-R14).
//
// Boundary (Constitution VIII, ADR-0008 decision 5): nothing computed here is passed to projectM.
#if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
import Accelerate
#endif

public final class BandReducer {
    /// Largest magnitude used; larger values are clamped (far above any ANL-001 output).
    public static let magnitudeLimit: Float = 1e15

    public let sampleRate: Double
    public let resolvedBackend: SpectrumBackend
    private let layouts: [BandLayout]
    /// Index of a table's first band in the flattened per-band arrays, per (count, size).
    private let tableStart: UnsafeMutablePointer<Int>
    private let firstBin: UnsafeMutablePointer<Int>
    private let binCount: UnsafeMutablePointer<Int>
    private let offset: UnsafeMutablePointer<Int>
    private let scale: UnsafeMutablePointer<Float>
    private let weights: UnsafeMutablePointer<Float>
    private let power: UnsafeMutablePointer<Float>
    private let tableCount = BandCount.allCases.count * FFTSize.allCases.count
    private let bandTotal: Int
    private let weightTotal: Int

    public init(sampleRate: Double = 44_100, backend: SpectrumBackend = .automatic) throws(BandLayoutError) {
        var layouts: [BandLayout] = []
        for count in BandCount.allCases {
            for size in FFTSize.allCases {
                layouts.append(try BandLayout(bandCount: count, size: size, sampleRate: sampleRate))
            }
        }
        self.sampleRate = sampleRate
        resolvedBackend = backend != .portable && SpectrumBackend.isAcceleratedAvailable ? .accelerated : .portable
        self.layouts = layouts
        bandTotal = layouts.reduce(0) { $0 + $1.bandCount.rawValue }
        weightTotal = layouts.reduce(0) { $0 + $1.weightTable.count }
        tableStart = .allocate(capacity: tableCount)
        firstBin = .allocate(capacity: bandTotal)
        binCount = .allocate(capacity: bandTotal)
        offset = .allocate(capacity: bandTotal)
        scale = .allocate(capacity: bandTotal)
        weights = .allocate(capacity: weightTotal)
        power = .allocate(capacity: FFTSize.maximum.binCount)
        power.initialize(repeating: 0, count: FFTSize.maximum.binCount)
        var band = 0, weight = 0
        for (t, layout) in layouts.enumerated() {
            (tableStart + t).initialize(to: band)
            for b in 0..<layout.bandCount.rawValue {
                (firstBin + band).initialize(to: layout.firstBin[b])
                (binCount + band).initialize(to: layout.binCounts[b])
                (offset + band).initialize(to: weight + layout.offsets[b])
                (scale + band).initialize(to: layout.scales[b])
                band += 1
            }
            for (i, w) in layout.weightTable.enumerated() { (weights + weight + i).initialize(to: w) }
            weight += layout.weightTable.count
        }
    }

    deinit {
        tableStart.deinitialize(count: tableCount); tableStart.deallocate()
        firstBin.deinitialize(count: bandTotal); firstBin.deallocate()
        binCount.deinitialize(count: bandTotal); binCount.deallocate()
        offset.deinitialize(count: bandTotal); offset.deallocate()
        scale.deinitialize(count: bandTotal); scale.deallocate()
        weights.deinitialize(count: weightTotal); weights.deallocate()
        power.deinitialize(count: FFTSize.maximum.binCount); power.deallocate()
    }

    @inline(__always)
    private static func tableIndex(_ count: BandCount, _ size: FFTSize) -> Int {
        let c: Int
        switch count { case .b16: c = 0; case .b32: c = 1; case .b64: c = 2; case .b128: c = 3 }
        return c * FFTSize.allCases.count + (size.log2 - FFTSize.n512.log2)
    }

    /// The table used for `bandCount` at `size` (this reducer's sample rate).
    public func layout(bandCount: BandCount, size: FFTSize) -> BandLayout {
        layouts[BandReducer.tableIndex(bandCount, size)]
    }

    /// Bands of `magnitudes[0..<size.binCount]` (ANL-001 linear magnitudes) into
    /// `output[0..<bandCount.rawValue]`. Every value finite and ≥ 0; all-zero input gives +0.0.
    /// Allocation-, lock-, log- and I/O-free.
    public func reduce(magnitudes: UnsafePointer<Float>, size: FFTSize, bandCount: BandCount,
                       into output: UnsafeMutablePointer<Float>) {
        let bins = size.binCount
        let limit = BandReducer.magnitudeLimit
        power[0] = 0
        for k in 1..<bins {
            var m = magnitudes[k]
            if !(m > 0) || !m.isFinite { m = 0 } else if m > limit { m = limit }
            power[k] = m * m
        }
        let start = tableStart[BandReducer.tableIndex(bandCount, size)]
        for b in 0..<bandCount.rawValue {
            let i = start + b
            let w = UnsafePointer(weights + offset[i])
            let p = UnsafePointer(power + firstBin[i])
            let n = binCount[i]
            var sum: Float = 0
            #if canImport(Accelerate) && !ANALYSIS_NO_ACCELERATE
            if resolvedBackend == .accelerated {
                vDSP_dotpr(w, 1, p, 1, &sum, vDSP_Length(n))
            } else {
                for j in 0..<n { sum += w[j] * p[j] }
            }
            #else
            for j in 0..<n { sum += w[j] * p[j] }
            #endif
            let value = (sum * scale[i]).squareRoot()
            output[b] = value.isFinite ? value : 0
        }
    }

    /// Convenience for tests and callers off the real-time path (allocates the result).
    /// `magnitudes.count` must equal `size.binCount`.
    public func reduce(_ magnitudes: [Float], size: FFTSize, bandCount: BandCount) -> [Float] {
        precondition(magnitudes.count == size.binCount, "need \(size.binCount) magnitudes, got \(magnitudes.count)")
        var result = [Float](repeating: 0, count: bandCount.rawValue)
        magnitudes.withUnsafeBufferPointer { m in
            result.withUnsafeMutableBufferPointer { o in
                reduce(magnitudes: m.baseAddress!, size: size, bandCount: bandCount, into: o.baseAddress!)
            }
        }
        return result
    }
}
