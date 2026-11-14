// VideoPlaybackSpeed.swift — the video layer's playback speed (MED-004-R1, R5; research MED-004-D2,
// D3; contracts/video-speed.md C1). Plain Swift, every platform.
//
// A speed is an integer percentage from a fixed safe set (0.25× to 2×); nothing else can be built, so
// a stored or scene value outside the set reads as 1× wherever it is converted. Integer percent keeps
// the clock's scaling exact (no drift). Speed changes only the video's own time: the app's audio
// source never sees it (the VideoLayer module imports no audio or capture module).

public struct VideoPlaybackSpeed: Sendable, Equatable, Hashable, Comparable {
    /// The percentages offered, ascending.
    public static let allowedPercents: [Int] = [25, 50, 75, 100, 125, 150, 200]
    /// MED-003's pre-roll lead at 1× (video time).
    public static let basePrerollNanoseconds: Int64 = 500_000_000

    public let percent: Int

    /// nil unless `percent` is one of `allowedPercents`.
    public init?(percent: Int) {
        guard Self.allowedPercents.contains(percent) else { return nil }
        self.percent = percent
    }

    private init(validated percent: Int) { self.percent = percent }

    /// 1×.
    public static let normal = VideoPlaybackSpeed(validated: 100)

    /// Every speed, slowest first.
    public static let all: [VideoPlaybackSpeed] = allowedPercents.map { (p: Int) -> VideoPlaybackSpeed in
        VideoPlaybackSpeed(validated: p)
    }

    public var isNormal: Bool { percent == 100 }

    /// The pre-roll lead in video time: 0.5 s at or below 1×, 0.5 s × the speed above it, so the next
    /// loop pass is prepared at least 0.5 s of wall time before out (research MED-004-D3).
    public var prerollLeadNanoseconds: Int64 {
        let factor: Int64 = Int64(max(percent, 100))
        return Self.basePrerollNanoseconds * factor / 100
    }

    public static func < (lhs: VideoPlaybackSpeed, rhs: VideoPlaybackSpeed) -> Bool { lhs.percent < rhs.percent }
}
