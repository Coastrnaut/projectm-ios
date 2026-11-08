// PCMSink+AudioBufferList.swift — Core Audio adapter for PCMSink (Apple platforms only).
// Uses only CoreAudioTypes (the C structs); walks the variable-length buffer array by offset so it
// needs no CoreAudio Swift overlay and never allocates.
#if canImport(CoreAudioTypes)
import CoreAudioTypes

extension PCMSink {
    /// Real-time-safe write from an `AudioBufferList` (contracts/audio-source.md §PCMSink).
    /// Uses the sink's preallocated plane scratch, so this path never allocates. Single producer.
    public func write(_ list: UnsafePointer<AudioBufferList>, format: AudioFormat, frameCount: Int,
                      hostTimeNs: UInt64 = MonotonicClock.nowNanoseconds()) {
        let count = Int(list.pointee.mNumberBuffers)
        guard count > 0, frameCount > 0,
              let offset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers) else { return }
        let buffers = UnsafeRawPointer(list).advanced(by: offset).assumingMemoryBound(to: AudioBuffer.self)
        if format.isInterleaved || count == 1 {
            guard let data = buffers[0].mData else { return }
            var f = format
            f.isInterleaved = true
            writeInterleaved(UnsafeRawPointer(data), frames: frameCount, format: f, hostTimeNs: hostTimeNs)
        } else {
            let planes = min(count, PCMSink.maxChannels)
            for i in 0..<planes {
                planeScratch[i] = buffers[i].mData.map { UnsafeRawPointer($0) }
            }
            writePlanar(UnsafePointer(planeScratch), planeCount: planes, frames: frameCount,
                        format: format, hostTimeNs: hostTimeNs)
        }
    }
}
#endif
