// AnimatedImageModel.swift — the plain-Swift model of animated images (MED-008-R3 to R6, R8, R13; specs/257-med-008-
// animated-images, contracts/animated-image.md; research MED-008-D3 to D6). Builds on every platform (Linux too).
//
// * `AnimationDelayRule`: a frame's delay as played, rounded to 0.1 ms. The browser rule (missing, non-finite or under 20 ms → 100 ms),
//   at most 60 s, and with Reduce flashing at least 334 ms (at most 3 frame changes a second).
// * `AnimationTimeline`: the clamped delays, their cumulative starts and total; the frame for an elapsed time is a pure
//   function of `elapsed % total` (binary search, integer nanoseconds), so the animation always loops and the frame at
//   t + total equals the frame at t.
// * `AnimatedFrameBudget`: the byte budget for decoded frames by device class (physical memory under 4 GiB: 32 MB,
//   under 8 GiB: 64 MB, otherwise 128 MB) and the decoded frame size that fits it (2 resident frames plus a 4-frame
//   decode reserve: the ImageIO bitmap, the pixels, the texels and the new texture).
// * `AnimatedFrameCache`: decoded frames by index with byte accounting. A decode reserves its transient bytes first;
//   the least recently used frame is evicted to make room, never frame 0 (kept for Reduce Motion and the fallback) nor
//   the frame on screen (`pinned`). Accounted bytes (resident + reserved) never exceed the budget; `peakBytes` records
//   the most ever accounted.
// * `AnimatedImportLimits`: import caps (600 frames, 2048 px, 32 M stored pixels in all frames together).
import Foundation

/// How long a frame plays (MED-008-R4).
public enum AnimationDelayRule {
    /// Delays shorter than this play as `browserDefaultNanoseconds` (the browser rule).
    public static let browserThresholdNanoseconds: UInt64 = 20_000_000
    public static let browserDefaultNanoseconds: UInt64 = 100_000_000
    /// Delays are rounded to 0.1 ms: files and ImageIO keep them as 32-bit floats (0.2 s reads as 0.2000000030 s).
    public static let quantumNanoseconds: UInt64 = 100_000
    /// The longest a frame plays.
    public static let maximumNanoseconds: UInt64 = 60_000_000_000
    /// With Reduce flashing: at most 3 frame changes a second (1.5 alternations, half the 3 Hz flash limit).
    public static let reducedFlashingMinimumNanoseconds: UInt64 = 334_000_000

    /// The played delay of a frame whose file states `seconds` (nil: none stated).
    public static func clamped(seconds: Double?, reduceFlashing: Bool) -> UInt64 {
        var nanoseconds: UInt64 = browserDefaultNanoseconds
        if let seconds, seconds.isFinite {
            let raw: Double = seconds * 1e9
            if raw >= Double(maximumNanoseconds) {
                nanoseconds = maximumNanoseconds
            } else if raw >= Double(browserThresholdNanoseconds) - Double(quantumNanoseconds) / 2 {
                nanoseconds = max(UInt64((raw / Double(quantumNanoseconds)).rounded()) * quantumNanoseconds,
                                  browserThresholdNanoseconds)
            }
        }
        if reduceFlashing { nanoseconds = max(nanoseconds, reducedFlashingMinimumNanoseconds) }
        return nanoseconds
    }
}

/// The clamped frame timing of one animation (MED-008-R5, R6).
public struct AnimationTimeline: Sendable, Equatable {
    /// Played delay of each frame (nanoseconds, each > 0).
    public let delays: [UInt64]
    /// Start of each frame within one loop (`starts[0] == 0`).
    public let starts: [UInt64]
    /// One loop.
    public let totalNanoseconds: UInt64

    /// Frames with delays as stated in the file (nil: not stated), clamped by `AnimationDelayRule`. No frames: one.
    public init(rawDelays: [Double?], reduceFlashing: Bool) {
        let source: [Double?] = rawDelays.isEmpty ? [nil] : rawDelays
        self.init(clampedDelays: source.map { (s: Double?) -> UInt64 in
            AnimationDelayRule.clamped(seconds: s, reduceFlashing: reduceFlashing)
        })
    }

    /// Frames with delays already clamped (each at least 1 ns).
    public init(clampedDelays: [UInt64]) {
        let delays: [UInt64] = clampedDelays.isEmpty ? [AnimationDelayRule.browserDefaultNanoseconds]
            : clampedDelays.map { (d: UInt64) -> UInt64 in max(d, 1) }
        var starts: [UInt64] = []
        starts.reserveCapacity(delays.count)
        var sum: UInt64 = 0
        for delay in delays {
            starts.append(sum)
            sum += delay
        }
        self.delays = delays
        self.starts = starts
        totalNanoseconds = sum
    }

    public var frameCount: Int { delays.count }

    /// The frame shown `elapsedNanoseconds` after the first frame: the last frame whose start ≤ elapsed % total.
    public func frameIndex(elapsedNanoseconds: UInt64) -> Int {
        let t: UInt64 = elapsedNanoseconds % totalNanoseconds
        var low = 0, high = starts.count - 1
        while low < high {
            let mid: Int = (low + high + 1) / 2
            if starts[mid] <= t { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// The decoded-frame budget by device class (MED-008-R8, research MED-008-D6).
public enum AnimatedFrameBudget {
    public static let megabyte = 1024 * 1024
    /// Frames that must fit besides the reserve: frame 0 and the frame on screen.
    public static let residentFrames = 2
    /// Transient frames a decode reserves: the ImageIO bitmap, the straight pixels, the texels and the new texture.
    public static let reserveFrames = 4

    /// Under 4 GiB → 32 MB; under 8 GiB → 64 MB; otherwise 128 MB.
    public static func bytes(physicalMemory: UInt64) -> Int {
        let gigabyte: UInt64 = 1024 * 1024 * 1024
        if physicalMemory < 4 * gigabyte { return 32 * megabyte }
        if physicalMemory < 8 * gigabyte { return 64 * megabyte }
        return 128 * megabyte
    }

    /// This device's budget.
    public static var current: Int { bytes(physicalMemory: ProcessInfo.processInfo.physicalMemory) }

    /// The bytes a decoded frame of `width` × `height` is accounted with (RGBA8, one level; a pixel of slack on each
    /// side, since ImageIO may round a scaled size up).
    public static func accountedFrameBytes(width: Int, height: Int) -> Int {
        (max(width, 1) + 1) * (max(height, 1) + 1) * 4
    }

    /// The decoded size of `width` × `height` frames: at most `maxSide` long and small enough that
    /// `residentFrames + reserveFrames` accounted frames fit in `budget`. Never larger than the source.
    public static func decodedSize(width: Int, height: Int, budget: Int, maxSide: Int) -> (width: Int, height: Int) {
        let w0: Int = max(width, 1), h0: Int = max(height, 1)
        let frames: Int = residentFrames + reserveFrames
        var scale: Double = min(1, Double(max(maxSide, 1)) / Double(max(w0, h0)))
        let maxPixels: Double = Double(max(budget, 1)) / Double(frames * 4)
        scale = min(scale, (maxPixels / (Double(w0) * Double(h0))).squareRoot())
        var w: Int = max(Int((Double(w0) * scale).rounded(.down)), 1)
        var h: Int = max(Int((Double(h0) * scale).rounded(.down)), 1)
        while frames * accountedFrameBytes(width: w, height: h) > budget, w > 1 || h > 1 {
            if w >= h { w = max(w - 1, 1); h = max(Int((Double(w) * Double(h0) / Double(w0)).rounded(.down)), 1) }
            else { h = max(h - 1, 1); w = max(Int((Double(h) * Double(w0) / Double(h0)).rounded(.down)), 1) }
        }
        return (w, h)
    }
}

/// What the frame cache of one animation holds (tests, diagnostics).
public struct AnimatedFrameCacheStatistics: Sendable, Equatable {
    public let budgetBytes: Int
    public let residentBytes: Int
    public let peakBytes: Int
    public let residentFrames: Int
    /// Frames decoded so far (frame 0 included; a frame evicted and decoded again counts twice).
    public let decodes: Int
    public let frameCount: Int
    public let frameWidth: Int
    public let frameHeight: Int
}

/// Decoded frames by index within a byte budget (MED-008-R8). Not thread-safe: the owner locks it.
public struct AnimatedFrameCache<Payload> {
    private struct Entry {
        var payload: Payload
        var bytes: Int
        var lastUse: UInt64
    }

    public let budgetBytes: Int
    public private(set) var residentBytes = 0
    public private(set) var reservedBytes = 0
    /// The most ever accounted (resident + reserved).
    public private(set) var peakBytes = 0
    /// The frame on screen (never evicted).
    public var pinned: Int?
    /// Frame 0 stays (Reduce Motion, the fallback picture).
    public let permanent: Int = 0
    private var entries: [Int: Entry] = [:]
    private var clock: UInt64 = 0

    public init(budgetBytes: Int) {
        self.budgetBytes = max(budgetBytes, 0)
    }

    public var residentFrames: Int { entries.count }
    public var accountedBytes: Int { residentBytes + reservedBytes }

    public func contains(_ index: Int) -> Bool { entries[index] != nil }

    /// The payload of `index` (marks it recently used).
    public mutating func payload(at index: Int) -> Payload? {
        guard entries[index] != nil else { return nil }
        clock &+= 1
        entries[index]!.lastUse = clock
        return entries[index]!.payload
    }

    /// Reserves `bytes` for a decode, evicting least recently used frames (never `permanent` or `pinned`); false when
    /// it cannot fit (nothing is reserved then).
    public mutating func reserve(_ bytes: Int) -> Bool {
        guard makeRoom(for: bytes) else { return false }
        reservedBytes += bytes
        notePeak()
        return true
    }

    /// Ends a reservation of `reserved` bytes and stores `payload` for `index` (`bytes` ≤ `reserved`, so it fits).
    /// False (nothing stored, the reservation ended) when it does not fit.
    @discardableResult
    public mutating func commit(_ index: Int, payload: Payload, bytes: Int, reserved: Int) -> Bool {
        reservedBytes = max(reservedBytes - reserved, 0)
        if let old = entries.removeValue(forKey: index) { residentBytes -= old.bytes }
        guard makeRoom(for: bytes) else { return false }
        clock &+= 1
        entries[index] = Entry(payload: payload, bytes: bytes, lastUse: clock)
        residentBytes += bytes
        notePeak()
        return true
    }

    /// Ends a reservation without storing anything (a failed decode).
    public mutating func cancel(reserved: Int) {
        reservedBytes = max(reservedBytes - reserved, 0)
    }

    private mutating func makeRoom(for bytes: Int) -> Bool {
        while accountedBytes + bytes > budgetBytes {
            var victim: Int?
            var oldest: UInt64 = .max
            for (index, entry) in entries where index != permanent && index != pinned && entry.lastUse < oldest {
                oldest = entry.lastUse
                victim = index
            }
            guard let victim, let removed = entries.removeValue(forKey: victim) else { return false }
            residentBytes -= removed.bytes
        }
        return true
    }

    private mutating func notePeak() {
        peakBytes = max(peakBytes, accountedBytes)
    }
}

/// Import caps of an animation (MED-008-R3).
public struct AnimatedImportLimits: Sendable, Equatable {
    /// Frames beyond this are dropped.
    public var maxFrames: Int
    /// The stored longest side (also at most `ImageImportLimits.maxStoredLongestSide`).
    public var maxStoredLongestSide: Int
    /// Stored pixels in all frames together.
    public var maxTotalPixels: Int

    public init(maxFrames: Int, maxStoredLongestSide: Int, maxTotalPixels: Int) {
        self.maxFrames = max(maxFrames, 1)
        self.maxStoredLongestSide = max(maxStoredLongestSide, 1)
        self.maxTotalPixels = max(maxTotalPixels, 1)
    }

    /// 600 frames, 2048 px, 32 M pixels (spec Clarifications).
    public static let standard = AnimatedImportLimits(maxFrames: 600, maxStoredLongestSide: 2048, maxTotalPixels: 32_000_000)

    /// The stored size of `frames` frames of `width` × `height`, scaled by `pixelFactor` (≤ 1) of the pixels that fit.
    public func storedSize(width: Int, height: Int, frames: Int, base: ImageImportLimits,
                           pixelFactor: Double = 1) -> (width: Int, height: Int) {
        let w0: Int = max(width, 1), h0: Int = max(height, 1)
        let side: Int = min(maxStoredLongestSide, base.maxStoredLongestSide)
        var scale: Double = min(1, Double(side) / Double(max(w0, h0)))
        let perFrame: Double = Double(maxTotalPixels) / Double(max(min(frames, maxFrames), 1))
        scale = min(scale, (perFrame / (Double(w0) * Double(h0))).squareRoot())
        scale *= max(min(pixelFactor, 1), 0).squareRoot()
        return (max(Int((Double(w0) * scale).rounded(.down)), 1), max(Int((Double(h0) * scale).rounded(.down)), 1))
    }
}
