// SpectralBinRange.swift — the whole spectrum bins of a frequency range (ANL-010-R6; research
// ANL-010-D7; contracts/spectral-centroid.md C1).
//
// Spectral-shape descriptors (ANL-010 centroid, and later ANL-011 rolloff and ANL-012 flatness)
// analyse the same bins of an ANL-001 spectrum: every whole bin k whose centre k·R/N lies in
// [lower, upper], DC (k = 0) never included, the Nyquist bin (N/2) the last possible. No fractional
// edge weights (ANL-002's band rule): a descriptor over hundreds of bins does not need them.
// Pure, allocation-free, Linux-portable.

public struct SpectralBinRange: Sendable, Hashable {
    /// First bin, at least 1.
    public let first: Int
    /// Last bin, at most N/2.
    public let last: Int

    /// Bins from max(1, ⌈lower·N/R⌉) through min(N/2, ⌊upper·N/R⌋); nil when no whole bin lies in
    /// the range or an input is not finite (lower ≥ 0, upper > lower, rate > 0).
    public init?(lowerFrequency: Double, upperFrequency: Double, size: FFTSize, sampleRate: Double) {
        guard lowerFrequency.isFinite, upperFrequency.isFinite, sampleRate.isFinite, sampleRate > 0,
              lowerFrequency >= 0, upperFrequency > lowerFrequency else { return nil }
        let points = Double(size.rawValue)
        let nyquistBin: Int = size.rawValue / 2
        let lowerExact: Double = lowerFrequency * points / sampleRate
        let upperExact: Double = upperFrequency * points / sampleRate
        let lowerBin: Double = min(lowerExact.rounded(.up), Double(nyquistBin + 1))
        let upperBin: Double = min(upperExact.rounded(.down), Double(nyquistBin))
        let first: Int = max(1, Int(lowerBin))
        let last: Int = Int(upperBin)
        guard first <= last else { return nil }
        self.first = first
        self.last = last
    }

    /// Bins in the range.
    public var count: Int { last - first + 1 }
}
