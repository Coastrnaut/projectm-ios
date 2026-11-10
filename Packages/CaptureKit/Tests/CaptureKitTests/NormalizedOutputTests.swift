// Task T061: CaptureManager's work queue feeds the Normalizer, and `normalizedOutput` yields
// Float32 interleaved stereo at 44.1 kHz (research R-05/R-06), using FakeAudioSource.
import XCTest
import AudioCore
@testable import CaptureKit

@MainActor
final class NormalizedOutputTests: XCTestCase {
    private lazy var fixture = Fixture()
    private var manager: CaptureManager { fixture.manager }
    private var capture: FakeAudioSource { fixture.capture }

    private func format(_ rate: Double, _ channels: Int) -> AudioFormat {
        AudioFormat(sampleRate: rate, channelCount: channels, isInterleaved: true, sampleType: .float32)
    }

    private func read(maxFrames: Int) -> [Float] {
        var out = [Float](repeating: .nan, count: maxFrames * 2)
        let n = out.withUnsafeMutableBufferPointer { manager.normalizedOutput.read(into: $0.baseAddress!, maxFrames: maxFrames) }
        return Array(out.prefix(n * 2))
    }

    func testStereo44100ReachesTheNormalizedOutput() async {
        await manager.select(.systemAppCapture)
        capture.pushAudio(amplitude: 0.5, frames: 441, format: format(44_100, 2))   // 10 ms
        manager.stepAnalysisForTesting()
        let out = read(maxFrames: 4_096)
        XCTAssertEqual(out.count, 441 * 2)
        XCTAssertEqual(Set(out), [0.5])
    }

    func testMonoIsDuplicatedAndTheFreshnessRuleApplies() async {
        await manager.select(.microphone)
        fixture.mic.pushAudio(amplitude: 0.25, frames: 4_410, format: format(44_100, 1))   // 100 ms
        manager.stepAnalysisForTesting()
        let out = read(maxFrames: 4_096)
        XCTAssertEqual(out.count, NormalizedPCMRing.freshnessFrames * 2, "a backlog over 50 ms is cut to 50 ms")
        XCTAssertEqual(Set(out), [0.25])
    }

    func testCapture48kHzIsResampledTo44100() async {
        await manager.select(.systemAppCapture)
        var frames = 0
        for _ in 0..<50 {                                     // 0.5 s in 10 ms buffers
            capture.pushAudio(amplitude: 0.5, seconds: 0.01)  // 480 frames at 48 kHz, stereo
            manager.stepAnalysisForTesting()
            frames += read(maxFrames: 4_096).count / 2
        }
        // 0.5 s at 44.1 kHz is 22,050 frames, less the resampler's latency.
        XCTAssertGreaterThan(frames, 21_000)
        XCTAssertLessThanOrEqual(frames, 22_050)
        let last = read(maxFrames: 4_096)
        XCTAssertTrue(last.isEmpty, "everything was read")
        capture.pushAudio(amplitude: 0.5, seconds: 0.01)
        manager.stepAnalysisForTesting()
        let settled = read(maxFrames: 4_096)
        XCTAssertFalse(settled.isEmpty)
        XCTAssertEqual(settled.max() ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(settled.min() ?? 0, 0.5, accuracy: 0.01)
    }

    func testANewAttemptEmptiesTheOutput() async {
        await manager.select(.systemAppCapture)
        capture.pushAudio(amplitude: 0.5, frames: 441, format: format(44_100, 2))
        manager.stepAnalysisForTesting()
        await manager.stop()
        await manager.select(.systemAppCapture)
        XCTAssertEqual(read(maxFrames: 4_096), [])
    }

    func testUnconvertibleFormatStopsTheSourceWithAnError() async {
        await manager.select(.systemAppCapture)
        capture.pushAudio(amplitude: 0.5, frames: 100, format: format(1_000, 2))    // below 8 kHz
        manager.stepAnalysisForTesting()
        for _ in 0..<50 where manager.state != .stopped { await Task.yield(); try? await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(manager.state, .stopped)
        guard case .error = manager.stopReason else { return XCTFail("expected an error, got \(String(describing: manager.stopReason))") }
        XCTAssertNotNil(manager.stopDetail)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(read(maxFrames: 16), [])
    }

    #if canImport(AVFAudio) && !AUDIOCORE_NO_AVFAUDIO
    func testFiveOneWithALayoutIsDownmixed() async {
        await manager.select(.systemAppCapture)
        // 5.1 with only the center channel carrying signal: the standard downmix reaches L and R.
        let frames = 441
        var samples = [Float](repeating: 0, count: frames * 6)
        for f in 0..<frames { samples[f * 6 + 2] = 0.5 }
        let f6 = format(44_100, 6)
        for _ in 0..<5 {
            fixture.capture.pushInterleaved(samples, frames: frames, format: f6, layout: .mpeg5_1A)
            manager.stepAnalysisForTesting()
        }
        let out = read(maxFrames: 4_096)
        XCTAssertFalse(out.isEmpty)
        let l = stride(from: 0, to: out.count, by: 2).map { out[$0] }
        let r = stride(from: 1, to: out.count, by: 2).map { out[$0] }
        XCTAssertGreaterThan(l.last ?? 0, 0.1)
        XCTAssertEqual(l.last ?? 0, r.last ?? 1, accuracy: 0.001)
    }
    #endif
}
