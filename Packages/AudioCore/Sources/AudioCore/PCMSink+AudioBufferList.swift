// PCMSink+AudioBufferList.swift — Core Audio adapter for PCMSink (Apple platforms only).
#if canImport(CoreAudioTypes)
import CoreAudioTypes

extension PCMSink {
    /// Real-time-safe write from an `AudioBufferList` (contracts/audio-source.md §PCMSink).
    /// `planeScratch` must hold at least `PCMSink.maxChannels` entries and is owned by the caller
    /// (each source preallocates one), so this path never allocates.
    public func write(_ list: UnsafePointer<AudioBufferList>, format: AudioFormat, frameCount: Int,
                      hostTimeNs: UInt64, planeScratch: UnsafeMutablePointer<UnsafeRawPointer?>) {
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

    /// Allocates a plane-pointer scratch array for `write(_:format:frameCount:hostTimeNs:planeScratch:)`.
    /// Call once at source setup, never in a callback.
    public static func makePlaneScratch() -> UnsafeMutablePointer<UnsafeRawPointer?> {
        let p = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: maxChannels)
        p.initialize(repeating: nil, count: maxChannels)
        return p
    }
}
#endif
