// PCMSink+AudioBufferList.swift — Core Audio adapter for PCMSink (Apple platforms only).
// Uses only CoreAudioTypes (the C structs); walks the variable-length buffer array by offset so it
// needs no CoreAudio Swift overlay and never allocates.
#if canImport(CoreAudioTypes)
import CoreAudioTypes

extension PCMSink {
    /// Byte offset of `AudioBufferList.mBuffers`. `mBuffers` is the last field (a one-element
    /// array), so it starts one `AudioBuffer` before the end of the struct. Computed without a key
    /// path: `MemoryLayout.offset(of: \.mBuffers)` creates a KeyPath object at run time in Debug
    /// builds, which heap-allocated on the first audio callback (T063 trace on D1, 2026-11-09).
    /// `PCMSinkAudioBufferListTests` checks it equals the key-path offset.
    @inline(__always)
    public static var audioBuffersOffset: Int {
        MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.stride
    }

    /// Real-time-safe write from an `AudioBufferList` (contracts/audio-source.md §PCMSink).
    /// Uses the sink's preallocated plane scratch, so this path never allocates. Single producer.
    public func write(_ list: UnsafePointer<AudioBufferList>, format: AudioFormat, frameCount: Int,
                      layout: ChannelLayoutTag = .unknown, captureTimeNs: UInt64 = 0,
                      hostTimeNs: UInt64 = MonotonicClock.nowNanoseconds()) {
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, frameCount > 0 else { return }
        let offset = PCMSink.audioBuffersOffset
        let buffers = UnsafeRawPointer(list).advanced(by: offset).assumingMemoryBound(to: AudioBuffer.self)
        if format.isInterleaved || count == 1 {
            guard let data = buffers[0].mData else { return }
            var f = format
            f.isInterleaved = true
            writeInterleaved(UnsafeRawPointer(data), frames: frameCount, format: f, layout: layout, captureTimeNs: captureTimeNs, hostTimeNs: hostTimeNs)
        } else {
            let planes = min(count, PCMSink.maxChannels)
            // An index loop, not `for in 0..<planes`: Range iteration heap-allocates at -Onone
            // (Debug), see PCMSink.swift.
            var i = 0
            while i < planes {
                planeScratch[i] = buffers[i].mData.map { UnsafeRawPointer($0) }
                i += 1
            }
            writePlanar(UnsafePointer(planeScratch), planeCount: planes, frames: frameCount,
                        format: format, layout: layout, captureTimeNs: captureTimeNs, hostTimeNs: hostTimeNs)
        }
    }
}
#endif
