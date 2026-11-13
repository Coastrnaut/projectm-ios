// SpectrumConfiguration.swift — size, hop, sample rate and channel mode of a spectrum stream
// (ANL-001-R2, R5, R6; data-model.md). Invalid configurations cannot be constructed.

/// Which channel of interleaved stereo input is analysed (ANL-001-R5). Choosing a channel in the
/// UI is AUD-009's job; this only describes the mono mix the analysis sees.
public enum ChannelMode: Sendable, Hashable {
    /// (L + R)·0.5 — the default.
    case mid
    case left
    case right
}

public enum SpectrumConfigurationError: Error, Equatable, Sendable {
    /// The hop must be 1…size.
    case hopOutOfRange(hop: Int, size: Int)
    /// The sample rate must be finite and positive.
    case invalidSampleRate(Double)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.hopOutOfRange(a, b), .hopOutOfRange(c, d)): return a == c && b == d
        case let (.invalidSampleRate(a), .invalidSampleRate(b)): return a == b || (a.isNaN && b.isNaN)
        default: return false
        }
    }
}

public struct SpectrumConfiguration: Sendable, Hashable {
    public let size: FFTSize
    /// Samples between the starts of consecutive frames, 1…size (default size/2, 50 % overlap).
    public let hop: Int
    /// Hz; the normalized stream is 44,100 Hz.
    public let sampleRate: Double
    public let channelMode: ChannelMode

    public init(size: FFTSize = .n2048, hop: Int? = nil, sampleRate: Double = 44_100,
                channelMode: ChannelMode = .mid) throws(SpectrumConfigurationError) {
        let hop = hop ?? size.rawValue / 2
        guard (1...size.rawValue).contains(hop) else {
            throw .hopOutOfRange(hop: hop, size: size.rawValue)
        }
        guard sampleRate.isFinite, sampleRate > 0 else { throw .invalidSampleRate(sampleRate) }
        self.size = size
        self.hop = hop
        self.sampleRate = sampleRate
        self.channelMode = channelMode
    }

    public var binCount: Int { size.binCount }
    public var binWidth: Double { size.binWidth(sampleRate: sampleRate) }
    public func frequency(ofBin bin: Int) -> Double { size.frequency(ofBin: bin, sampleRate: sampleRate) }
    public func nearestBin(toFrequency frequency: Double) -> Int {
        size.nearestBin(toFrequency: frequency, sampleRate: sampleRate)
    }
}
