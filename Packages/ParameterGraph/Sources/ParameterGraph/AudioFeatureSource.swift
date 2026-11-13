// AudioFeatureSource.swift — which normalized audio feature drives a binding, and one frame of
// features (MOD-002-R1, R6; research MOD-002-D2, D3; contract C1).
//
// The frame borrows the caller's band buffer for one `advance` call, so nothing is copied or
// allocated and this module stays independent of the analysis types (Constitution VI): the native
// spectra pass their band scratch; a consumer of the analysis event bus (ANL-016) passes its copied
// bands plus `AnalysisFrame.onsetFlux` and `beatConfidence`.

/// A normalized (0…1) audio feature a binding can follow.
public enum AudioFeatureSource: Sendable, Hashable, CustomStringConvertible {
    /// One band's level (ANL-002), by 0-based index.
    case band(Int)
    /// The mean level of all bands in the frame.
    case bandMean
    /// The onset detection value (ANL-004).
    case onset
    /// The beat tracker's confidence (ANL-005).
    case beatConfidence

    /// The highest band index (the largest band count is 128).
    public static let maximumBandIndex = 127

    /// The stable identifier (MOD-013 stores it): `audio.band.<index>`, `audio.bandMean`,
    /// `audio.onset`, `audio.beatConfidence`.
    public var id: String {
        switch self {
        case let .band(index): "audio.band.\(index)"
        case .bandMean: "audio.bandMean"
        case .onset: "audio.onset"
        case .beatConfidence: "audio.beatConfidence"
        }
    }

    public var description: String { id }

    /// Parses exactly the identifiers `id` produces (decimal band index 0…127, no sign, no
    /// leading zeros); anything else is nil.
    public init?(id: String) {
        switch id {
        case "audio.bandMean": self = .bandMean
        case "audio.onset": self = .onset
        case "audio.beatConfidence": self = .beatConfidence
        default:
            let prefix = "audio.band."
            guard id.hasPrefix(prefix) else { return nil }
            let digits = id.dropFirst(prefix.count)
            guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }),
                  digits.count == 1 || digits.first != "0",
                  let index = Int(digits), index <= Self.maximumBandIndex else { return nil }
            self = .band(index)
        }
    }

    /// The feature's value in `frame`; a missing or non-finite reading is 0 (MOD-002-R6).
    public func value(in frame: AudioFeatureFrame) -> Double {
        switch self {
        case let .band(index):
            guard index >= 0, index < frame.bands.count else { return 0 }
            return Self.finite(Double(frame.bands[index]))
        case .bandMean:
            guard !frame.bands.isEmpty else { return 0 }
            var sum = 0.0
            for level in frame.bands { sum += Self.finite(Double(level)) }
            return sum / Double(frame.bands.count)
        case .onset:
            return frame.onset.map { Self.finite(Double($0)) } ?? 0
        case .beatConfidence:
            return frame.beatConfidence.map(Self.finite) ?? 0
        }
    }

    private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
}

/// One frame of normalized audio features. `bands` is borrowed: valid only during the call it is
/// passed to.
public struct AudioFeatureFrame {
    public var bands: UnsafeBufferPointer<Float>
    public var onset: Float?
    public var beatConfidence: Double?

    public init(bands: UnsafeBufferPointer<Float>, onset: Float? = nil, beatConfidence: Double? = nil) {
        self.bands = bands
        self.onset = onset
        self.beatConfidence = beatConfidence
    }

    /// No audio: every feature reads 0.
    public static var silent: AudioFeatureFrame { AudioFeatureFrame(bands: UnsafeBufferPointer(start: nil, count: 0)) }
}
