// RecordingSettings.swift — REC-003 settings, codecs and geometry (spec specs/058-rec-003-video-recording,
// data-model.md, research REC-003-D2, D3). Plain Swift; builds on Linux.

/// The video codecs the recorder can write, in the writer's preference order (REC-003-R6).
public enum RecordingCodec: String, Sendable, CaseIterable, Equatable {
    case hevc
    case h264

    public var title: String {
        switch self {
        case .hevc: "HEVC"
        case .h264: "H.264"
        }
    }

    /// The sample description's four-character code as it is written ("hvc1", "avc1").
    public var fourCharacterCode: String {
        switch self {
        case .hevc: "hvc1"
        case .h264: "avc1"
        }
    }

    /// Average bits per pixel per frame (research REC-003-D2).
    var bitsPerPixel: Double {
        switch self {
        case .hevc: 0.12
        case .h264: 0.2
        }
    }

    /// Average bit rate for a size and frame rate (at least 1 Mb/s so tiny sizes stay sharp).
    public func averageBitRate(width: Int, height: Int, frameRate: Int) -> Int {
        max(1_000_000, Int(Double(width * height * frameRate) * bitsPerPixel))
    }
}

/// What a recording writes (REC-003-R5 to R7, R11). REC-005 profiles (`RecordingQualityProfile`) make these;
/// `.standard` is REC-003's settings and REC-005's default.
public struct RecordingSettings: Sendable, Equatable {
    /// Ticks per second of every written time (1/600 s divides 24, 25, 30 and 60 frames per second).
    public static let timescale: Int32 = 600

    /// At most this many frames per second (1...60).
    public var maxFrameRate: Int
    /// The video's long side is at most this many pixels (≥ 16, even).
    public var maxLongSide: Int
    /// A recording stops by itself at this length.
    public var maxDurationSeconds: Int
    /// Frames between "pixel buffer taken" and "appended" (≥ 1).
    public var framesInFlight: Int
    /// Codecs tried in order.
    public var codecPreference: [RecordingCodec]
    /// REC-005: a fixed average bit rate (bits per second, at least 100 kb/s); nil keeps REC-003's per-pixel rule.
    public var fixedBitRate: Int?

    /// REC-005: a long-side cap above any drawable (Max: the screen's own size, never scaled).
    public static let nativeLongSide = 16_384

    public init(maxFrameRate: Int = 30, maxLongSide: Int = 1920, maxDurationSeconds: Int = 600, framesInFlight: Int = 3,
                codecPreference: [RecordingCodec] = [.hevc, .h264], fixedBitRate: Int? = nil) {
        self.fixedBitRate = fixedBitRate.map { (rate: Int) -> Int in max(rate, 100_000) }
        self.maxFrameRate = min(max(maxFrameRate, 1), 60)
        let side = max(maxLongSide, 16)
        self.maxLongSide = side - side % 2
        self.maxDurationSeconds = max(maxDurationSeconds, 1)
        self.framesInFlight = max(framesInFlight, 1)
        self.codecPreference = codecPreference.isEmpty ? [.hevc, .h264] : codecPreference
    }

    public static let standard = RecordingSettings()

    /// The minimum spacing of written frames, in ticks (20 at 30 fps).
    public var frameIntervalTicks: Int64 { Int64(Self.timescale) / Int64(maxFrameRate) }

    /// REC-005: the average bit rate written for `codec` at an output size: the fixed rate, else REC-003's rule.
    public func averageBitRate(codec: RecordingCodec, width: Int, height: Int) -> Int {
        fixedBitRate ?? codec.averageBitRate(width: width, height: height, frameRate: maxFrameRate)
    }

    /// The duration limit in ticks.
    public var maxDurationTicks: Int64 { Int64(maxDurationSeconds) * Int64(Self.timescale) }
}

/// The recorded picture's size (research REC-003-D3): the drawable cropped to even dimensions (the
/// last column or row goes), and the video's size, which fits `maxLongSide` with the same aspect.
public struct RecordingGeometry: Sendable, Equatable {
    /// The pixel buffers' size: what the GPU copies, from the top-left of the drawable.
    public let sourceWidth: Int
    public let sourceHeight: Int
    /// The encoded video's size (the writer scales when it differs from the source).
    public let outputWidth: Int
    public let outputHeight: Int

    /// nil when the drawable is smaller than 2 × 2 pixels.
    public init?(drawableWidth: Int, drawableHeight: Int, maxLongSide: Int) {
        let w = drawableWidth - drawableWidth % 2, h = drawableHeight - drawableHeight % 2
        guard w >= 2, h >= 2 else { return nil }
        sourceWidth = w
        sourceHeight = h
        let long = max(w, h)
        let cap = max(maxLongSide - maxLongSide % 2, 2)
        if long <= cap {
            outputWidth = w
            outputHeight = h
        } else {
            let scale = Double(cap) / Double(long)
            outputWidth = Self.even(Double(w) * scale)
            outputHeight = Self.even(Double(h) * scale)
        }
    }

    /// True when the writer scales the source to the output size.
    public var isScaled: Bool { sourceWidth != outputWidth || sourceHeight != outputHeight }

    /// Rounded to the nearest even number, at least 2.
    private static func even(_ value: Double) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }

    /// True when a drawable of this size crops to the same source size.
    public func matches(drawableWidth: Int, drawableHeight: Int) -> Bool {
        drawableWidth - drawableWidth % 2 == sourceWidth && drawableHeight - drawableHeight % 2 == sourceHeight
    }
}
