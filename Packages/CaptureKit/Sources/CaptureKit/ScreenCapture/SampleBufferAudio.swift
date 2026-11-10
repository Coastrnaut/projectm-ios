// SampleBufferAudio.swift — copies the linear PCM audio of a CMSampleBuffer into a PCMSink
// (task T037). The ScreenCaptureKit audio output (SCKStreamDriver.swift) calls this from its
// sample-handler queue. This file uses only CoreMedia, CoreAudioTypes, AudioCore and
// Synchronization (never ScreenCaptureKit), so it compiles on macOS and iOS (device and
// simulator) and the host tests cover it (SampleBufferAudioTests).
//
// Real-time path (Constitution VII): `write(_:)` does not allocate, lock, log, or call async
// code. The AudioBufferList storage is preallocated once. Two CoreMedia rules apply:
//   * CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer accepts only the exact list size it
//     reports through `bufferListSizeNeededOut` (CMSampleBuffer.h: bufferListOut is "sized as
//     specified by bufferListSizeNeededOut"); any other size, larger or smaller, fails with
//     kCMSampleBufferError_ArrayTooSmall. So the size is queried first, then passed exactly.
//   * flags are 0. kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment makes CoreMedia
//     allocate and copy a new block buffer whenever a plane is not 16-byte aligned; PCMSink needs
//     only 2- or 4-byte alignment.
#if canImport(CoreMedia) && canImport(CoreAudioTypes)
import AudioCore
import CoreAudioTypes
import CoreMedia
import Synchronization

/// What one `SampleBufferAudioWriter.write(_:)` call did. No case allocates.
enum SampleBufferAudioOutcome: Equatable, Sendable {
    /// `frames` frames were written to the sink.
    case written(frames: Int)
    /// `stop()` was called; the buffer was ignored and the sink was not touched.
    case stopped
    /// The sample buffer is invalid, has no audio format description, or is not linear PCM
    /// (float32, int16 or int32).
    case unsupportedFormat
    /// The sample buffer holds no frames.
    case noFrames
    /// CoreMedia could not report the AudioBufferList size.
    case sizeQueryFailed(OSStatus)
    /// The AudioBufferList needs more bytes than the preallocated storage holds.
    case listTooLarge(needed: Int)
    /// CoreMedia could not fill the AudioBufferList.
    case bufferListFailed(OSStatus)
    /// A buffer has no data or fewer bytes than the frame count implies.
    case bufferTooShort
}

/// Copies sample-buffer audio into one PCMSink. One producer at a time (the sample-handler
/// queue); `stop()` may be called from any thread.
final class SampleBufferAudioWriter: @unchecked Sendable {
    /// Buffers the preallocated AudioBufferList can describe. PCMSink keeps the first
    /// `PCMSink.maxChannels` channels, so larger planar layouts still deliver audio.
    static let maxBuffers = 64
    /// Byte size of the preallocated AudioBufferList (the largest list this writer accepts).
    static let maxListSize =
        MemoryLayout<AudioBufferList>.size + (maxBuffers - 1) * MemoryLayout<AudioBuffer>.size

    private let sink: PCMSink
    private let listStorage: UnsafeMutableRawPointer
    private let stoppedFlag = Atomic<Bool>(false)
    private let rejected = Atomic<Int>(0)

    init(sink: PCMSink) {
        self.sink = sink
        listStorage = UnsafeMutableRawPointer.allocate(byteCount: Self.maxListSize, alignment: 16)
        listStorage.initializeMemory(as: UInt8.self, repeating: 0, count: Self.maxListSize)
    }

    deinit { listStorage.deallocate() }

    /// After this returns, every later `write(_:)` returns `.stopped` without touching the sink.
    /// A `write(_:)` already running may still finish; the caller waits for it by draining the
    /// queue that calls `write(_:)` (SCKStreamDriver.stop).
    func stop() { stoppedFlag.store(true, ordering: .releasing) }

    var isStopped: Bool { stoppedFlag.load(ordering: .acquiring) }

    /// Buffers that arrived but were not written (every outcome except `.written` and
    /// `.stopped`). Not part of the diagnostics export; for tests and debugging.
    var rejectedCount: Int { rejected.load(ordering: .relaxed) }

    /// Real-time safe: no allocation, no locks, no logging.
    @discardableResult
    func write(_ sampleBuffer: CMSampleBuffer) -> SampleBufferAudioOutcome {
        guard !isStopped else { return .stopped }
        let outcome = copy(sampleBuffer)
        if case .written = outcome {} else { _ = rejected.add(1, ordering: .relaxed) }
        return outcome
    }

    private func copy(_ sampleBuffer: CMSampleBuffer) -> SampleBufferAudioOutcome {
        guard CMSampleBufferIsValid(sampleBuffer),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              let format = AudioFormat(asbd: asbd) else { return .unsupportedFormat }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return .noFrames }

        // 1. Ask for the exact list size (no list, no block buffer: nothing is allocated).
        var needed = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard sizeStatus == noErr else { return .sizeQueryFailed(sizeStatus) }
        guard needed >= MemoryLayout<AudioBufferList>.size, needed <= Self.maxListSize else {
            return .listTooLarge(needed: needed)
        }

        // 2. Fill the preallocated list, passing exactly that size. When the sample buffer's data is
        //    contiguous (as in the host tests), the retained block buffer is the sample buffer's own
        //    (flags 0: no aligned copy); otherwise CoreMedia builds a contiguous one, which
        //    allocates (T050 measures this on device). It keeps the data alive until the sink has
        //    copied it.
        let list = listStorage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == noErr else { return .bufferListFailed(status) }

        let outcome: SampleBufferAudioOutcome
        if Self.buffersHold(frames: frames, format: format, list: UnsafePointer(list)) {
            // The layout tag lets the Normalizer downmix more than 2 channels (R-05); a CoreMedia
            // getter that returns a pointer into the format description, so nothing is allocated.
            let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: nil)?.pointee.mChannelLayoutTag ?? 0
            sink.write(UnsafePointer(list), format: format, frameCount: frames,
                       layout: ChannelLayoutTag(rawValue: layout))
            outcome = .written(frames: frames)
        } else {
            outcome = .bufferTooShort
        }
        withExtendedLifetime(blockBuffer) {}
        return outcome
    }

    /// Whether every buffer PCMSink will read holds at least `frames` frames, using the same
    /// interleaved/planar rule as `PCMSink.write(_:format:frameCount:)`. Guards against reading
    /// past the end of a buffer if a sample count and its data ever disagree.
    private static func buffersHold(frames: Int, format: AudioFormat,
                                    list: UnsafePointer<AudioBufferList>) -> Bool {
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0,
              let offset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers) else { return false }
        let buffers = UnsafeRawPointer(list).advanced(by: offset).assumingMemoryBound(to: AudioBuffer.self)
        let bytesPerSample = format.sampleType == .int16 ? 2 : 4
        if format.isInterleaved || count == 1 {
            let (samples, o1) = frames.multipliedReportingOverflow(by: format.channelCount)
            let (bytes, o2) = samples.multipliedReportingOverflow(by: bytesPerSample)
            guard !o1, !o2, buffers[0].mData != nil else { return false }
            return Int(buffers[0].mDataByteSize) >= bytes
        }
        let (bytes, overflow) = frames.multipliedReportingOverflow(by: bytesPerSample)
        guard !overflow else { return false }
        // Index `while`, not `for i in 0..<n`: at -Onone (Debug, the Run configuration used for
        // device runs) Range iteration heap-allocates on every step (see PCMSink.swift).
        let planes = min(count, PCMSink.maxChannels)
        var i = 0
        while i < planes {
            guard buffers[i].mData != nil, Int(buffers[i].mDataByteSize) >= bytes else { return false }
            i += 1
        }
        return true
    }
}
#endif
