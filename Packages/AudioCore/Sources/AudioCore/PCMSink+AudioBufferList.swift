// PCMSink+AudioBufferList.swift — Core Audio adapter for PCMSink (Apple platforms only).
#if canImport(CoreAudioTypes)
import CoreAudioTypes

extension PCMSink {
    /// Real-time-safe write from an `AudioBufferList` (contracts/audio-source.md §PCMSink).
    /// Uses the sink's preallocated plane scratch, so this path never allocates. Single producer.
    public func write(_ list: UnsafePointer<AudioBufferList>, format: AudioFormat, frameCount: Int,
                      hostTimeNs: UInt64 = MonotonicClock.nowNanoseconds()) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard buffers.count > 0, frameCount > 0 else { return }
        if format.isInterleaved || buffers.count == 1 {
            guard let data = buffers[0].mData else { return }
            var f = format
            f.isInterleaved = true
            writeInterleaved(UnsafeRawPointer(data), frames: frameCount, format: f, hostTimeNs: hostTimeNs)
        } else {
            let planes = min(buffers.count, PCMSink.maxChannels)
            for i in 0..<planes {
                planeScratch[i] = buffers[i].mData.map { UnsafeRawPointer($0) }
            }
            writePlanar(UnsafePointer(planeScratch), planeCount: planes, frames: frameCount,
                        format: format, hostTimeNs: hostTimeNs)
        }
    }
}
#endif
