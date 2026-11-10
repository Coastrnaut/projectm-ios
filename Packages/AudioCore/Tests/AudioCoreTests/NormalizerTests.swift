// Task T057: the Normalizer (research R-05, FR-017). Every source becomes Float32 interleaved
// stereo at 44,100 Hz in the normalized ring: mono is duplicated to L=R; more than 2 channels with
// a known layout use the standard layout downmix; an unknown layout keeps channels 1 and 2; int16
// and int32 samples become Float32 (PCMSink converts them, the Normalizer takes its output); other
// rates are resampled; a format change mid-stream does not stop the stream; only an unconvertible
// format is an error.
//
// The downmix and resampling tests need AVAudioConverter, so they run on Apple platforms only.
import XCTest
@testable import AudioCore

final class NormalizerTests: XCTestCase {
    // MARK: - Helpers

    private func interleaved(frames: Int, channels: Int, _ value: (_ frame: Int, _ channel: Int) -> Float) -> [Float] {
        var out = [Float](repeating: 0, count: frames * channels)
        for f in 0..<frames {
            for c in 0..<channels { out[f * channels + c] = value(f, c) }
        }
        return out
    }

    private func format(_ rate: Double, _ channels: Int, _ type: SampleType = .float32) -> AudioFormat {
        AudioFormat(sampleRate: rate, channelCount: channels, isInterleaved: true, sampleType: type)
    }

    @discardableResult
    private func process(_ normalizer: Normalizer, _ samples: [Float], _ format: AudioFormat,
                         layout: ChannelLayoutTag = .unknown) -> Normalizer.Outcome {
        samples.withUnsafeBufferPointer {
            normalizer.process($0.baseAddress!, frames: $0.count / max(1, format.channelCount), format: format, layout: layout)
        }
    }

    /// Everything in the ring, bypassing the freshness rule (tests read all of it).
    private func drain(_ ring: NormalizedPCMRing) -> [Float] {
        var out = [Float](repeating: .nan, count: NormalizedPCMRing.capacityFrames * 2)
        let n = out.withUnsafeMutableBufferPointer { ring.readAll(into: $0.baseAddress!, maxFrames: NormalizedPCMRing.capacityFrames) }
        return Array(out.prefix(n * 2))
    }

    private func left(_ s: [Float]) -> [Float] { stride(from: 0, to: s.count, by: 2).map { s[$0] } }
    private func right(_ s: [Float]) -> [Float] { stride(from: 1, to: s.count, by: 2).map { s[$0] } }
    /// RMS of the second half (after the converter has settled).
    private func rmsOfSecondHalf(_ s: [Float]) -> Float {
        let tail = s.suffix(s.count / 2)
        return tail.isEmpty ? 0 : (tail.reduce(Float(0)) { $0 + $1 * $1 } / Float(tail.count)).squareRoot()
    }

    // MARK: - Channel mapping at 44.1 kHz (every platform)

    func testStereoAt44100PassesThrough() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        let input = interleaved(frames: 100, channels: 2) { f, c in c == 0 ? Float(f) : -Float(f) }
        XCTAssertEqual(process(normalizer, input, format(44_100, 2)), .ok(framesWritten: 100))
        XCTAssertEqual(drain(ring), input)
    }

    func testMonoIsDuplicatedToBothChannels() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        let input = (0..<64).map { Float($0) / 64 }
        XCTAssertEqual(process(normalizer, input, format(44_100, 1)), .ok(framesWritten: 64))
        let out = drain(ring)
        XCTAssertEqual(left(out), input)
        XCTAssertEqual(right(out), input)
    }

    func testUnknownLayoutKeepsChannels1And2() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        // Six channels, no layout: channel c carries the value (c + 1) / 10.
        let input = interleaved(frames: 50, channels: 6) { _, c in Float(c + 1) / 10 }
        XCTAssertEqual(process(normalizer, input, format(44_100, 6)), .ok(framesWritten: 50))
        let out = drain(ring)
        XCTAssertEqual(out.count, 100)
        XCTAssertEqual(Set(left(out)), [0.1])
        XCTAssertEqual(Set(right(out)), [0.2])
    }

    func testLayoutThatDoesNotDescribeTheChannelsCountsAsUnknown() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        let input = interleaved(frames: 10, channels: 4) { _, c in Float(c + 1) }
        // A 5.1 tag (6 channels) on a 4-channel stream, and a channel-description tag: unknown.
        process(normalizer, input, format(44_100, 4), layout: .mpeg5_1A)
        process(normalizer, input, format(44_100, 4), layout: ChannelLayoutTag(rawValue: 0))
        let out = drain(ring)
        XCTAssertEqual(Set(left(out)), [1])
        XCTAssertEqual(Set(right(out)), [2])
        XCTAssertFalse(ChannelLayoutTag.mpeg5_1A.describes(channelCount: 4))
        XCTAssertTrue(ChannelLayoutTag.mpeg5_1A.describes(channelCount: 6))
        XCTAssertFalse(ChannelLayoutTag.unknown.describes(channelCount: 6))
        XCTAssertFalse(ChannelLayoutTag.discreteInOrder(channelCount: 6).describes(channelCount: 6))
    }

    func testInt16AndInt32BecomeFloat32ThroughTheSink() {
        // PCMSink converts integer samples to Float32; the Normalizer takes the sink's output.
        let sink = PCMSink()
        let int16: [Int16] = [16_384, -16_384, 32_767, -32_768]          // 2 stereo frames
        int16.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 2, format: format(44_100, 2, .int16)) }
        let int32: [Int32] = [1_073_741_824, -1_073_741_824]              // 1 stereo frame
        int32.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: 1, format: format(44_100, 2, .int32)) }
        var raw = [Float](repeating: 0, count: 6)
        let n = raw.withUnsafeMutableBufferPointer { sink.ring.read(into: $0.baseAddress!, maxCount: 6) }
        XCTAssertEqual(n, 6)

        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        XCTAssertEqual(process(normalizer, raw, format(44_100, 2, .int32)), .ok(framesWritten: 3))
        let out = drain(ring)
        XCTAssertEqual(out, [0.5, -0.5, 32_767 / 32_768, -1, 0.5, -0.5])
    }

    func testFormatChangeMidStreamDoesNotStopTheStream() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        XCTAssertEqual(process(normalizer, [Float](repeating: 0.25, count: 200), format(44_100, 2)), .ok(framesWritten: 100))
        XCTAssertEqual(process(normalizer, [Float](repeating: 0.5, count: 100), format(44_100, 1)), .ok(framesWritten: 100))
        XCTAssertEqual(process(normalizer, [Float](repeating: 0.75, count: 600), format(44_100, 6)), .ok(framesWritten: 100))
        XCTAssertEqual(normalizer.formatChangeCount, 2)
        let out = drain(ring)
        XCTAssertEqual(out.count, 600)
        XCTAssertEqual(out[0], 0.25)
        XCTAssertEqual(out[200], 0.5)
        XCTAssertEqual(out[599], 0.75)
    }

    func testUnconvertibleFormatIsAnError() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        for bad in [format(0, 2), format(44_100, 0), format(1_000, 2), format(1_000_000, 2)] {
            guard case .failed(.error) = process(normalizer, [0, 0, 0, 0], bad) else {
                return XCTFail("\(bad) should be unconvertible")
            }
        }
        XCTAssertEqual(ring.availableFrames, 0)
        // A valid format afterwards works again.
        XCTAssertEqual(process(normalizer, [0.1, 0.2], format(44_100, 2)), .ok(framesWritten: 1))
    }

    func testLongInputIsProcessedInChunks() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        let frames = Normalizer.maxChunkFrames * 2 + 7
        let input = interleaved(frames: frames, channels: 1) { f, _ in Float(f % 100) }
        XCTAssertEqual(process(normalizer, input, format(44_100, 1)), .ok(framesWritten: frames))
        XCTAssertEqual(ring.availableFrames, frames)
    }

    // MARK: - Fallback resampler (Linux test host; tested everywhere)

    func testLinearResamplerKeepsA1kHzSineAt1kHzAcrossChunks() {
        let ring = NormalizedPCMRing()
        let resampler = LinearResampler(inputRate: 48_000)
        let total = 21_600, chunk = 480
        let sine = interleaved(frames: total, channels: 2) { f, _ in
            0.5 * Float(sin(2 * Double.pi * 1_000 * Double(f) / 48_000))
        }
        var written = 0
        for start in stride(from: 0, to: total, by: chunk) {
            written += sine[(start * 2)..<((start + chunk) * 2)].withUnsafeBufferPointer {
                resampler.convert($0.baseAddress!, frames: chunk, into: ring)
            }
        }
        XCTAssertEqual(Double(written), 19_845, accuracy: 2)
        XCTAssertEqual(Self.zeroCrossingFrequency(of: left(drain(ring)), sampleRate: 44_100), 1_000, accuracy: 1)
    }

    // MARK: - AVAudioConverter (Apple platforms)

    #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
    func testFiveOneUsesTheStandardDownmix() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        // 5.1 (L R C LFE Ls Rs), a 1 kHz tone on the center channel only. Keeping channels 1-2
        // would be silent; the standard downmix puts the center into both L and R equally.
        let frames = 4_410
        let input = interleaved(frames: frames, channels: 6) { f, c in
            c == 2 ? 0.5 * Float(sin(2 * Double.pi * 1_000 * Double(f) / 44_100)) : 0
        }
        guard case .ok(let written) = process(normalizer, input, format(44_100, 6), layout: .mpeg5_1A) else {
            return XCTFail("5.1 should convert")
        }
        XCTAssertGreaterThan(written, frames / 2)
        let out = drain(ring)
        let l = left(out), r = right(out)
        let lr = rmsOfSecondHalf(l), rr = rmsOfSecondHalf(r)
        XCTAssertGreaterThan(lr, 0.05, "center reaches L")
        XCTAssertGreaterThan(rr, 0.05, "center reaches R")
        XCTAssertEqual(lr, rr, accuracy: 0.01, "center is split equally")
    }

    func testFiveOneLeftChannelStaysLeft() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        let input = interleaved(frames: 4_410, channels: 6) { f, c in
            c == 0 ? 0.5 * Float(sin(2 * Double.pi * 440 * Double(f) / 44_100)) : 0
        }
        process(normalizer, input, format(44_100, 6), layout: .mpeg5_1A)
        let out = drain(ring)
        let l = left(out), r = right(out)
        XCTAssertGreaterThan(rmsOfSecondHalf(l), 0.1)
        XCTAssertLessThan(rmsOfSecondHalf(r), 0.01)
    }

    func testResampling48kHzKeepsA1kHzSineAt1kHz() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        // 0.45 s of a 1 kHz sine at 48 kHz, fed in 10 ms chunks like the work queue does
        // (the ring holds 0.5 s at 44.1 kHz, and this test reads it only at the end).
        let total = 21_600, chunk = 480
        let sine = interleaved(frames: total, channels: 2) { f, _ in
            0.5 * Float(sin(2 * Double.pi * 1_000 * Double(f) / 48_000))
        }
        var written = 0
        for start in stride(from: 0, to: total, by: chunk) {
            let slice = Array(sine[(start * 2)..<((start + chunk) * 2)])
            guard case .ok(let n) = process(normalizer, slice, format(48_000, 2)) else {
                return XCTFail("48 kHz should convert")
            }
            written += n
        }
        // 21,600 frames at 48 kHz are 19,845 at 44.1 kHz, less the converter's latency.
        XCTAssertGreaterThan(written, 19_000)
        XCTAssertLessThanOrEqual(written, 19_845)
        let l = left(drain(ring))
        let measured = Self.zeroCrossingFrequency(of: Array(l.dropFirst(2_000)), sampleRate: 44_100)
        XCTAssertEqual(measured, 1_000, accuracy: 1)
    }

    func testMonoAt48kHzIsResampledAndDuplicated() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        let input = (0..<4_800).map { 0.5 * Float(sin(2 * Double.pi * 1_000 * Double($0) / 48_000)) }
        guard case .ok(let n) = process(normalizer, input, format(48_000, 1)) else {
            return XCTFail("mono 48 kHz should convert")
        }
        // 4,800 frames at 48 kHz are 4,410 at 44.1 kHz, less the converter's priming latency.
        XCTAssertGreaterThan(n, 3_500)
        let out = drain(ring)
        XCTAssertEqual(left(out), right(out))
    }

    func testRateChangeMidStreamDoesNotStopTheStream() {
        let ring = NormalizedPCMRing()
        let normalizer = Normalizer(output: ring)
        guard case .ok = process(normalizer, [Float](repeating: 0.1, count: 9_600), format(48_000, 2)),
              case .ok = process(normalizer, [Float](repeating: 0.1, count: 4_410), format(44_100, 1)),
              case .ok = process(normalizer, [Float](repeating: 0.1, count: 9_600), format(48_000, 2)) else {
            return XCTFail("every format should convert")
        }
        XCTAssertEqual(normalizer.formatChangeCount, 2)
        XCTAssertGreaterThan(ring.availableFrames, 4_410)
    }

    #endif

    /// Frequency from linearly interpolated rising zero crossings.
    static func zeroCrossingFrequency(of s: [Float], sampleRate: Double) -> Double {
        var crossings: [Double] = []
        for i in 1..<s.count where s[i - 1] < 0 && s[i] >= 0 {
            let fraction = Double(-s[i - 1] / (s[i] - s[i - 1]))
            crossings.append(Double(i - 1) + fraction)
        }
        guard crossings.count > 2, let first = crossings.first, let last = crossings.last else { return 0 }
        return Double(crossings.count - 1) / ((last - first) / sampleRate)
    }
}
