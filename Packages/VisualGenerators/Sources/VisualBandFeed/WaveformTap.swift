// WaveformTap.swift — the oscilloscope's sample path (VIS-003-R2, R15; research VIS-003-D1; contract C3).
//
// The analysis tap has exactly one consumer (the native host's `LiveBandAnalyzer`). The host hands the
// analyzer this pass-through reader instead: every read is forwarded to the wrapped tap and returned
// unchanged, so the ANL-016 pipeline and its bands are untouched; then, on the same thread (the
// analysis worker), the frames read are mixed to mono ((L + R)/2, the pipeline's `.mid` mode) into a
// fixed 4,096-sample rolling history (newest last), which is published through `WaveformFrameBuffer`.
// The capture session generation (ANL-016-R9) is forwarded; a wrapped reader that reports none reads
// as 0, which the pipeline treats exactly as before (never changes).
//
// Real-time safety (Constitution VII): the history is allocated in `init`; a read does one mono mix,
// one move of at most 16 KB and one atomic exchange. It never runs on an audio callback. Only the
// reading thread touches the history (hence `@unchecked Sendable`). Nothing reaches projectM
// (Constitution VIII).
import AudioCore
import VisualGenerators

public final class WaveformTap: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    /// The newest history, for the frame loop.
    public let output = WaveformFrameBuffer()
    private let reader: any NormalizedPCMReader
    private let history: UnsafeMutablePointer<Float>
    private var total: UInt64 = 0   // reader-thread-owned

    public init(_ reader: any NormalizedPCMReader) {
        self.reader = reader
        history = .allocate(capacity: WaveformFrameBuffer.capacity)
        history.initialize(repeating: 0, count: WaveformFrameBuffer.capacity)
    }

    deinit {
        history.deinitialize(count: WaveformFrameBuffer.capacity)
        history.deallocate()
    }

    public var analysisSessionGeneration: UInt64 {
        (reader as? any AnalysisSessionReporting)?.analysisSessionGeneration ?? 0
    }

    public func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let frames = reader.read(into: dst, maxFrames: maxFrames)
        guard frames > 0 else { return frames }
        let n = WaveformFrameBuffer.capacity
        let channels = NormalizedPCMRing.channelCount
        let kept = min(frames, n)
        if kept < n { history.update(from: history + kept, count: n - kept) }   // memmove: regions overlap
        let target = history + (n - kept)
        let first = frames - kept
        for i in 0..<kept {
            let frame = (first + i) * channels
            target[i] = (dst[frame] + dst[frame + 1]) * 0.5
        }
        total &+= UInt64(frames)
        output.write(UnsafeBufferPointer(start: history, count: n), totalWritten: total)
        return frames
    }
}
