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

    /// REC-014: the output's aspect (Match screen: REC-003's geometry).
    public var aspect: RecordingAspect
    /// REC-014: the device class's largest encoded frame (every recording).
    public var outputCap: RecordingOutputCap

    /// REC-016-R1 (ADR-0061): the writer writes a movie fragment this often (seconds, at least 0.1), so a writer
    /// failure keeps every completed fragment readable. A normal finish produces an ordinary MP4.
    public var fragmentIntervalSeconds: Double = 1.0 {
        didSet { fragmentIntervalSeconds = max(fragmentIntervalSeconds, 0.1) }
    }

    /// REC-005: a long-side cap above any drawable (Max: the screen's own size, never scaled).
    public static let nativeLongSide = 16_384

    public init(maxFrameRate: Int = 30, maxLongSide: Int = 1920, maxDurationSeconds: Int = 600, framesInFlight: Int = 3,
                codecPreference: [RecordingCodec] = [.hevc, .h264], fixedBitRate: Int? = nil,
                aspect: RecordingAspect = .matchScreen, outputCap: RecordingOutputCap = .regular) {
        self.aspect = aspect
        self.outputCap = outputCap
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

/// The recorded picture's size (research REC-003-D3; REC-014 contract C1): the drawable cropped to even dimensions
/// (the last column or row goes) is the pixel buffers' size; the video's size fits the profile's long side, the
/// aspect (centred crop to fill, never upscaled) and the device's output cap.
public struct RecordingGeometry: Sendable, Equatable {
    /// The pixel buffers' size: what the GPU copies, from the top-left of the drawable.
    public let sourceWidth: Int
    public let sourceHeight: Int
    /// The encoded video's size (the writer scales when it differs from the source).
    public let outputWidth: Int
    public let outputHeight: Int
    /// REC-014: the writer crops the centre to fill the output (every aspect but Match screen).
    public let cropsToFill: Bool
    /// REC-014-R6: the asked custom size when it was reduced to fit (nil otherwise).
    public let reducedCustomSize: RecordingCustomSize?

    /// Match screen (REC-003); nil when the drawable is smaller than 2 × 2 pixels.
    public init?(drawableWidth: Int, drawableHeight: Int, maxLongSide: Int, aspect: RecordingAspect = .matchScreen,
                 cap: RecordingOutputCap = .regular) {
        let w = drawableWidth - drawableWidth % 2, h = drawableHeight - drawableHeight % 2
        guard w >= 2, h >= 2 else { return nil }
        let limit: Int = Swift.min(Swift.max(maxLongSide - maxLongSide % 2, 2), cap.maxSide)
        guard let size = Self.outputSize(width: w, height: h, limit: limit, aspect: aspect, cap: cap) else { return nil }
        sourceWidth = w
        sourceHeight = h
        outputWidth = size.width
        outputHeight = size.height
        cropsToFill = aspect != .matchScreen
        reducedCustomSize = size.reduced
    }

    /// REC-014: the geometry of `settings` (long side, aspect, cap) on this drawable.
    public init?(drawableWidth: Int, drawableHeight: Int, settings: RecordingSettings) {
        self.init(drawableWidth: drawableWidth, drawableHeight: drawableHeight, maxLongSide: settings.maxLongSide,
                  aspect: settings.aspect, cap: settings.outputCap)
    }

    private typealias Output = (width: Int, height: Int, reduced: RecordingCustomSize?)

    private static func outputSize(width w: Int, height h: Int, limit: Int, aspect: RecordingAspect,
                                   cap: RecordingOutputCap) -> Output? {
        guard let ratio = aspect.ratio else { return screenSize(width: w, height: h, limit: limit, cap: cap) }
        let crop: (width: Int, height: Int) = centredCrop(width: w, height: h, ratio: ratio)
        let m: Int = multiple(ratio: ratio, crop: crop, limit: limit, maxPixels: cap.maxPixels)
        guard case .custom(let asked) = aspect else {
            return m > 0 ? (ratio.width * m, ratio.height * m, nil) : nil
        }
        let fits: Bool = asked.width <= crop.width && asked.height <= crop.height
            && Swift.max(asked.width, asked.height) <= limit && asked.width * asked.height <= cap.maxPixels
        if fits { return (asked.width, asked.height, nil) }
        // Uniform scale, sides floored to even (always within every limit).
        let longAsked = Double(Swift.max(asked.width, asked.height))
        let pixels = Double(asked.width) * Double(asked.height)
        let factors: [Double] = [Double(limit) / longAsked, Double(crop.width) / Double(asked.width),
                                 Double(crop.height) / Double(asked.height), (Double(cap.maxPixels) / pixels).squareRoot()]
        let f: Double = factors.min() ?? 1
        let fw: Int = floorEven(Double(asked.width) * f), fh: Int = floorEven(Double(asked.height) * f)
        // The exact ratio when it is nearly as large as the fallback (research REC-014-D3).
        if m > 0, Swift.max(ratio.width, ratio.height) * m * 10 >= Swift.max(fw, fh) * 9 {
            return (ratio.width * m, ratio.height * m, asked)
        }
        guard fw >= 2, fh >= 2, fw * fh <= cap.maxPixels else { return nil }
        return (fw, fh, asked)
    }

    /// Match screen: REC-003's fit to the long side (nearest even), then the cap's pixel count (floored to even).
    private static func screenSize(width w: Int, height h: Int, limit: Int, cap: RecordingOutputCap) -> Output {
        var ow: Int = w, oh: Int = h
        let long = Swift.max(w, h)
        if long > limit {
            let scale = Double(limit) / Double(long)
            ow = even(Double(w) * scale)
            oh = even(Double(h) * scale)
        }
        if ow * oh > cap.maxPixels {
            let f: Double = (Double(cap.maxPixels) / (Double(ow) * Double(oh))).squareRoot()
            ow = Swift.max(floorEven(Double(ow) * f), 2)
            oh = Swift.max(floorEven(Double(oh) * f), 2)
            while ow * oh > cap.maxPixels && ow > 2 && oh > 2 {   // never above the budget (floating guard)
                ow -= 2
                oh -= 2
            }
        }
        return (ow, oh, nil)
    }

    /// The largest centred rectangle of `ratio` inside w × h (floored).
    private static func centredCrop(width w: Int, height h: Int, ratio: (width: Int, height: Int)) -> (width: Int, height: Int) {
        if w * ratio.height <= h * ratio.width {   // the source is narrower: full width
            return (w, w * ratio.height / ratio.width)
        }
        return (h * ratio.width / ratio.height, h)
    }

    /// The largest m (even when a ratio term is odd, so both sides are even) within every limit; 0 when none.
    private static func multiple(ratio: (width: Int, height: Int), crop: (width: Int, height: Int), limit: Int, maxPixels: Int) -> Int {
        let u: Int = ratio.width, v: Int = ratio.height
        let step: Int = (u % 2 == 1 || v % 2 == 1) ? 2 : 1
        var m: Int = Swift.min(limit / Swift.max(u, v), crop.width / u, crop.height / v)
        m = Swift.min(m, Int((Double(maxPixels) / (Double(u) * Double(v))).squareRoot()))
        while m > 0 && u * m * v * m > maxPixels { m -= 1 }
        return Swift.max(m - m % step, 0)
    }

    /// True when the writer scales the source to the output size.
    public var isScaled: Bool { sourceWidth != outputWidth || sourceHeight != outputHeight }

    /// Rounded to the nearest even number, at least 2.
    private static func even(_ value: Double) -> Int {
        Swift.max(2, Int((value / 2).rounded()) * 2)
    }

    /// Rounded down to an even number (may be 0). A tiny tolerance absorbs floating error on exact products
    /// (1918 × 1280/1918 must give 1280, not 1278); the true value never exceeds its limit.
    private static func floorEven(_ value: Double) -> Int {
        let whole = Int((value + 1e-7).rounded(.down))
        return whole - whole % 2
    }

    /// True when a drawable of this size crops to the same source size.
    public func matches(drawableWidth: Int, drawableHeight: Int) -> Bool {
        drawableWidth - drawableWidth % 2 == sourceWidth && drawableHeight - drawableHeight % 2 == sourceHeight
    }
}
