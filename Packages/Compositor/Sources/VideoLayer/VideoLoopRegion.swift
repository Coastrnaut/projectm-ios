// VideoLoopRegion.swift — the in and out points a video layer repeats (MED-003-R1, R2; research
// MED-003-D1). Plain Swift, every platform; integer nanoseconds inside the player, integer
// milliseconds where the region is stored (settings, scenes).
//
// A region is [in, out) on the video's own timeline: the pictures whose time t satisfies
// in ≤ t < out are shown, then playback starts again at in. `effective(duration:)` clamps a saved
// region to an opened video: negative points to 0, out to the duration, at least
// `minimumLengthNanoseconds` long (out moves forward, or in moves back at the end); a video shorter
// than the minimum plays whole. No region at all is the whole file (MED-002's loop).

public struct VideoLoopRegion: Sendable, Equatable, Hashable {
    /// The shortest region (0.25 s).
    public static let minimumLengthNanoseconds: Int64 = 250_000_000
    private static let nanosecondsPerMillisecond: Int64 = 1_000_000

    public let inNanoseconds: Int64
    public let outNanoseconds: Int64

    /// Stored as given; `effective(duration:)` applies the rules.
    public init(inNanoseconds: Int64, outNanoseconds: Int64) {
        self.inNanoseconds = inNanoseconds
        self.outNanoseconds = outNanoseconds
    }

    public init(inMilliseconds: Int, outMilliseconds: Int) {
        let inNs: Int64 = Int64(inMilliseconds) * Self.nanosecondsPerMillisecond
        let outNs: Int64 = Int64(outMilliseconds) * Self.nanosecondsPerMillisecond
        self.init(inNanoseconds: inNs, outNanoseconds: outNs)
    }

    /// The whole file of `duration` nanoseconds.
    public static func whole(duration: Int64) -> VideoLoopRegion {
        VideoLoopRegion(inNanoseconds: 0, outNanoseconds: max(duration, 1))
    }

    public var inMilliseconds: Int { Int(inNanoseconds / Self.nanosecondsPerMillisecond) }
    public var outMilliseconds: Int { Int(outNanoseconds / Self.nanosecondsPerMillisecond) }
    public var length: Int64 { outNanoseconds - inNanoseconds }

    /// in ≤ t < out.
    public func contains(_ nanoseconds: Int64) -> Bool {
        nanoseconds >= inNanoseconds && nanoseconds < outNanoseconds
    }

    /// True when the region covers the whole of a `duration`-long video.
    public func isWholeFile(duration: Int64) -> Bool {
        let e = effective(duration: duration)
        return e.inNanoseconds == 0 && e.outNanoseconds >= duration
    }

    /// The region clamped to a video of `duration` nanoseconds (research MED-003-D1).
    public func effective(duration: Int64) -> VideoLoopRegion {
        guard duration > 0 else { return VideoLoopRegion.whole(duration: 1) }
        let minimum: Int64 = Self.minimumLengthNanoseconds
        guard duration > minimum else { return VideoLoopRegion.whole(duration: duration) }
        var start: Int64 = min(max(inNanoseconds, 0), duration)
        var end: Int64 = min(max(outNanoseconds, 0), duration)
        if end - start < minimum {
            end = start + minimum
            if end > duration {
                end = duration
                start = duration - minimum
            }
        }
        return VideoLoopRegion(inNanoseconds: start, outNanoseconds: end)
    }

    /// `region` clamped to `duration`, or the whole file when there is none.
    public static func effective(_ region: VideoLoopRegion?, duration: Int64) -> VideoLoopRegion {
        region?.effective(duration: duration) ?? whole(duration: duration)
    }
}
