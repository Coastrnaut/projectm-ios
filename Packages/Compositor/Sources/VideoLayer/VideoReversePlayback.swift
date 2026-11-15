// VideoReversePlayback.swift — the plain-Swift rules of cached reverse playback (MED-005-R2 to R5, R10;
// specs/284-med-005-video-reverse-playback, contracts/video-reverse.md; research MED-005-D1 to D4). Every platform
// (Linux too): no AVFoundation, Metal or locks here.
//
// * `VideoReverseLimits`: which clips can be reversed (≤ 30 s; upright ≤ 1920 × 1080) and the cache rate (≤ 30 pictures/s).
// * `VideoReverseUnsupported`: why not, with the user-facing sentence (the clip keeps playing forward).
// * `VideoReversePlan`: the eligibility check on the track facts, then the cached picture size and count. The budget
//   and the per-picture accounting are MED-008's (`AnimatedFrameBudget`): (pictures + 2 transient) × accounted bytes
//   must fit, and a picture is never larger than the clip's own.
// * `VideoReverseTimeline`: the shown picture as a pure function of video time (the MED-002 clock × MED-004 speed),
//   backwards over the MED-003 region [in, out), wrapping from in back to out.
// * `VideoReverseFrameStore`: strict accounting with a peak. Unlike `AnimatedFrameCache` it never evicts: reverse needs
//   every picture, so a picture that does not fit fails the build instead.
// * `VideoReverseDecoding` + `VideoReverseCacheBuilder`: decode the clip once (off the render path), keeping at most
//   30 pictures a second, and return the cache, the reason it is unsupported, or "cancelled".
import Foundation
import ImageLayer

/// Which clips can be reversed (MED-005-R2; spec Clarifications).
public struct VideoReverseLimits: Sendable, Equatable {
    public var maxDurationNanoseconds: Int64
    public var maxLongestSide: Int
    public var maxShortestSide: Int
    /// At most this many cached pictures per second of video.
    public var maxPicturesPerSecond: Int

    public init(maxDurationNanoseconds: Int64, maxLongestSide: Int, maxShortestSide: Int, maxPicturesPerSecond: Int) {
        self.maxDurationNanoseconds = max(maxDurationNanoseconds, 1)
        self.maxLongestSide = max(maxLongestSide, 1)
        self.maxShortestSide = max(maxShortestSide, 1)
        self.maxPicturesPerSecond = max(maxPicturesPerSecond, 1)
    }

    /// 30 s, 1080p (1920 × 1080 either way up), 30 pictures a second.
    public static let standard = VideoReverseLimits(maxDurationNanoseconds: 30_000_000_000, maxLongestSide: 1920,
                                                    maxShortestSide: 1080, maxPicturesPerSecond: 30)

    /// The shortest gap between two cached pictures: one picture interval at the cache rate less 1 ms, so a clip at
    /// exactly that rate (rounded timestamps) keeps every picture.
    public var minimumIntervalNanoseconds: Int64 {
        max(1_000_000_000 / Int64(maxPicturesPerSecond) - 1_000_000, 1)
    }
}

/// Why a clip is not reversed (MED-005-R5). It keeps playing forward.
public enum VideoReverseUnsupported: Error, Sendable, Equatable {
    case tooLong
    case tooLarge
    case undecodable

    /// The sentence shown under the Reverse switch (contracts/video-reverse.md C3).
    public var message: String {
        switch self {
        case .tooLong: "Reverse playback is available for clips up to 30 seconds. This video plays forward."
        case .tooLarge: "Reverse playback is available for clips up to 1080p. This video plays forward."
        case .undecodable: "This video can't be played in reverse. It plays forward."
        }
    }
}

/// Reverse playback of the video layer (data-model "VideoReverseState").
public enum VideoReverseState: Sendable, Equatable {
    case off
    /// The cache is being built; the clip plays forward meanwhile.
    case preparing
    /// The cache is ready; the clip plays backwards.
    case playing
    case unsupported(VideoReverseUnsupported)

    /// The DEBUG probe's word.
    public var probeName: String {
        switch self {
        case .off: "off"
        case .preparing: "preparing"
        case .playing: "playing"
        case .unsupported: "unsupported"
        }
    }
}

/// The cache of one clip: the size and count of its pictures (MED-005-R3; research MED-005-D3).
public struct VideoReversePlan: Sendable, Equatable {
    /// Transient pictures the build accounts for besides the cache (the picture being converted and its texture).
    public static let transientPictures = 2

    /// The cached picture size in the track's encoded orientation (the draw applies the rotation).
    public let pictureWidth: Int
    public let pictureHeight: Int
    /// The most pictures the cache may hold.
    public let maxPictures: Int
    /// `AnimatedFrameBudget.accountedFrameBytes` of one cached picture.
    public let accountedPictureBytes: Int
    public let minimumIntervalNanoseconds: Int64
    public let budgetBytes: Int

    /// Checks `info` against `limits` (duration, then size), then sizes the cache for `budgetBytes`.
    public init(info: VideoTrackInfo, limits: VideoReverseLimits = .standard, budgetBytes: Int) throws(VideoReverseUnsupported) {
        guard info.width > 0, info.height > 0, info.durationNanoseconds > 0 else { throw .undecodable }
        guard info.durationNanoseconds <= limits.maxDurationNanoseconds else { throw .tooLong }
        let longest: Int = max(info.uprightWidth, info.uprightHeight)
        let shortest: Int = min(info.uprightWidth, info.uprightHeight)
        guard longest <= limits.maxLongestSide, shortest <= limits.maxShortestSide else { throw .tooLarge }
        let interval: Int64 = limits.minimumIntervalNanoseconds
        let count: Int = Int(info.durationNanoseconds / interval) + 1
        let size = Self.pictureSize(width: info.width, height: info.height, pictures: count + Self.transientPictures,
                                    budget: budgetBytes)
        guard let size else { throw .tooLarge }
        pictureWidth = size.width
        pictureHeight = size.height
        maxPictures = count
        accountedPictureBytes = AnimatedFrameBudget.accountedFrameBytes(width: size.width, height: size.height)
        minimumIntervalNanoseconds = interval
        self.budgetBytes = budgetBytes
    }

    /// The largest size of `width` × `height`'s aspect, never larger, such that `pictures` accounted pictures fit
    /// `budget`; nil when not even 1 × 1 fits.
    static func pictureSize(width: Int, height: Int, pictures: Int, budget: Int) -> (width: Int, height: Int)? {
        let w0: Int = max(width, 1), h0: Int = max(height, 1)
        let n: Int = max(pictures, 1)
        let maxPixels: Double = Double(max(budget, 0)) / Double(n * 4)
        let scale: Double = min(1, (maxPixels / (Double(w0) * Double(h0))).squareRoot())
        var w: Int = max(Int((Double(w0) * scale).rounded(.down)), 1)
        var h: Int = max(Int((Double(h0) * scale).rounded(.down)), 1)
        while n * AnimatedFrameBudget.accountedFrameBytes(width: w, height: h) > budget {
            if w == 1, h == 1 { return nil }
            if w >= h {
                w = max(w - 1, 1)
                h = max(Int((Double(w) * Double(h0) / Double(w0)).rounded(.down)), 1)
            } else {
                h = max(h - 1, 1)
                w = max(Int((Double(h) * Double(w0) / Double(h0)).rounded(.down)), 1)
            }
        }
        return (w, h)
    }

    /// Bytes accounted while the whole cache and the transient pictures are resident.
    public var fullBytes: Int { (maxPictures + Self.transientPictures) * accountedPictureBytes }
}

/// The cached pictures' media times and the reverse selection rule (MED-005-R4; research MED-005-D4).
public struct VideoReverseTimeline: Sendable, Equatable {
    /// Media time of each cached picture, ascending.
    public let mediaNanoseconds: [Int64]
    public let durationNanoseconds: Int64

    public init(mediaNanoseconds: [Int64], durationNanoseconds: Int64) {
        self.mediaNanoseconds = mediaNanoseconds
        self.durationNanoseconds = max(durationNanoseconds, 1)
    }

    /// The picture shown `elapsed` nanoseconds of video time after reverse began at `startMedia` (nil, or outside
    /// the region: out; inside it, the top of the picture shown at `startMedia`, so that picture plays its full interval). With [a, b) the effective region and L = b − a: m = b − 1 − ((elapsed + b − 1 − s) mod L);
    /// the last picture at or before m, never one before the first picture at or after a.
    public func index(elapsedNanoseconds: Int64, region: VideoLoopRegion?, startMediaNanoseconds: Int64?) -> Int {
        guard !mediaNanoseconds.isEmpty else { return 0 }
        let r = VideoLoopRegion.effective(region, duration: durationNanoseconds)
        let a: Int64 = r.inNanoseconds, b: Int64 = r.outNanoseconds
        let length: Int64 = max(b - a, 1)
        // The start picture is shown for its whole interval: start at the top of it (the next picture's time − 1).
        var start: Int64 = b - 1
        if let s = startMediaNanoseconds, s >= a, s < b, let shown = lastIndex(atOrBefore: s) {
            let next: Int64 = shown + 1 < mediaNanoseconds.count ? mediaNanoseconds[shown + 1] : b
            start = min(next, b) - 1
        }
        let offset: Int64 = b - 1 - start
        let phase: Int64 = (max(elapsedNanoseconds, 0) % length + offset) % length
        let m: Int64 = b - 1 - phase
        let first: Int = firstIndex(atOrAfter: a)
        let last: Int = lastIndex(atOrBefore: m) ?? first
        return min(max(last, first), mediaNanoseconds.count - 1)
    }

    /// The last index whose time ≤ t (nil: none).
    func lastIndex(atOrBefore t: Int64) -> Int? {
        var low = 0, high = mediaNanoseconds.count - 1
        guard high >= 0, mediaNanoseconds[0] <= t else { return nil }
        while low < high {
            let mid: Int = (low + high + 1) / 2
            if mediaNanoseconds[mid] <= t { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The first index whose time ≥ t (the last index when none).
    func firstIndex(atOrAfter t: Int64) -> Int {
        var low = 0, high = mediaNanoseconds.count - 1
        while low < high {
            let mid: Int = (low + high) / 2
            if mediaNanoseconds[mid] >= t { high = mid } else { low = mid + 1 }
        }
        return low
    }
}

/// Every picture of one clip within a byte budget; never evicts (research MED-005-D3). Not thread-safe.
public struct VideoReverseFrameStore<Picture> {
    public let budgetBytes: Int
    public private(set) var residentBytes = 0
    public private(set) var reservedBytes = 0
    /// The most ever accounted (resident + reserved).
    public private(set) var peakBytes = 0
    public private(set) var pictures: [(media: Int64, picture: Picture)] = []

    public init(budgetBytes: Int) {
        self.budgetBytes = max(budgetBytes, 0)
    }

    public var accountedBytes: Int { residentBytes + reservedBytes }

    /// Reserves `bytes`; false (nothing reserved) when they do not fit.
    public mutating func reserve(_ bytes: Int) -> Bool {
        guard accountedBytes + bytes <= budgetBytes else { return false }
        reservedBytes += bytes
        peakBytes = max(peakBytes, accountedBytes)
        return true
    }

    /// Ends a reservation of `reserved` bytes and keeps `picture` (`bytes` ≤ `reserved`).
    public mutating func commit(media: Int64, picture: Picture, bytes: Int, reserved: Int) {
        reservedBytes = max(reservedBytes - reserved, 0)
        residentBytes += bytes
        pictures.append((media, picture))
        peakBytes = max(peakBytes, accountedBytes)
    }

    /// Ends a reservation without keeping anything.
    public mutating func cancel(reserved: Int) {
        reservedBytes = max(reservedBytes - reserved, 0)
    }
}

/// Reads one clip's pictures forward for the cache build (MED-005-R3). Used on the build's thread only.
public protocol VideoReverseDecoding: AnyObject {
    associatedtype Picture
    /// Opens the clip; its track facts.
    func open() throws(VideoReverseUnsupported) -> VideoTrackInfo
    /// The next picture in presentation order; `accept(pts)` false skips its conversion (picture nil). nil at the end.
    func next(width: Int, height: Int, accept: (Int64) -> Bool) throws(VideoReverseUnsupported) -> (pts: Int64, picture: Picture?)?
}

/// A built cache (immutable).
public struct VideoReverseCache<Picture> {
    public let info: VideoTrackInfo
    public let plan: VideoReversePlan
    public let timeline: VideoReverseTimeline
    public let pictures: [Picture]
    public let peakBytes: Int
}

public enum VideoReverseBuildOutcome<Picture> {
    case built(VideoReverseCache<Picture>)
    case unsupported(VideoReverseUnsupported)
    case cancelled
}

public enum VideoReverseCacheBuilder {
    /// Decodes `decoder`'s clip once into a cache planned for `budgetBytes` (MED-005-R2, R3). `isCancelled` is asked
    /// before every picture.
    public static func build<D: VideoReverseDecoding>(_ decoder: D, limits: VideoReverseLimits = .standard, budgetBytes: Int,
                                                      isCancelled: () -> Bool) -> VideoReverseBuildOutcome<D.Picture> {
        let info: VideoTrackInfo
        let plan: VideoReversePlan
        do throws(VideoReverseUnsupported) {
            info = try decoder.open()
            plan = try VideoReversePlan(info: info, limits: limits, budgetBytes: budgetBytes)
        } catch {
            return .unsupported(error)
        }
        var store = VideoReverseFrameStore<D.Picture>(budgetBytes: budgetBytes)
        let transient: Int = VideoReversePlan.transientPictures * plan.accountedPictureBytes
        guard store.reserve(transient) else { return .unsupported(.tooLarge) }
        var lastKept: Int64?
        let interval: Int64 = plan.minimumIntervalNanoseconds
        let accept: (Int64) -> Bool = { (pts: Int64) -> Bool in
            guard pts >= 0, pts <= info.durationNanoseconds else { return false }
            guard let previous = lastKept else { return true }
            return pts - previous >= interval
        }
        while store.pictures.count < plan.maxPictures {
            if isCancelled() { return .cancelled }
            let read: (pts: Int64, picture: D.Picture?)?
            do throws(VideoReverseUnsupported) {
                read = try decoder.next(width: plan.pictureWidth, height: plan.pictureHeight, accept: accept)
            } catch {
                return .unsupported(error)
            }
            guard let read else { break }
            guard let picture = read.picture else { continue }
            guard store.reserve(plan.accountedPictureBytes) else { return .unsupported(.tooLarge) }
            store.commit(media: read.pts, picture: picture, bytes: plan.accountedPictureBytes, reserved: plan.accountedPictureBytes)
            lastKept = read.pts
        }
        if isCancelled() { return .cancelled }
        store.cancel(reserved: transient)
        guard !store.pictures.isEmpty else { return .unsupported(.undecodable) }
        let sorted = store.pictures.sorted { (l: (media: Int64, picture: D.Picture), r: (media: Int64, picture: D.Picture)) -> Bool in
            l.media < r.media
        }
        let media: [Int64] = sorted.map(\.media)
        // A track whose duration stops at its last picture's start still shows that picture.
        let duration: Int64 = max(info.durationNanoseconds, (media.last ?? 0) + plan.minimumIntervalNanoseconds)
        let timeline = VideoReverseTimeline(mediaNanoseconds: media, durationNanoseconds: duration)
        let pictures: [D.Picture] = sorted.map(\.picture)
        return .built(VideoReverseCache(info: info, plan: plan, timeline: timeline, pictures: pictures, peakBytes: store.peakBytes))
    }
}
