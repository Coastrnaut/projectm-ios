// FFTSize.swift — the five selectable FFT sizes and their bin helpers (ANL-001-R2, R15).
// Sizes match the AUD-016 catalog's documented bins (ReferenceToneCatalog.fftSizes).

/// A supported FFT size: a power of two from 512 to 8,192 samples.
public enum FFTSize: Int, CaseIterable, Sendable, Hashable {
    case n512 = 512
    case n1024 = 1_024
    case n2048 = 2_048
    case n4096 = 4_096
    case n8192 = 8_192

    /// The largest size; analyzers preallocate for it.
    public static let maximum: FFTSize = .n8192

    /// nil for any count that is not one of the five sizes (never rounded).
    public init?(samples: Int) {
        self.init(rawValue: samples)
    }

    /// log2 of the size (9…13).
    public var log2: Int { rawValue.trailingZeroBitCount }

    /// One-sided bins, DC through Nyquist: N/2 + 1.
    public var binCount: Int { rawValue / 2 + 1 }

    /// Width of one bin in Hz: R/N.
    public func binWidth(sampleRate: Double) -> Double { sampleRate / Double(rawValue) }

    /// Centre frequency of bin `k` in Hz: k·R/N.
    public func frequency(ofBin bin: Int, sampleRate: Double) -> Double {
        Double(bin) * sampleRate / Double(rawValue)
    }

    /// The bin nearest to `frequency` (f·N/R rounded half up, as `ReferenceToneCatalog.nearestBin`),
    /// clamped to 0…N/2.
    public func nearestBin(toFrequency frequency: Double, sampleRate: Double) -> Int {
        let exact = frequency * Double(rawValue) / sampleRate
        guard exact.isFinite else { return exact > 0 ? rawValue / 2 : 0 }
        let rounded = (exact + 0.5).rounded(.down)
        return Int(min(max(rounded, 0), Double(rawValue / 2)))
    }
}
