// OfflinePCMSource.swift — REC-013 the export's audio as the analysis reads it (research REC-013-D2). Builds on Linux.
//
// An in-memory, interleaved stereo Float32 buffer at 44.1 kHz behind `NormalizedPCMReader`. Reads return the frames
// between the read position and the readable end, which the export moves forward to the current frame's sample
// position (`expose(upTo:)`), so the analysis sees exactly the audio before that frame and never any later audio.
// One thread drives it (the export's task, through the pipeline's synchronous `step`).
import AudioCore

public final class OfflinePCMSource: NormalizedPCMReader, @unchecked Sendable {
    private let samples: [Float]
    /// Stereo frames in the buffer.
    public let frameCount: Int
    private var readPosition = 0
    private var readableEnd = 0

    /// `interleaved`: L, R, L, R… (an odd trailing sample is ignored).
    public init(interleaved: [Float]) {
        samples = interleaved
        frameCount = interleaved.count / NormalizedPCMRing.channelCount
    }

    /// Lets reads reach frame `frame` (exclusive), clamped to the buffer; never moves backwards.
    public func expose(upTo frame: Int) {
        readableEnd = max(readableEnd, min(max(frame, 0), frameCount))
    }

    /// Frames read so far.
    public var position: Int { readPosition }

    public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let n = min(max(maxFrames, 0), readableEnd - readPosition)
        guard n > 0 else { return 0 }
        let channels = NormalizedPCMRing.channelCount
        samples.withUnsafeBufferPointer { (all: UnsafeBufferPointer<Float>) -> Void in
            dst.update(from: all.baseAddress! + readPosition * channels, count: n * channels)
        }
        readPosition += n
        return n
    }
}
