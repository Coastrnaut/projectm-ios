// AuthoringPreviewFixture.swift — the preview's deterministic sample audio and clock (SHD-012-R1; research
// SHD-012-D1; data-model.md "AuthoringPreviewFixture"). Plain Swift; builds on Linux.
//
// REC-013's seeded fixture music (`OfflineFixtureAudio`: a 120 BPM kick, a chord and seeded noise hits) for
// `seconds`, paced by REC-013's `OfflineFrameClock` at `fps`. Nothing here reads live audio or a real clock: the same
// seed, length and rate always give the same samples and the same frame times.
import VisualBandFeed

public struct AuthoringPreviewFixture: Sendable, Equatable, Hashable {
    public static let defaultSeed: UInt64 = 1
    public static let defaultSeconds = 4.0
    public static let defaultFPS = 30
    /// The seeds the editor offers.
    public static let editorSeeds: ClosedRange<Int> = 1...99

    public var seed: UInt64
    /// Length of the fixture audio (> 0).
    public var seconds: Double
    /// Frames per second (> 0).
    public var fps: Int

    public init(seed: UInt64 = defaultSeed, seconds: Double = defaultSeconds, fps: Int = defaultFPS) {
        precondition(seconds.isFinite && seconds > 0, "fixture length")
        precondition(fps > 0, "frame rate")
        self.seed = seed
        self.seconds = seconds
        self.fps = fps
    }

    public var clock: OfflineFrameClock { OfflineFrameClock(fps: fps) }

    /// Stereo frames of fixture audio (as `OfflineFixtureAudio` rounds them).
    public var sampleFrames: Int { Int((seconds * Double(OfflineFrameClock.sampleRate)).rounded()) }

    /// Frames of a full run (120 for the defaults).
    public var frameCount: Int { clock.frameCount(samples: sampleFrames) }

    /// The fixture audio, interleaved stereo at 44.1 kHz.
    public func audio() -> [Float] { OfflineFixtureAudio.samples(seed: seed, seconds: seconds) }
}
