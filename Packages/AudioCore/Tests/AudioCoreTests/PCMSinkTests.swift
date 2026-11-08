// Task T027 AC: 1 s written through PCMSink reads back identically; format handling and statistics.
import XCTest
@testable import AudioCore

final class PCMSinkTests: XCTestCase {
    private let stereoFloat = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)

    private func drainAll(_ sink: PCMSink) -> [Float] {
        var out = [Float](repeating: 0, count: sink.ring.capacity)
        let n = out.withUnsafeMutableBufferPointer { sink.ring.read(into: $0.baseAddress!, maxCount: $0.count) }
        return Array(out.prefix(n))
    }

    func testOneSecondInterleavedRoundTrip() {
        let sink = PCMSink()
        sink.reset(sessionStartNs: 1_000)
        let frames = 48_000
        let input = (0..<(frames * 2)).map { Float($0 % 1000) / 1000 }
        var t: UInt64 = 2_000
        var offset = 0
        while offset < frames {
            let n = min(512, frames - offset)
            input.withUnsafeBufferPointer {
                sink.writeInterleaved(UnsafeRawPointer($0.baseAddress! + offset * 2), frames: n, format: stereoFloat, hostTimeNs: t)
            }
            offset += n
            t += 10_666_667
        }
        XCTAssertEqual(drainAll(sink), input)
        let stats = sink.statistics()
        XCTAssertEqual(stats.sampleCount, frames)
        XCTAssertEqual(stats.format, stereoFloat)
        XCTAssertEqual(stats.droppedSamples, 0)
        XCTAssertEqual(stats.cadenceMeanMs, 10.666667, accuracy: 0.001)
        XCTAssertEqual(stats.lateBuffers, 0)
        XCTAssertNotNil(stats.startToFirstAudioMs)
    }

    func testInt16IsConvertedToFloat() {
        let sink = PCMSink()
        let format = AudioFormat(sampleRate: 44_100, channelCount: 1, isInterleaved: true, sampleType: .int16)
        let input: [Int16] = [0, 16_384, -32_768]
        input.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 3, format: format, hostTimeNs: 1) }
        XCTAssertEqual(drainAll(sink), [0, 0.5, -1])
    }

    func testPlanarIsInterleaved() {
        let sink = PCMSink()
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: false, sampleType: .float32)
        let left: [Float] = [1, 2, 3]
        let right: [Float] = [-1, -2, -3]
        left.withUnsafeBytes { l in
            right.withUnsafeBytes { r in
                let planes: [UnsafeRawPointer?] = [l.baseAddress, r.baseAddress]
                planes.withUnsafeBufferPointer {
                    sink.writePlanar($0.baseAddress!, planeCount: 2, frames: 3, format: format, hostTimeNs: 1)
                }
            }
        }
        XCTAssertEqual(drainAll(sink), [1, -1, 2, -2, 3, -3])
    }

    func testFormatChangeIsCountedNotFatal() {
        let sink = PCMSink()
        let mono = AudioFormat(sampleRate: 44_100, channelCount: 1, isInterleaved: true, sampleType: .float32)
        let samples: [Float] = [0.1, 0.2, 0.3, 0.4]
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 2, format: stereoFloat, hostTimeNs: 1) }
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 4, format: mono, hostTimeNs: 2) }
        let stats = sink.statistics()
        XCTAssertEqual(stats.formatChangeCount, 1)
        XCTAssertEqual(stats.format, mono)
        XCTAssertEqual(stats.sampleCount, 6)
    }

    func testLateBufferCounted() {
        let sink = PCMSink()
        let one: [Float] = [0, 0]
        var t: UInt64 = 0
        for _ in 0..<10 {
            t += 10_000_000
            one.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 1, format: stereoFloat, hostTimeNs: t) }
        }
        t += 50_000_000   // 5× the cadence
        one.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 1, format: stereoFloat, hostTimeNs: t) }
        XCTAssertEqual(sink.statistics().lateBuffers, 1)
        XCTAssertEqual(sink.statistics().cadenceMaxMs, 50, accuracy: 0.001)
    }

    func testResetClearsEverything() {
        let sink = PCMSink()
        let one: [Float] = [0.5, 0.5]
        one.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 1, format: stereoFloat, hostTimeNs: 5) }
        sink.reset()
        XCTAssertEqual(sink.statistics(), PCMSinkStatistics())
        XCTAssertEqual(sink.ring.availableToRead, 0)
    }

    // Review F8: session time starts when the source has started, not before the picker.
    func testMarkSessionStartMovesTimeZero() {
        let sink = PCMSink()
        sink.reset(sessionStartNs: 1_000)
        sink.markSessionStart(atNanoseconds: 4_000_001_000)   // 4 s later, e.g. after the picker
        let one: [Float] = [0.5, 0.5]
        one.withUnsafeBytes {
            sink.writeInterleaved($0.baseAddress!, frames: 1, format: stereoFloat, hostTimeNs: 4_150_001_000)
        }
        let stats = sink.statistics()
        XCTAssertEqual(stats.startToFirstAudioMs ?? -1, 150, accuracy: 1e-6)
        XCTAssertEqual(stats.firstSampleSeconds ?? -1, 0.15, accuracy: 1e-9)
    }

    func testBufferBeforeMarkIsTimeZero() {
        let sink = PCMSink()
        sink.reset(sessionStartNs: 1_000)
        let one: [Float] = [0.5, 0.5]
        one.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 1, format: stereoFloat, hostTimeNs: 2_000) }
        sink.markSessionStart(atNanoseconds: 10_000)   // a buffer raced ahead of the mark
        XCTAssertEqual(sink.statistics().startToFirstAudioMs, 0)
        XCTAssertEqual(sink.statistics().firstSampleSeconds, 0)
        XCTAssertEqual(sink.statistics().sampleCount, 1, "the mark does not clear statistics")
    }

    // Review F9: the producer loops are index loops; check they still cover every frame and
    // channel, including more than maxFramesPerWrite frames and more than maxChannels channels.
    func testLargeWritesCoverEveryFrameAndChannel() {
        let sink = PCMSink()
        let frames = PCMSink.maxFramesPerWrite + 3
        let channels = PCMSink.maxChannels + 2
        let wide = AudioFormat(sampleRate: 96_000, channelCount: channels, isInterleaved: true, sampleType: .float32)
        let input = (0..<(frames * channels)).map { Float($0 % 977) / 977 }
        input.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: wide, hostTimeNs: 1) }
        var expected: [Float] = []
        for f in 0..<frames { for c in 0..<PCMSink.maxChannels { expected.append(input[f * channels + c]) } }
        XCTAssertEqual(drainAll(sink), expected)

        let planar = AudioFormat(sampleRate: 96_000, channelCount: channels, isInterleaved: false, sampleType: .float32)
        let planeData = (0..<channels).map { c in (0..<frames).map { Float(c * 10_000 + $0 % 5_000) } }
        let pointers = planeData.map { plane -> UnsafeMutableRawPointer in
            let p = UnsafeMutableRawPointer.allocate(byteCount: frames * 4, alignment: 4)
            plane.withUnsafeBytes { p.copyMemory(from: $0.baseAddress!, byteCount: frames * 4) }
            return p
        }
        defer { pointers.forEach { $0.deallocate() } }
        var planes: [UnsafeRawPointer?] = pointers.map { UnsafeRawPointer($0) }
        planes.withUnsafeMutableBufferPointer {
            sink.writePlanar($0.baseAddress!, planeCount: channels, frames: frames, format: planar, hostTimeNs: 2)
        }
        expected.removeAll()
        for f in 0..<frames { for c in 0..<PCMSink.maxChannels { expected.append(planeData[c][f]) } }
        XCTAssertEqual(drainAll(sink), expected)
    }

    func testFormatPackRoundTrip() {
        for f in [stereoFloat,
                  AudioFormat(sampleRate: 44_100, channelCount: 6, isInterleaved: false, sampleType: .int32),
                  AudioFormat(sampleRate: 16_000, channelCount: 1, isInterleaved: true, sampleType: .int16)] {
            XCTAssertEqual(PCMSink.unpack(PCMSink.pack(f)), f)
        }
    }
}
