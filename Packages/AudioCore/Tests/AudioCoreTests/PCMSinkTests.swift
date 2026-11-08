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

    func testFormatPackRoundTrip() {
        for f in [stereoFloat,
                  AudioFormat(sampleRate: 44_100, channelCount: 6, isInterleaved: false, sampleType: .int32),
                  AudioFormat(sampleRate: 16_000, channelCount: 1, isInterleaved: true, sampleType: .int16)] {
            XCTAssertEqual(PCMSink.unpack(PCMSink.pack(f)), f)
        }
    }
}
