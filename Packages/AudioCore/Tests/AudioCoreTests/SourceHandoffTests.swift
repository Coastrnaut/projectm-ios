// SourceHandoffTests.swift — AUD-012: the renderer boundary's sanitizer and switch envelope
// (specs/092-aud-012-source-crossfade, contracts/source-handoff.md C1; spec User Story 2).
//
// Everything is measured on the sample clock: frames written and read in order (`readAll`, no
// freshness skip, the way the analysis tap reads).
import XCTest
@testable import AudioCore

final class SourceHandoffTests: XCTestCase {
    private func stereo(_ value: Float, frames: Int) -> [Float] {
        [Float](repeating: value, count: frames * 2)
    }

    private func write(_ ring: NormalizedPCMRing, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Void in
            ring.write(buffer.baseAddress!, frames: buffer.count / 2)
        }
    }

    /// Writes `frames` frames of a constant level in 441-frame (10 ms) buffers, like drain passes.
    private func writeLevel(_ ring: NormalizedPCMRing, _ value: Float, frames: Int) {
        var left = frames
        while left > 0 {
            let n = min(left, 441)
            write(ring, stereo(value, frames: n))
            left -= n
        }
    }

    private func readAllMain(_ ring: NormalizedPCMRing) -> [Float] {
        var out = [Float](repeating: .nan, count: NormalizedPCMRing.capacityFrames * 2)
        let n = out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Float>) -> Int in
            ring.readAll(into: buffer.baseAddress!, maxFrames: NormalizedPCMRing.capacityFrames)
        }
        return Array(out.prefix(n * 2))
    }

    private func readAllTap(_ ring: NormalizedPCMRing) -> [Float] {
        guard let tap = ring.analysisTap else { return [] }
        var out = [Float](repeating: .nan, count: NormalizedPCMRing.capacityFrames * 2)
        let n = out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Float>) -> Int in
            tap.read(into: buffer.baseAddress!, maxFrames: NormalizedPCMRing.capacityFrames)
        }
        return Array(out.prefix(n * 2))
    }

    /// The largest change between consecutive samples of one channel.
    private func maxStep(_ samples: [Float], channel: Int) -> Float {
        var largest: Float = 0
        var i = channel + 2
        while i < samples.count {
            let step: Float = abs(samples[i] - samples[i - 2])
            largest = max(largest, step)
            i += 2
        }
        return largest
    }

    // MARK: - Sanitizer (AUD-012-R9, R10)

    func testSanitizerReplacesNonFiniteAndClampsWithAnExactCount() {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096, sampleBound: PCMSanitizer.bound)
        var samples = stereo(0.25, frames: 100)
        samples[0] = .nan
        samples[1] = .infinity
        samples[50] = -.infinity
        samples[60] = 3
        samples[61] = -7
        samples[62] = 2   // exactly the bound: kept
        write(ring, samples)
        let main = readAllMain(ring)
        let tap = readAllTap(ring)
        XCTAssertEqual(ring.sanitizedSampleCount, 5)
        XCTAssertEqual(main.count, 200)
        XCTAssertEqual(main, tap)
        XCTAssertTrue(main.allSatisfy { $0.isFinite && abs($0) <= 2 })
        XCTAssertEqual(Array(main[0...1]), [0, 0])
        XCTAssertEqual(main[50], 0)
        XCTAssertEqual(Array(main[60...62]), [2, -2, 2])
        XCTAssertEqual(main[2], 0.25)
    }

    func testCleanAudioIsBitIdenticalAndUncounted() {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 4_096, sampleBound: PCMSanitizer.bound)
        var samples: [Float] = []
        for i in 0..<2_000 {   // over one boundary chunk; values up to ±1.9
            let phase: Float = Float(i) * 0.031
            samples.append(1.9 * sin(phase))
        }
        samples.append(-0.0)
        samples.append(Float.leastNonzeroMagnitude)
        write(ring, samples)
        let main = readAllMain(ring)
        XCTAssertEqual(main.map(\.bitPattern), samples.map(\.bitPattern))
        XCTAssertEqual(ring.sanitizedSampleCount, 0)
        XCTAssertEqual(ring.handoffPhase, .unity)
    }

    func testAnUnboundedRingReplacesOnlyNonFiniteValues() {
        let ring = NormalizedPCMRing()
        write(ring, [5, .nan, -300, 1])
        XCTAssertEqual(readAllMain(ring), [5, 0, -300, 1])
        XCTAssertEqual(ring.sanitizedSampleCount, 1)
    }

    func testTheCapturePathRingIsBoundedToTwo() {
        let analyzer = AudioAnalyzer(sink: PCMSink())
        XCTAssertEqual(analyzer.normalizedOutput.sampleBound, 2)
    }

    func testReplaceNonFiniteLeavesLoudFiniteValues() {
        var samples: [Float] = [.nan, 5, -.infinity, 0.5]
        let replaced = samples.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Float>) -> Int in
            PCMSanitizer.replaceNonFinite(buffer.baseAddress!, count: buffer.count)
        }
        XCTAssertEqual(replaced, 2)
        XCTAssertEqual(samples, [0, 5, 0, 0.5])
    }

    // MARK: - Envelope (AUD-012-R3, R4)

    func testFadeOutSilenceAndFadeInHaveTheStepBoundAndExactEnds() {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 22_050)
        writeLevel(ring, 0.5, frames: 441)
        ring.beginFadeOut()
        writeLevel(ring, 0.5, frames: HandoffEnvelope.fadeFrames + 441)   // the old source keeps delivering
        XCTAssertEqual(ring.handoffPhase, .silent)
        ring.resetForHandoff()
        ring.beginFadeIn()
        XCTAssertEqual(ring.handoffPhase, .fadingIn)
        writeLevel(ring, -0.5, frames: HandoffEnvelope.fadeFrames + 441)
        XCTAssertEqual(ring.handoffPhase, .unity)
        let main = readAllMain(ring)
        let bound: Float = 0.5 / Float(HandoffEnvelope.fadeFrames) + 1e-6
        XCTAssertLessThanOrEqual(maxStep(main, channel: 0), bound)
        XCTAssertLessThanOrEqual(maxStep(main, channel: 1), bound)
        // The fade-out ends at exactly 0 after 4,410 frames; then the old source's extra 441 frames
        // (zeros), the 1,024-frame silence, and the fade-in, which reaches −0.5 exactly.
        let fadeEnd = (441 + HandoffEnvelope.fadeFrames - 1) * 2
        XCTAssertEqual(main[fadeEnd], 0)
        let zeros = main[(fadeEnd)...].prefix { $0 == 0 }.count / 2
        XCTAssertEqual(zeros, 1 + 441 + HandoffEnvelope.silenceFrames)
        XCTAssertEqual(main.last, -0.5)
        XCTAssertTrue(main.allSatisfy { $0 >= -0.5 && $0 <= 0.5 })
    }

    func testForcedCompletionRampsFromTheLastFrameWithinTheBound() {
        let ring = NormalizedPCMRing()
        writeLevel(ring, 0.5, frames: 441)
        ring.beginFadeOut()
        writeLevel(ring, 0.5, frames: 441)   // part of the fade had audio, then the source stalled
        let position = ring.handoffEnvelope.position
        XCTAssertEqual(position, HandoffEnvelope.fadeFrames - 441)
        let written = ring.completeFadeOut()
        XCTAssertEqual(written, HandoffEnvelope.maxForcedFrames)
        XCTAssertEqual(ring.handoffPhase, .silent)
        let main = readAllMain(ring)
        XCTAssertEqual(main.count, (441 + 441 + 1_024) * 2)
        XCTAssertEqual(main.last, 0)
        let last: Float = 0.5 * Float(position) / Float(HandoffEnvelope.fadeFrames)
        let bound: Float = last / Float(HandoffEnvelope.maxForcedFrames) + 1e-6
        XCTAssertLessThanOrEqual(maxStep(Array(main.suffix(1_025 * 2)), channel: 0), bound)
        XCTAssertLessThanOrEqual(maxStep(main, channel: 0), max(bound, 0.5 / Float(HandoffEnvelope.fadeFrames) + 1e-6))
    }

    func testForcedCompletionNearTheEndUsesTheRemainingFrames() {
        let ring = NormalizedPCMRing()
        ring.beginFadeOut()
        writeLevel(ring, 1, frames: HandoffEnvelope.fadeFrames - 10)
        XCTAssertEqual(ring.completeFadeOut(), 10)
        let main = readAllMain(ring)
        XCTAssertEqual(main.last, 0)
        XCTAssertLessThanOrEqual(maxStep(main, channel: 0), 1 / Float(HandoffEnvelope.fadeFrames) + 1e-6)
    }

    func testHandoffResetKeepsProjectMsRingEmptiesTheTapAndAdvancesTheGeneration() {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: 22_050)
        writeLevel(ring, 0.5, frames: 441)
        let generation = ring.analysisSessionGeneration
        ring.beginFadeOut()
        ring.completeFadeOut()
        ring.resetForHandoff()
        XCTAssertEqual(ring.analysisSessionGeneration, generation + 1)
        let tap = readAllTap(ring)
        XCTAssertEqual(tap.count, HandoffEnvelope.silenceFrames * 2, "the tap holds only the new session's silence")
        XCTAssertTrue(tap.allSatisfy { $0 == 0 })
        let main = readAllMain(ring)
        XCTAssertEqual(main.count, (441 + 1_024 + 1_024) * 2, "projectM keeps the faded tail, then the silence")
        XCTAssertEqual(main.first, 0.5)
    }

    func testFadeOutDuringFadeInContinuesFromTheCurrentPosition() {
        let ring = NormalizedPCMRing()
        ring.beginFadeOut()
        ring.completeFadeOut()
        ring.resetForHandoff()
        ring.beginFadeIn()
        writeLevel(ring, 0.5, frames: 1_000)
        XCTAssertEqual(ring.handoffEnvelope.position, 1_000)
        ring.beginFadeOut()   // a second switch while the first fades in
        writeLevel(ring, 0.5, frames: 2_000)
        XCTAssertEqual(ring.handoffPhase, .silent)
        let main = readAllMain(ring)
        XCTAssertLessThanOrEqual(maxStep(main, channel: 0), 0.5 / Float(HandoffEnvelope.fadeFrames) + 1e-6)
    }

    func testAPlainResetReturnsToUnity() {
        let ring = NormalizedPCMRing()
        ring.beginFadeOut()
        writeLevel(ring, 0.5, frames: 100)
        ring.reset()
        XCTAssertEqual(ring.handoffPhase, .unity)
        write(ring, stereo(0.5, frames: 10))
        XCTAssertEqual(Set(readAllMain(ring)), [0.5])
    }

    func testSanitizerRunsBeforeTheEnvelope() {
        let ring = NormalizedPCMRing()
        ring.beginFadeOut()
        var samples = stereo(0.5, frames: 10)
        samples[4] = .nan
        write(ring, samples)
        let main = readAllMain(ring)
        XCTAssertTrue(main.allSatisfy { $0.isFinite })
        XCTAssertEqual(main[4], 0)
        XCTAssertEqual(ring.sanitizedSampleCount, 1)
    }

    // MARK: - Analyzer (AUD-012-R9)

    func testTheAnalyzerSanitizesInputBeforeLevelsAndConversion() {
        let sink = PCMSink()
        let analyzer = AudioAnalyzer(sink: sink, analysisTapCapacityFrames: 4_096)
        analyzer.beginAttempt()
        analyzer.apply(.started)
        var samples = stereo(0.25, frames: 480)
        samples[100] = .nan
        samples[101] = .infinity
        let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)
        samples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
            sink.writeInterleaved(raw.baseAddress!, frames: 480, format: format)
        }
        let update = analyzer.step()
        XCTAssertEqual(update.levels.peakDBFS, -12.0412, accuracy: 0.01,
                       "the level is the real level, not the floor a NaN would give")
        XCTAssertEqual(analyzer.normalizedOutput.sanitizedSampleCount, 2)
        let main = readAllMain(analyzer.normalizedOutput)
        XCTAssertFalse(main.isEmpty)
        XCTAssertTrue(main.allSatisfy { $0.isFinite }, "the resampler never saw the NaN")
    }

    func testAHandoffAttemptFadesTheNewSourceInAfterTheSilence() {
        let sink = PCMSink()
        let analyzer = AudioAnalyzer(sink: sink, analysisTapCapacityFrames: 22_050)
        let format = AudioFormat(sampleRate: 44_100, channelCount: 2, isInterleaved: true, sampleType: .float32)
        func push(_ value: Float, frames: Int) {
            let samples = stereo(value, frames: frames)
            samples.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Void in
                sink.writeInterleaved(raw.baseAddress!, frames: frames, format: format)
            }
            analyzer.step()
        }
        analyzer.beginAttempt()
        analyzer.apply(.started)
        push(0.5, frames: 441)
        analyzer.beginHandoffFadeOut()
        push(0.5, frames: 441)
        XCTAssertFalse(analyzer.handoffFadeOutDone)
        analyzer.completeHandoffFadeOut()
        XCTAssertTrue(analyzer.handoffFadeOutDone)
        sink.reset()
        analyzer.beginAttempt(handoff: true)
        analyzer.apply(.started)
        for _ in 0..<11 { push(-0.5, frames: 441) }
        let main = readAllMain(analyzer.normalizedOutput)
        XCTAssertLessThanOrEqual(maxStep(main, channel: 0), 0.5 / 1_024 + 1e-6)
        XCTAssertEqual(main.last, -0.5)
        // Sample clock of the handoff: fade-out (441 with audio + ≤ 1,024 forced) + 1,024 silence +
        // 4,410 fade-in ≤ 300 ms.
        let handoffFrames = 441 + HandoffEnvelope.maxForcedFrames + HandoffEnvelope.silenceFrames + HandoffEnvelope.fadeFrames
        XCTAssertLessThanOrEqual(Double(handoffFrames) / NormalizedPCMRing.sampleRate, 0.300)
    }
}
