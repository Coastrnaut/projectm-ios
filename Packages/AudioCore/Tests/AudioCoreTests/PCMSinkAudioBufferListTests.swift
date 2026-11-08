// Apple-only: PCMSink.write(_ AudioBufferList…) for interleaved and planar (multi-buffer) lists.
#if canImport(CoreAudioTypes)
import XCTest
import CoreAudioTypes
@testable import AudioCore

final class PCMSinkAudioBufferListTests: XCTestCase {
    private func drain(_ sink: PCMSink) -> [Float] {
        var out = [Float](repeating: 0, count: 64)
        let n = out.withUnsafeMutableBufferPointer { sink.ring.read(into: $0.baseAddress!, maxCount: $0.count) }
        return Array(out.prefix(n))
    }

    func testInterleavedSingleBuffer() {
        let sink = PCMSink()
        var samples: [Float] = [0.1, -0.1, 0.2, -0.2]
        samples.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
            withUnsafePointer(to: &list) { sink.write($0, format: format, frameCount: 2, hostTimeNs: 1) }
        }
        XCTAssertEqual(drain(sink), [0.1, -0.1, 0.2, -0.2])
    }

    func testPlanarTwoBuffers() {
        let sink = PCMSink()
        var left: [Float] = [1, 2, 3]
        var right: [Float] = [-1, -2, -3]
        let byteCount = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        defer { raw.deallocate() }
        left.withUnsafeMutableBytes { l in
            right.withUnsafeMutableBytes { r in
                let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
                list.pointee.mNumberBuffers = 2
                let offset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers)!
                let buffers = (raw + offset).bindMemory(to: AudioBuffer.self, capacity: 2)
                buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(l.count), mData: l.baseAddress)
                buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(r.count), mData: r.baseAddress)
                let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: false, sampleType: .float32)
                sink.write(UnsafePointer(list), format: format, frameCount: 3, hostTimeNs: 1)
            }
        }
        XCTAssertEqual(drain(sink), [1, -1, 2, -2, 3, -3])
    }
}
#endif
