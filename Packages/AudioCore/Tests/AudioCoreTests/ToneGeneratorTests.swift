// ToneGeneratorTests.swift — validation, purity and shape of the reference-tone generator
// (AUD-016-T03; AUD-016-R1 to R8; contracts/tone-generator.md).
import Foundation
import XCTest
@testable import AudioCore

final class ToneGeneratorTests: XCTestCase {
    private let stereo48 = try! ToneFormat(sampleRate: 48_000, channels: 2)
    private let mono48 = try! ToneFormat(sampleRate: 48_000, channels: 1)

    private func expectError(_ expected: ToneError, file: StaticString = #filePath, line: UInt = #line,
                             _ body: () throws -> Void) {
        do {
            try body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ToneError, expected, file: file, line: line)
        }
    }

    // MARK: Validation (AUD-016-R7)

    func testFormatBounds() throws {
        expectError(.sampleRate(7_999)) { _ = try ToneFormat(sampleRate: 7_999, channels: 1) }
        expectError(.sampleRate(192_001)) { _ = try ToneFormat(sampleRate: 192_001, channels: 1) }
        expectError(.channelCount(0)) { _ = try ToneFormat(sampleRate: 48_000, channels: 0) }
        expectError(.channelCount(3)) { _ = try ToneFormat(sampleRate: 48_000, channels: 3) }
        XCTAssertEqual(try ToneFormat(sampleRate: 8_000, channels: 1).sampleRate, 8_000)
        XCTAssertEqual(try ToneFormat(sampleRate: 192_000, channels: 2).channels, 2)
        XCTAssertEqual(ToneFormat.canonical, try ToneFormat(sampleRate: 48_000, channels: 2))
    }

    func testSineBounds() {
        expectError(.frequency(0.5)) { _ = try ToneGenerator(signal: .sine(SineTone(frequency: 0.5, amplitude: 0.25)), format: stereo48) }
        expectError(.frequency(24_000)) { _ = try ToneGenerator(signal: .sine(SineTone(frequency: 24_000, amplitude: 0.25)), format: stereo48) }
        expectError(.frequency(.infinity)) { _ = try ToneGenerator(signal: .sine(SineTone(frequency: .infinity, amplitude: 0.25)), format: stereo48) }
        expectError(.amplitude(1.5)) { _ = try ToneGenerator(signal: .sine(SineTone(frequency: 1_000, amplitude: 1.5)), format: stereo48) }
        expectError(.amplitude(-0.1)) { _ = try ToneGenerator(signal: .sine(SineTone(frequency: 1_000, amplitude: -0.1)), format: stereo48) }
        expectError(.noFrequency) { _ = try ToneGenerator(signal: .sine(SineTone(left: nil, right: nil, amplitude: 0.25)), format: stereo48) }
        expectError(.monoNeedsEqualChannels) {
            _ = try ToneGenerator(signal: .sine(SineTone(left: 1_000, right: 440, amplitude: 0.25)), format: mono48)
        }
        XCTAssertNoThrow(try ToneGenerator(signal: .sine(SineTone(frequency: 23_999, amplitude: 1)), format: stereo48))
    }

    func testSweepBounds() {
        expectError(.frequency(30_000)) {
            _ = try ToneGenerator(signal: .sweep(SweepTone(start: 20, end: 30_000, seconds: 10, amplitude: 0.25, curve: .linear)), format: stereo48)
        }
        expectError(.duration(0.001)) {
            _ = try ToneGenerator(signal: .sweep(SweepTone(start: 20, end: 2_000, seconds: 0.001, amplitude: 0.25, curve: .logarithmic)), format: stereo48)
        }
        expectError(.duration(601)) {
            _ = try ToneGenerator(signal: .sweep(SweepTone(start: 20, end: 2_000, seconds: 601, amplitude: 0.25, curve: .logarithmic)), format: stereo48)
        }
        expectError(.amplitude(2)) {
            _ = try ToneGenerator(signal: .sweep(SweepTone(start: 20, end: 2_000, seconds: 1, amplitude: 2, curve: .linear)), format: stereo48)
        }
    }

    func testPulseBounds() {
        expectError(.tempo(0.5)) { _ = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 0.5, widthSeconds: 0.002, amplitude: 0.5)), format: stereo48) }
        expectError(.tempo(601)) { _ = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 601, widthSeconds: 0.002, amplitude: 0.5)), format: stereo48) }
        expectError(.pulseWidth(0)) { _ = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0, amplitude: 0.5)), format: stereo48) }
        // 600 BPM at 48 kHz: a beat is 4,800 frames, so 0.1 s (4,800 frames) is too wide.
        expectError(.pulseWidth(0.1)) { _ = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 600, widthSeconds: 0.1, amplitude: 0.5)), format: stereo48) }
        expectError(.accents) { _ = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5, accents: [])), format: stereo48) }
        expectError(.accents) { _ = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5, accents: [1, 1.5])), format: stereo48) }
        expectError(.accents) {
            _ = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5,
                                                             accents: [Double](repeating: 1, count: 33))), format: stereo48)
        }
        XCTAssertNoThrow(try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 600, widthSeconds: 0.09, amplitude: 1)), format: stereo48))
    }

    // MARK: Purity (AUD-016-R2)

    private var signals: [ToneSignal] {
        [
            .sine(SineTone(left: 1_000, right: 440, amplitude: 0.25)),
            .sweep(SweepTone(start: 20, end: 20_000, seconds: 1, amplitude: 0.25, curve: .logarithmic)),
            .sweep(SweepTone(start: 20, end: 20_000, seconds: 1, amplitude: 0.25, curve: .linear)),
            .pulses(PulseTrain(beatsPerMinute: 132, widthSeconds: 0.002, amplitude: 0.5, accents: [1, 0.5])),
            .silence,
        ]
    }

    func testAnyRangeEqualsTheSameRangeOfALongerRun() throws {
        for signal in signals {
            let generator = try ToneGenerator(signal: signal, format: stereo48)
            let long = generator.interleaved(frames: 60_000)
            let slice = generator.interleaved(frames: 7_777, startFrame: 41_234)
            XCTAssertEqual(slice, Array(long[(41_234 * 2)..<((41_234 + 7_777) * 2)]), "\(signal)")
            for frame in [0, 1, 21_818, 48_000, 59_999] {
                for channel in 0..<2 {
                    XCTAssertEqual(generator.sample(frame: Int64(frame), channel: channel).bitPattern,
                                   long[frame * 2 + channel].bitPattern, "\(signal) frame \(frame)")
                }
            }
        }
    }

    func testPlanarAndInterleavedRendersAgreeAndDoNotTouchOtherMemory() throws {
        for signal in signals {
            let generator = try ToneGenerator(signal: signal, format: stereo48)
            let frames = 5_000
            var left = [Float](repeating: .nan, count: frames + 1)
            var right = [Float](repeating: .nan, count: frames + 1)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    generator.render(left: l.baseAddress!, right: r.baseAddress!, frames: frames, startFrame: 123)
                }
            }
            var interleaved = [Float](repeating: .nan, count: frames * 2 + 1)
            interleaved.withUnsafeMutableBufferPointer { generator.render(into: $0.baseAddress!, frames: frames, startFrame: 123) }
            for i in 0..<frames {
                XCTAssertEqual(left[i].bitPattern, interleaved[i * 2].bitPattern)
                XCTAssertEqual(right[i].bitPattern, interleaved[i * 2 + 1].bitPattern)
            }
            XCTAssertTrue(left[frames].isNaN && right[frames].isNaN && interleaved[frames * 2].isNaN, "wrote past the end")
        }
    }

    func testMonoIsTheStereoLeftChannel() throws {
        for signal: ToneSignal in [.sine(SineTone(frequency: 1_000, amplitude: 0.25)),
                                   .sweep(SweepTone(start: 20, end: 20_000, seconds: 1, amplitude: 0.25, curve: .linear)),
                                   .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5)), .silence] {
            let mono = try ToneGenerator(signal: signal, format: mono48).interleaved(frames: 30_000)
            let stereo = try ToneGenerator(signal: signal, format: stereo48).interleaved(frames: 30_000)
            for i in 0..<30_000 {
                XCTAssertEqual(mono[i].bitPattern, stereo[i * 2].bitPattern)
                XCTAssertEqual(stereo[i * 2].bitPattern, stereo[i * 2 + 1].bitPattern)
            }
        }
    }

    // MARK: Shape

    func testSineIsPeriodicInOneSecondAndStartsAtZero() throws {
        let generator = try ToneGenerator(signal: .sine(SineTone(left: 1_000, right: 440, amplitude: 0.25)), format: stereo48)
        let first = generator.interleaved(frames: 4_800)
        let later = generator.interleaved(frames: 4_800, startFrame: 48_000 * 7)
        XCTAssertEqual(first.map(\.bitPattern), later.map(\.bitPattern))
        XCTAssertEqual(first[0], 0)
        XCTAssertEqual(first[1], 0)
        // 1 kHz at 48 kHz: a quarter cycle is 12 frames.
        XCTAssertEqual(generator.sample(frame: 12, channel: 0), 0.25)
        let peak = first.map { abs($0) }.max()!
        XCTAssertEqual(peak, 0.25, accuracy: 1e-6)
    }

    func testSilentChannel() throws {
        let generator = try ToneGenerator(signal: .sine(SineTone(left: nil, right: 440, amplitude: 0.25)), format: stereo48)
        let samples = generator.interleaved(frames: 1_000)
        for i in 0..<1_000 { XCTAssertEqual(samples[i * 2].bitPattern, Float(0).bitPattern) }
        XCTAssertGreaterThan(samples.map { abs($0) }.max()!, 0.2)
    }

    func testSilenceIsPositiveZero() throws {
        let samples = try ToneGenerator(signal: .silence, format: stereo48).interleaved(frames: 10_000, startFrame: 99)
        XCTAssertTrue(samples.allSatisfy { $0.bitPattern == 0 })
    }

    func testPulsesAtWholeAndFractionalPeriods() throws {
        // 120 BPM at 48 kHz: onsets every 24,000 frames, 96 frames wide (2 ms), accent pattern applied.
        let accented = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 120, widthSeconds: 0.002, amplitude: 0.5,
                                                                    accents: [1, 0.5, 0.5, 0.5])), format: mono48)
        XCTAssertEqual(accented.sample(frame: 0, channel: 0), 0.5)
        XCTAssertEqual(accented.sample(frame: 95, channel: 0), 0.5)
        XCTAssertEqual(accented.sample(frame: 96, channel: 0), 0)
        XCTAssertEqual(accented.sample(frame: 23_999, channel: 0), 0)
        XCTAssertEqual(accented.sample(frame: 24_000, channel: 0), 0.25)
        XCTAssertEqual(accented.sample(frame: 96_000, channel: 0), 0.5)
        // 132 BPM at 44.1 kHz: onset k at round(k · 20,045.45…): 20,045 and 40,091.
        let fractional = try ToneGenerator(signal: .pulses(PulseTrain(beatsPerMinute: 132, widthSeconds: 0.002, amplitude: 0.5)),
                                           format: ToneFormat(sampleRate: 44_100, channels: 1))
        XCTAssertEqual(fractional.sample(frame: 20_044, channel: 0), 0)
        XCTAssertEqual(fractional.sample(frame: 20_045, channel: 0), 0.5)
        XCTAssertEqual(fractional.sample(frame: 20_045 + 87, channel: 0), 0.5)
        XCTAssertEqual(fractional.sample(frame: 20_045 + 88, channel: 0), 0)
        XCTAssertEqual(fractional.sample(frame: 40_090, channel: 0), 0)
        XCTAssertEqual(fractional.sample(frame: 40_091, channel: 0), 0.5)
        // Far away, still on the exact grid (no drift): onset 1,000 at round(1,000 · 20,045.45…).
        XCTAssertEqual(fractional.sample(frame: 20_045_455, channel: 0), 0.5)
        XCTAssertEqual(fractional.sample(frame: 20_045_454, channel: 0), 0)
    }

    func testSweepsStartAtPhaseZeroAndRepeat() throws {
        for curve in [SweepTone.Curve.logarithmic, .linear] {
            let generator = try ToneGenerator(signal: .sweep(SweepTone(start: 20, end: 20_000, seconds: 1, amplitude: 0.25, curve: curve)),
                                              format: mono48)
            XCTAssertEqual(generator.sample(frame: 0, channel: 0), 0)
            let first = generator.interleaved(frames: 2_000)
            let repeated = generator.interleaved(frames: 2_000, startFrame: 48_000 * 3)
            XCTAssertEqual(first.map(\.bitPattern), repeated.map(\.bitPattern))
        }
    }

    func testEqualSweepFrequenciesAreASteadyTone() throws {
        let sweep = try ToneGenerator(signal: .sweep(SweepTone(start: 1_000, end: 1_000, seconds: 1, amplitude: 0.25, curve: .logarithmic)),
                                      format: mono48).interleaved(frames: 4_800)
        let sine = try ToneGenerator(signal: .sine(SineTone(frequency: 1_000, amplitude: 0.25)), format: mono48).interleaved(frames: 4_800)
        for (a, b) in zip(sweep, sine) { XCTAssertEqual(a, b, accuracy: 1e-6) }
    }
}
