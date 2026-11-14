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
// VIS-004 (contract C1; research VIS-004-D1): the same read also keeps the newest 2,048 frames
// interleaved (L, R; oldest first) for the Lissajous scope, published through a second triple buffer
// (`stereoOutput`). The forwarded frames and the mono history are unchanged.
//
// Real-time safety (Constitution VII): both histories are allocated in `init`; a read does one mono
// mix, two moves of at most 16 KB each and two atomic exchanges. It never runs on an audio callback. Only the
// reading thread touches the history (hence `@unchecked Sendable`). Nothing reaches projectM
// (Constitution VIII).
import AudioCore
import VisualGenerators

public final class WaveformTap: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    /// The newest history, for the frame loop.
    public let output = WaveformFrameBuffer()
    /// VIS-004: the newest stereo history (interleaved L, R; oldest first), for the Lissajous scope.
    public let stereoOutput = WaveformFrameBuffer()
    /// Frames the stereo history holds (2,048 ≈ 46 ms).
    public static let stereoFrames = WaveformFrameBuffer.capacity / NormalizedPCMRing.channelCount
    private let reader: any NormalizedPCMReader
    private let history: UnsafeMutablePointer<Float>
    private let stereo: UnsafeMutablePointer<Float>
    private var total: UInt64 = 0   // reader-thread-owned

    public init(_ reader: any NormalizedPCMReader) {
        self.reader = reader
        history = .allocate(capacity: WaveformFrameBuffer.capacity)
        history.initialize(repeating: 0, count: WaveformFrameBuffer.capacity)
        stereo = .allocate(capacity: WaveformFrameBuffer.capacity)
        stereo.initialize(repeating: 0, count: WaveformFrameBuffer.capacity)
    }

    deinit {
        history.deinitialize(count: WaveformFrameBuffer.capacity)
        history.deallocate()
        stereo.deinitialize(count: WaveformFrameBuffer.capacity)
        stereo.deallocate()
    }

    // Storage introspection for the allocation tests (VIS-004-R17).
    var storageAddresses: [UInt] { [UInt(bitPattern: history), UInt(bitPattern: stereo)] }

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
        keepStereo(dst, frames: frames)
        return frames
    }

    /// VIS-004: rolls the newest frames of `dst` into the stereo history and publishes it.
    private func keepStereo(_ dst: UnsafeMutablePointer<Float>, frames: Int) {
        let n = WaveformFrameBuffer.capacity
        let channels = NormalizedPCMRing.channelCount
        let keptFrames = min(frames, Self.stereoFrames)
        let kept = keptFrames * channels
        if kept < n { stereo.update(from: stereo + kept, count: n - kept) }   // memmove: regions overlap
        let first = (frames - keptFrames) * channels
        (stereo + (n - kept)).update(from: dst + first, count: kept)   // the ring is stereo (channelCount 2)
        stereoOutput.write(UnsafeBufferPointer(start: stereo, count: n), totalWritten: total)
    }
}
