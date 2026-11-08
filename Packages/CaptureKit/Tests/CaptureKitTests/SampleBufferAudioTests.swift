// Task T037: the CMSampleBuffer → AudioBufferList → PCMSink copy used by the ScreenCaptureKit
// audio output. Synthetic sample buffers built with CoreMedia on the host; no ScreenCaptureKit,
// no device. These tests show that the copy works on this host's CoreMedia; whether iOS delivers
// other apps' audio at all is a device question (RI-002, T040).
#if canImport(CoreMedia) && canImport(CoreAudioTypes)
import AudioCore
import CoreAudioTypes
import CoreMedia
import XCTest
@testable import CaptureKit

final class SampleBufferAudioTests: XCTestCase {
    // MARK: - Exact frames reach PCMSink (regression test for the 136-byte list size, review F1)

    func testPlanarStereoFloat32ReachesSinkExactly() throws {
        try assertRoundTrip(frames: 480, channels: 2, interleaved: false)
    }

    func testPlanarStereoWithUnalignedSecondPlaneReachesSinkExactly() throws {
        // 1023 frames: plane 1 starts at 4092 bytes, not 16-byte aligned (review F18: flags 0).
        try assertRoundTrip(frames: 1023, channels: 2, interleaved: false)
    }

    func testInterleavedStereoFloat32ReachesSinkExactly() throws {
        try assertRoundTrip(frames: 512, channels: 2, interleaved: true)
    }

    func testMonoFloat32ReachesSinkExactly() throws {
        try assertRoundTrip(frames: 256, channels: 1, interleaved: false)
    }

    func testInterleavedInt16IsConvertedToFloat() throws {
        let frames = 64
        var samples = [Int16](repeating: 0, count: frames * 2)
        for f in 0..<frames {
            samples[f * 2] = Int16(f * 100)
            samples[f * 2 + 1] = Int16(-f * 100)
        }
        let buffer = try samples.withUnsafeBytes { raw in
            try makeSampleBuffer(bytes: raw, frames: frames, channels: 2, interleaved: true, int16: true)
        }
        let sink = PCMSink()
        let writer = SampleBufferAudioWriter(sink: sink)
        XCTAssertEqual(writer.write(buffer), .written(frames: frames))
        let read = readAll(sink, count: frames * 2)
        XCTAssertEqual(read.count, frames * 2)
        for i in 0..<read.count {
            XCTAssertEqual(read[i], Float(samples[i]) / 32_768, accuracy: 1e-6)
        }
        XCTAssertEqual(sink.statistics().format?.sampleType, .int16)
    }

    // MARK: - Why the list size is queried first

    func testCoreMediaRejectsAnyListSizeButTheExactOne() throws {
        let buffer = try makeFloatSampleBuffer(frames: 480, channels: 2, interleaved: false, rate: 48_000)
        var needed = 0
        XCTAssertEqual(CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil), noErr)
        XCTAssertEqual(needed, MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size)

        // The old callback passed room for PCMSink.maxChannels buffers (136 bytes).
        let oldSize = MemoryLayout<AudioBufferList>.size + (PCMSink.maxChannels - 1) * MemoryLayout<AudioBuffer>.size
        let storage = UnsafeMutableRawPointer.allocate(byteCount: oldSize, alignment: 16)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        let oversized = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: oldSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block)
        XCTAssertNotEqual(oversized, noErr, "CoreMedia accepted a larger list; the exact-size rule may have changed")
        block = nil
        let exact = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block)
        XCTAssertEqual(exact, noErr)
        XCTAssertEqual(list.pointee.mNumberBuffers, 2)
    }

    // MARK: - Stop, rejection, format changes

    func testWritesAfterStopAreIgnoredAndLeaveTheSinkUntouched() throws {
        let sink = PCMSink()
        let writer = SampleBufferAudioWriter(sink: sink)
        writer.stop()
        XCTAssertTrue(writer.isStopped)
        let buffer = try makeFloatSampleBuffer(frames: 480, channels: 2, interleaved: false, rate: 48_000)
        XCTAssertEqual(writer.write(buffer), .stopped)
        XCTAssertEqual(sink.statistics().sampleCount, 0)
        XCTAssertEqual(sink.statistics().bufferCount, 0)
        XCTAssertNil(sink.statistics().format)
        XCTAssertEqual(writer.rejectedCount, 0)
    }

    func testBufferWithoutAudioFormatIsRejectedAndCounted() throws {
        var buffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: nil, sampleCount: 0, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer)
        XCTAssertEqual(status, noErr)
        let sink = PCMSink()
        let writer = SampleBufferAudioWriter(sink: sink)
        XCTAssertEqual(writer.write(try XCTUnwrap(buffer)), .unsupportedFormat)
        XCTAssertEqual(writer.rejectedCount, 1)
        XCTAssertEqual(sink.statistics().bufferCount, 0)
    }

    /// The driver no longer emits `.formatChanged` from the audio callback (review F17), because
    /// PCMSink already counts format changes; CaptureManager logs them from the statistics.
    func testFormatChangeIsCountedByTheSink() throws {
        let sink = PCMSink()
        let writer = SampleBufferAudioWriter(sink: sink)
        XCTAssertEqual(writer.write(try makeFloatSampleBuffer(frames: 480, channels: 2, interleaved: false, rate: 48_000)),
                       .written(frames: 480))
        XCTAssertEqual(writer.write(try makeFloatSampleBuffer(frames: 441, channels: 2, interleaved: false, rate: 44_100)),
                       .written(frames: 441))
        let stats = sink.statistics()
        XCTAssertEqual(stats.formatChangeCount, 1)
        XCTAssertEqual(stats.format?.sampleRate, 44_100)
        XCTAssertEqual(stats.sampleCount, 921)
        XCTAssertEqual(stats.bufferCount, 2)
    }

    // MARK: - Helpers

    /// Builds a Float32 buffer whose sample for (frame f, channel c) is `value(f, c)`, writes it
    /// through the writer, and reads the sink's interleaved ring back.
    private func assertRoundTrip(frames: Int, channels: Int, interleaved: Bool,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let buffer = try makeFloatSampleBuffer(frames: frames, channels: channels, interleaved: interleaved, rate: 48_000)
        let sink = PCMSink()
        let writer = SampleBufferAudioWriter(sink: sink)
        XCTAssertEqual(writer.write(buffer), .written(frames: frames), file: file, line: line)
        XCTAssertEqual(writer.rejectedCount, 0, file: file, line: line)

        let stats = sink.statistics()
        XCTAssertEqual(stats.sampleCount, frames, file: file, line: line)
        XCTAssertEqual(stats.bufferCount, 1, file: file, line: line)
        XCTAssertEqual(stats.format, AudioFormat(sampleRate: 48_000, channelCount: channels,
                                                 isInterleaved: interleaved || channels == 1,
                                                 sampleType: .float32), file: file, line: line)

        let read = readAll(sink, count: frames * channels)
        XCTAssertEqual(read.count, frames * channels, file: file, line: line)
        guard read.count == frames * channels else { return }
        for f in 0..<frames {
            for c in 0..<channels where read[f * channels + c] != Self.value(f, c) {
                XCTFail("frame \(f) channel \(c): \(read[f * channels + c]) != \(Self.value(f, c))",
                        file: file, line: line)
                return
            }
        }
    }

    private static func value(_ frame: Int, _ channel: Int) -> Float {
        Float(channel + 1) * 0.5 - Float(frame) / 4096
    }

    private func readAll(_ sink: PCMSink, count: Int) -> [Float] {
        var out = [Float](repeating: .nan, count: count + 16)
        let n = out.withUnsafeMutableBufferPointer { sink.ring.read(into: $0.baseAddress!, maxCount: $0.count) }
        return Array(out.prefix(n))
    }

    private func makeFloatSampleBuffer(frames: Int, channels: Int, interleaved: Bool,
                                       rate: Double) throws -> CMSampleBuffer {
        var samples = [Float](repeating: 0, count: frames * channels)
        for f in 0..<frames {
            for c in 0..<channels {
                // Interleaved: frame-major. Planar: channel c's plane, then the next plane.
                samples[interleaved ? f * channels + c : c * frames + f] = Self.value(f, c)
            }
        }
        return try samples.withUnsafeBytes { raw in
            try makeSampleBuffer(bytes: raw, frames: frames, channels: channels,
                                 interleaved: interleaved, int16: false, rate: rate)
        }
    }

    /// One contiguous block: interleaved frames, or planes back to back (how CoreMedia lays out
    /// a non-interleaved LPCM sample buffer).
    private func makeSampleBuffer(bytes: UnsafeRawBufferPointer, frames: Int, channels: Int,
                                  interleaved: Bool, int16: Bool, rate: Double = 48_000) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes.count,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block), noErr)
        let dataBuffer = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: dataBuffer,
                                                     offsetIntoDestination: 0, dataLength: bytes.count), noErr)

        let sampleBytes = UInt32(int16 ? 2 : 4)
        let bytesPerFrame = interleaved ? sampleBytes * UInt32(channels) : sampleBytes
        var flags = int16 ? kAudioFormatFlagIsSignedInteger : kAudioFormatFlagIsFloat
        flags |= kAudioFormatFlagIsPacked
        if !interleaved { flags |= kAudioFormatFlagIsNonInterleaved }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: sampleBytes * 8, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
            magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)

        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: dataBuffer, formatDescription: try XCTUnwrap(format),
            sampleCount: frames, presentationTimeStamp: CMTime(value: 0, timescale: CMTimeScale(rate)),
            packetDescriptions: nil, sampleBufferOut: &sampleBuffer), noErr)
        return try XCTUnwrap(sampleBuffer)
    }
}
#endif
