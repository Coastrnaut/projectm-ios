// BandLayout.swift — the precomputed log-frequency band table for one (band count, FFT size, sample
// rate) (ANL-002-R1 to R3, R5, R6, R10; research ANL-002-D1, D2, D4, D8; data-model.md).
//
// Edges: `20 · (upper/20)^(i/B)` Hz, upper = min(20 kHz, R/2). Bin k ≥ 1 covers one bin width centred
// on k·R/N (bin 1 from 0 Hz, the Nyquist bin up to R/2); DC covers nothing. A bin's weight in a band is
// the fraction of its interval inside the band, so no energy is counted twice. A band's scale is
// `1 / (1.5 · min(1, W))`, W = the band's total weight in bins and 1.5 the periodic Hann window's
// equivalent noise bandwidth (research ANL-002-D3, D4). Built once in Double, stored as Float.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The band counts offered (ANL-002-R1).
public enum BandCount: Int, CaseIterable, Sendable, Hashable {
    case b16 = 16
    case b32 = 32
    case b64 = 64
    case b128 = 128
}

public enum BandLayoutError: Error, Equatable, Sendable {
    /// The sample rate must be finite and at least `BandLayout.minimumSampleRate`.
    case invalidSampleRate(Double)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidSampleRate(a), .invalidSampleRate(b)): return a == b || (a.isNaN && b.isNaN)
        }
    }
}

public struct BandLayout: Sendable, Equatable {
    public static let lowerEdgeHz: Double = 20
    public static let upperEdgeLimitHz: Double = 20_000
    public static let minimumSampleRate: Double = 8_000
    /// Equivalent noise bandwidth of the periodic Hann window, in bins.
    public static let hannEquivalentNoiseBandwidth: Double = 1.5
    /// Overlaps below this many bins are rounding residue at an edge and are dropped.
    static let weightEpsilon: Double = 1e-9

    public let bandCount: BandCount
    public let size: FFTSize
    public let sampleRate: Double
    public var lowerEdge: Double { BandLayout.lowerEdgeHz }
    public let upperEdge: Double
    /// `bandCount + 1` edges in Hz; band b is [edges[b], edges[b + 1]).
    public let edges: [Double]

    let firstBin: [Int]
    let binCounts: [Int]
    let offsets: [Int]
    let weightTable: [Float]
    /// The same weights in Double, for ownership decisions (no Float ties).
    let exactWeights: [Double]
    let scales: [Float]
    let widths: [Double]

    public init(bandCount: BandCount, size: FFTSize, sampleRate: Double) throws(BandLayoutError) {
        guard sampleRate.isFinite, sampleRate >= BandLayout.minimumSampleRate else { throw .invalidSampleRate(sampleRate) }
        let b = bandCount.rawValue
        let lower = BandLayout.lowerEdgeHz
        let upper = min(BandLayout.upperEdgeLimitHz, sampleRate / 2)
        var edges = (0...b).map { lower * pow(upper / lower, Double($0) / Double(b)) }
        edges[0] = lower
        edges[b] = upper

        let n = size.rawValue
        let m = n / 2
        let delta = sampleRate / Double(n)
        func interval(_ k: Int) -> (lo: Double, hi: Double) {
            (k == 1 ? 0 : (Double(k) - 0.5) * delta, k == m ? Double(k) * delta : (Double(k) + 0.5) * delta)
        }

        var firstBin: [Int] = [], binCounts: [Int] = [], offsets: [Int] = []
        var weightTable: [Float] = [], exactWeights: [Double] = [], scales: [Float] = [], widths: [Double] = []
        for band in 0..<b {
            let lo = edges[band], hi = edges[band + 1]
            // Candidate bins whose intervals can reach [lo, hi].
            let kLow = max(1, Int((lo / delta - 0.5).rounded(.down)))
            let kHigh = min(m, Int((hi / delta + 0.5).rounded(.up)))
            var first = -1
            var weights: [Double] = []
            if kLow <= kHigh {
                for k in kLow...kHigh {
                    let bin = interval(k)
                    let overlap = min(hi, bin.hi) - max(lo, bin.lo)
                    let w = overlap > 0 ? overlap / (bin.hi - bin.lo) : 0
                    if w > BandLayout.weightEpsilon {
                        if first < 0 { first = k }
                        // Keep the range contiguous (an interior zero cannot occur: intervals tile).
                        weights.append(contentsOf: [Double](repeating: 0, count: k - first - weights.count))
                        weights.append(min(w, 1))
                    }
                }
            }
            // Every band of a valid layout overlaps some bin (ANL-002-R6): intervals tile 0…R/2.
            precondition(first >= 1 && !weights.isEmpty, "band \(band) of \(b) at N=\(n), R=\(sampleRate) is empty")
            let width = weights.reduce(0, +)
            firstBin.append(first)
            binCounts.append(weights.count)
            offsets.append(weightTable.count)
            weightTable.append(contentsOf: weights.map { Float($0) })
            exactWeights.append(contentsOf: weights)
            widths.append(width)
            scales.append(Float(1 / (BandLayout.hannEquivalentNoiseBandwidth * min(1, width))))
        }
        self.bandCount = bandCount
        self.size = size
        self.sampleRate = sampleRate
        self.upperEdge = upper
        self.edges = edges
        self.firstBin = firstBin
        self.binCounts = binCounts
        self.offsets = offsets
        self.weightTable = weightTable
        self.exactWeights = exactWeights
        self.scales = scales
        self.widths = widths
    }

    public func lowerEdge(ofBand band: Int) -> Double { edges[band] }
    public func upperEdge(ofBand band: Int) -> Double { edges[band + 1] }

    /// Geometric centre of the band's edges.
    public func centerFrequency(ofBand band: Int) -> Double { (edges[band] * edges[band + 1]).squareRoot() }

    /// The band's total weight W in bins (the sum of its overlap fractions).
    public func widthInBins(ofBand band: Int) -> Double { widths[band] }

    /// The bins the band reads (each with weight > 0).
    public func binRange(ofBand band: Int) -> Range<Int> { firstBin[band]..<(firstBin[band] + binCounts[band]) }

    /// The band's weights over `binRange(ofBand:)` (allocates; inspection only).
    public func weights(ofBand band: Int) -> [Float] {
        Array(weightTable[offsets[band]..<(offsets[band] + binCounts[band])])
    }

    /// The band whose [lower, upper) contains `frequency`; nil outside 20 Hz…upper or for NaN.
    public func band(containingFrequency frequency: Double) -> Int? {
        guard frequency >= edges[0], frequency < edges[bandCount.rawValue] else { return nil }
        var lo = 0, hi = bandCount.rawValue - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if edges[mid] <= frequency { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The band with the largest weight of bin `bin` (lower band on a tie); nil if no band reads it.
    public func ownerBand(ofBin bin: Int) -> Int? {
        precondition((0..<size.binCount).contains(bin), "bin \(bin) out of range")
        var best: Int?
        var bestWeight = 0.0
        for band in 0..<bandCount.rawValue where binRange(ofBand: band).contains(bin) {
            let w = exactWeights[offsets[band] + bin - firstBin[band]]
            if w > bestWeight { best = band; bestWeight = w }
        }
        return best
    }
}
