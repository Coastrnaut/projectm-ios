// RecordingAudioTimeline.swift — REC-004 placing host-timed audio in the file (REC-004-R5, R6; research
// REC-004-D3). Plain Swift; builds on Linux.
//
// Positions are samples at 44.1 kHz from the first video frame (the origin, on the same uptime clock as
// the frames). Per chunk, in order:
//   1. ended, or no origin yet → nothing is placed;
//   2. its position = round((first sample's time − origin) × 44,100 / 1e9);
//   3. within ±100 ms of where the last chunk ended → placed right after it (contiguous: stamp jitter
//      never makes clicks);
//   4. earlier than that beyond the window → the overlap is trimmed (never written twice);
//      later beyond the window → placed at its own time (a gap, never padded with silence);
//   5. anything before the origin is trimmed.
// Not thread-safe: the caller serializes.

public struct RecordingAudioTimeline: Sendable, Equatable {
    /// Where a chunk goes: skip `skipFrames` at its start, write `frames` from `startSample`.
    public struct Placement: Sendable, Equatable {
        public let skipFrames: Int
        public let startSample: Int64
        public let frames: Int
    }

    public static let sampleRate = 44_100
    /// ±100 ms: closer than this to the expected position counts as contiguous.
    public static let contiguityWindowSamples: Int64 = 4_410
    /// REC-004-R6: a sound and the frame stamped at the same host time are at most this far apart in the file.
    public static let toleranceSeconds = 0.020

    public private(set) var originNanoseconds: UInt64?
    /// The position after the last placed sample (nil before the first).
    public private(set) var nextSample: Int64?
    public private(set) var ended = false
    /// Samples placed so far.
    public private(set) var placedFrames = 0

    public init() {}

    /// Sets the origin once (the first video frame's time); later calls are ignored.
    public mutating func setOrigin(nanoseconds: UInt64) {
        if originNanoseconds == nil { originNanoseconds = nanoseconds }
    }

    /// No audio is placed after this (REC-004-R5).
    public mutating func end() { ended = true }

    /// The sample position of a host time (negative before the origin; 0 without an origin).
    public func position(forNanoseconds ns: UInt64) -> Int64 {
        guard let origin = originNanoseconds else { return 0 }
        let delta = ns >= origin ? Double(ns - origin) : -Double(origin - ns)
        return Int64((delta * Double(Self.sampleRate) / 1e9).rounded())
    }

    public mutating func place(frames: Int, firstSampleNanoseconds ns: UInt64) -> Placement? {
        guard !ended, originNanoseconds != nil, frames > 0 else { return nil }
        var start = position(forNanoseconds: ns)
        var skip: Int64 = 0
        if let next = nextSample {
            if abs(start - next) <= Self.contiguityWindowSamples {
                start = next
            } else if start < next {
                skip = next - start
                start = next
            }
        }
        if start < 0 {
            skip += -start
            start = 0
        }
        let remaining = Int64(frames) - skip
        guard remaining > 0 else { return nil }
        nextSample = start + remaining
        placedFrames += Int(remaining)
        return Placement(skipFrames: Int(skip), startSample: start, frames: Int(remaining))
    }
}
