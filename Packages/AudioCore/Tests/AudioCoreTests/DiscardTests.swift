// DiscardTests.swift — discarding audio that was written but not yet delivered (AUD-006-T03;
// AUD-006-R10, R11; specs/007-aud-006-seekable-transport/contracts/transport.md).
//
// A source that jumps (In-App Playback seeking or changing track) calls
// `PCMSink.discardBufferedAudio()`. With an analyzer attached, nothing written before the call may
// come out of the normalized reader afterwards: not from the sink ring, not from the converter's
// internal state, not from the normalized ring.
import Foundation
import XCTest
@testable import AudioCore

final class DiscardTests: XCTestCase {
    private final class TestClock: @unchecked Sendable { var now: Double = 0 }
    private final class Counter: @unchecked Sendable { var value = 0 }

    private func push(_ sink: PCMSink, value: Float, frames: Int, rate: Double = 44_100, channels: Int = 2) {
        let format = AudioFormat(sampleRate: rate, channelCount: channels, isInterleaved: true, sampleType: .float32)
        let samples = [Float](repeating: value, count: frames * channels)
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: format, hostTimeNs: 1) }
    }

    private func readAll(_ ring: NormalizedPCMRing) -> [Float] {
        var out: [Float] = []
        var scratch = [Float](repeating: 0, count: 8192)
        while true {
            let frames = scratch.withUnsafeMutableBufferPointer { ring.readAll(into: $0.baseAddress!, maxFrames: 4096) }
            if frames == 0 { break }
            out.append(contentsOf: scratch[0..<(frames * 2)])
        }
        return out
    }

    func testSinkWithoutHandlerDrainsItsRingAndKeepsTheSession() {
        let sink = PCMSink()
        sink.reset(sessionStartNs: 1)
        push(sink, value: 0.5, frames: 1000)
        let before = sink.statistics()
        XCTAssertEqual(sink.ring.availableToRead, 2000)
        sink.discardBufferedAudio()
        XCTAssertEqual(sink.ring.availableToRead, 0)
        XCTAssertEqual(sink.statistics(), before, "a discard is not a new session")
        XCTAssertEqual(sink.currentChannelCount, 2)
    }

    func testSinkWithHandlerCallsItOnceAndLeavesTheRingToIt() {
        let sink = PCMSink()
        let calls = Counter()
        sink.setDiscardHandler { calls.value += 1 }
        push(sink, value: 0.5, frames: 100)
        sink.discardBufferedAudio()
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(sink.ring.availableToRead, 200, "the handler owns the discard")
        sink.setDiscardHandler(nil)
        sink.discardBufferedAudio()
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(sink.ring.availableToRead, 0)
    }

    func testAnalyzerRegistersItselfAndDiscardsEveryStage() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        // Old audio in the normalized ring (analyzed) and in the sink ring (not yet analyzed).
        push(sink, value: 0.25, frames: 4410)
        clock.now = 0.1
        analyzer.step()
        XCTAssertGreaterThan(analyzer.normalizedOutput.availableFrames, 0)
        push(sink, value: 0.25, frames: 4410)

        sink.discardBufferedAudio()                 // through the handler the analyzer registered
        XCTAssertEqual(sink.ring.availableToRead, 0)
        XCTAssertEqual(analyzer.normalizedOutput.availableFrames, 0)

        // No new audio: levels are silent, not the old ones (AUD-006-R11).
        clock.now = 0.11
        XCTAssertEqual(analyzer.step().levels, .silent)

        push(sink, value: 0.75, frames: 441)
        clock.now = 0.12
        analyzer.step()
        let delivered = readAll(analyzer.normalizedOutput)
        XCTAssertEqual(delivered.count, 882)
        XCTAssertTrue(delivered.allSatisfy { $0 == 0.75 }, "only audio written after the discard is delivered")
    }

    func testDiscardDropsTheConverterTail() {
        // 48 kHz mono goes through the resampler, which keeps input between calls. After a
        // discard, its output must not contain the old level.
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        for step in 1...5 {
            push(sink, value: 0.9, frames: 480, rate: 48_000, channels: 1)
            clock.now = Double(step) * 0.01
            analyzer.step()
        }
        analyzer.discardBufferedAudio()
        XCTAssertEqual(analyzer.normalizedOutput.availableFrames, 0)
        for step in 6...15 {
            push(sink, value: 0.1, frames: 480, rate: 48_000, channels: 1)
            clock.now = Double(step) * 0.01
            analyzer.step()
        }
        let delivered = readAll(analyzer.normalizedOutput)
        XCTAssertGreaterThan(delivered.count, 4000)
        XCTAssertLessThan(delivered.map { abs($0) }.max() ?? 1, 0.2, "no sample at the old level 0.9 after the discard")
    }

    func testDiscardKeepsTheStateTheVerifiedFlagAndTheStatistics() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        for step in 1...30 {
            push(sink, value: 0.5, frames: 441)
            clock.now = Double(step) * 0.01
            analyzer.step()
        }
        XCTAssertEqual(analyzer.currentState, .active)
        let transitions = analyzer.transitions(from: 0)
        let samples = sink.statistics().sampleCount
        analyzer.discardBufferedAudio()
        clock.now = 0.31
        let update = analyzer.step()
        XCTAssertEqual(update.state, .active, "a seek is not a state change")
        XCTAssertTrue(update.hasVerifiedActiveAudio)
        XCTAssertEqual(update.statistics.sampleCount, samples)
        XCTAssertEqual(analyzer.transitions(from: 0), transitions)
        XCTAssertGreaterThan(update.sessionSeconds, 0.3)
    }

    func testNormalizerDiscardKeepsTheFormatChangeCount() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        let mono48 = AudioFormat(sampleRate: 48_000, channelCount: 1, isInterleaved: true, sampleType: .float32)
        let stereo44 = AudioFormat(sampleRate: 44_100, channelCount: 2, isInterleaved: true, sampleType: .float32)
        let samples = [Float](repeating: 0.5, count: 960)
        samples.withUnsafeBufferPointer { _ = normalizer.process($0.baseAddress!, frames: 480, format: mono48) }
        samples.withUnsafeBufferPointer { _ = normalizer.process($0.baseAddress!, frames: 480, format: stereo44) }
        XCTAssertEqual(normalizer.formatChangeCount, 1)
        normalizer.discardPending()
        samples.withUnsafeBufferPointer { _ = normalizer.process($0.baseAddress!, frames: 480, format: stereo44) }
        XCTAssertEqual(normalizer.formatChangeCount, 1, "the same format after a discard is not a format change")
    }

    func testNormalizedRingDiscardKeepsTheCounters() {
        let ring = NormalizedPCMRing()
        let samples = [Float](repeating: 0.5, count: 2 * NormalizedPCMRing.capacityFrames)
        samples.withUnsafeBufferPointer {
            ring.write($0.baseAddress!, frames: NormalizedPCMRing.capacityFrames)
            ring.write($0.baseAddress!, frames: 100)       // overflow: 100 frames dropped
        }
        XCTAssertEqual(ring.overflowDroppedFrames, 100)
        ring.discardBuffered()
        XCTAssertEqual(ring.availableFrames, 0)
        XCTAssertEqual(ring.overflowDroppedFrames, 100, "a discard is not a new session")
    }
}
