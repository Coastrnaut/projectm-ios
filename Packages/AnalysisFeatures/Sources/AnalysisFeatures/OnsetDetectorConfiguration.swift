// OnsetDetectorConfiguration.swift — parameters of the spectral flux onset detector and the event it
// reports (ANL-004-R4, R5, R9, R13; data-model.md; defaults from research ANL-004-D3).
// Invalid configurations cannot be constructed.

public enum OnsetDetectorConfigurationError: Error, Equatable, Sendable {
    /// Finite and at least `BandLayout.minimumSampleRate` (8,000 Hz).
    case invalidSampleRate(Double)
    /// −120…−20 dBFS.
    case invalidFloor(Float)
    /// Greater than 0 and less than 1.
    case invalidThresholdOffset(Float)
    /// 0…10.
    case invalidThresholdMultiplier(Float)
    /// Greater than 0 and at most 2 s.
    case invalidThresholdWindow(Double)
    /// 0…2 s.
    case invalidMinimumInterOnsetInterval(Double)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        func same<T: FloatingPoint>(_ a: T, _ b: T) -> Bool { a == b || (a.isNaN && b.isNaN) }
        switch (lhs, rhs) {
        case let (.invalidSampleRate(a), .invalidSampleRate(b)): return same(a, b)
        case let (.invalidFloor(a), .invalidFloor(b)): return same(a, b)
        case let (.invalidThresholdOffset(a), .invalidThresholdOffset(b)): return same(a, b)
        case let (.invalidThresholdMultiplier(a), .invalidThresholdMultiplier(b)): return same(a, b)
        case let (.invalidThresholdWindow(a), .invalidThresholdWindow(b)): return same(a, b)
        case let (.invalidMinimumInterOnsetInterval(a), .invalidMinimumInterOnsetInterval(b)): return same(a, b)
        default: return false
        }
    }
}

public struct OnsetDetectorConfiguration: Sendable, Hashable {
    public static let defaultFloorDecibels: Float = -70
    public static let defaultThresholdOffset: Float = 0.06
    public static let defaultThresholdMultiplier: Float = 1.5
    public static let defaultThresholdWindowSeconds: Double = 0.1
    public static let defaultMinimumInterOnsetSeconds: Double = 0.05
    /// Capacity of the detector's flux history; the threshold window never spans more frames.
    public static let maximumHistoryFrames = 128

    /// The defaults at 44,100 Hz (the normalized stream's rate), without a throwing call.
    public static let standard = OnsetDetectorConfiguration(
        validSampleRate: 44_100, bandCount: .b64, floorDecibels: defaultFloorDecibels,
        thresholdOffset: defaultThresholdOffset, thresholdMultiplier: defaultThresholdMultiplier,
        thresholdWindowSeconds: defaultThresholdWindowSeconds,
        minimumInterOnsetSeconds: defaultMinimumInterOnsetSeconds)

    /// Hz; one detector serves one sample rate (its band tables are built for it).
    public let sampleRate: Double
    /// ANL-002 bands the flux is computed on.
    public let bandCount: BandCount
    /// Silence floor: bands at or below it read 0 (ANL-004-R2, R3).
    public let floorDecibels: Float
    /// δ: the absolute part of the threshold, in flux units (0…1).
    public let thresholdOffset: Float
    /// κ: weight of the mean flux of the preceding window.
    public let thresholdMultiplier: Float
    /// Length of the threshold's averaging window.
    public let thresholdWindowSeconds: Double
    /// Events closer than this to the previous event are suppressed.
    public let minimumInterOnsetSeconds: Double

    public init(sampleRate: Double = 44_100, bandCount: BandCount = .b64,
                floorDecibels: Float = defaultFloorDecibels,
                thresholdOffset: Float = defaultThresholdOffset,
                thresholdMultiplier: Float = defaultThresholdMultiplier,
                thresholdWindowSeconds: Double = defaultThresholdWindowSeconds,
                minimumInterOnsetSeconds: Double = defaultMinimumInterOnsetSeconds) throws(OnsetDetectorConfigurationError) {
        guard sampleRate.isFinite, sampleRate >= BandLayout.minimumSampleRate else { throw .invalidSampleRate(sampleRate) }
        guard floorDecibels >= -120, floorDecibels <= -20 else { throw .invalidFloor(floorDecibels) }
        guard thresholdOffset > 0, thresholdOffset < 1 else { throw .invalidThresholdOffset(thresholdOffset) }
        guard thresholdMultiplier >= 0, thresholdMultiplier <= 10 else { throw .invalidThresholdMultiplier(thresholdMultiplier) }
        guard thresholdWindowSeconds > 0, thresholdWindowSeconds <= 2 else { throw .invalidThresholdWindow(thresholdWindowSeconds) }
        guard minimumInterOnsetSeconds >= 0, minimumInterOnsetSeconds <= 2 else {
            throw .invalidMinimumInterOnsetInterval(minimumInterOnsetSeconds)
        }
        self.init(validSampleRate: sampleRate, bandCount: bandCount, floorDecibels: floorDecibels,
                  thresholdOffset: thresholdOffset, thresholdMultiplier: thresholdMultiplier,
                  thresholdWindowSeconds: thresholdWindowSeconds, minimumInterOnsetSeconds: minimumInterOnsetSeconds)
    }

    private init(validSampleRate: Double, bandCount: BandCount, floorDecibels: Float, thresholdOffset: Float,
                 thresholdMultiplier: Float, thresholdWindowSeconds: Double, minimumInterOnsetSeconds: Double) {
        sampleRate = validSampleRate
        self.bandCount = bandCount
        self.floorDecibels = floorDecibels
        self.thresholdOffset = thresholdOffset
        self.thresholdMultiplier = thresholdMultiplier
        self.thresholdWindowSeconds = thresholdWindowSeconds
        self.minimumInterOnsetSeconds = minimumInterOnsetSeconds
    }

    /// Frames in the threshold window at `hop`: round(window · rate / hop), clamped to 1…128.
    public func historyFrames(hop: Int) -> Int {
        guard hop > 0 else { return 1 }
        let frames = (thresholdWindowSeconds * sampleRate / Double(hop)).rounded()
        return Int(min(max(frames, 1), Double(OnsetDetectorConfiguration.maximumHistoryFrames)))
    }

    /// round(interval · rate).
    public var minimumInterOnsetSamples: Int64 {
        Int64((minimumInterOnsetSeconds * sampleRate).rounded())
    }
}

/// One detected onset (ANL-004-R9). Times are on the stream's sample clock.
public struct OnsetEvent: Sendable, Hashable {
    /// 1, 2, 3… over the detector's lifetime; never reused, not restarted by `reset()`.
    public let sequence: UInt64
    /// First sample of the producing frame's newest hop: `frame.index + size − hop` (ANL-004-R6).
    public let sampleIndex: Int64
    /// The producing frame's first sample.
    public let frameIndex: Int64
    /// The frame's detection value (0…1), above `threshold`.
    public let strength: Float
    /// The threshold the strength crossed.
    public let threshold: Float
    public let sampleRate: Double
    /// The producing frame's timestamp.
    public let timestampNanoseconds: UInt64

    public init(sequence: UInt64, sampleIndex: Int64, frameIndex: Int64, strength: Float, threshold: Float,
                sampleRate: Double, timestampNanoseconds: UInt64) {
        self.sequence = sequence
        self.sampleIndex = sampleIndex
        self.frameIndex = frameIndex
        self.strength = strength
        self.threshold = threshold
        self.sampleRate = sampleRate
        self.timestampNanoseconds = timestampNanoseconds
    }

    /// `sampleIndex / sampleRate`.
    public var seconds: Double { Double(sampleIndex) / sampleRate }
}
