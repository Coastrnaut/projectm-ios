// SourceSwitchTests.swift — AUD-012: mid-session source switch with a bounded handoff
// (specs/092-aud-012-source-crossfade, contracts/source-handoff.md C2-C4; User Stories 1-3).
//
// A harness with FakeAudioSource: the sources write constant levels (or NaN/±Inf), the test drives
// the analysis passes and reads projectM's ring in order (`readAll`, no freshness skip) and the
// analysis tap after every pass, so it sees every sample the renderer and the analysis could get.
// Times are on the sample clock; nothing asserts wall-clock time.
import XCTest
@testable import AudioCore
@testable import CaptureKit

@MainActor
final class SourceSwitchTests: XCTestCase {
    private lazy var clock = ManualClock()
    private lazy var capture = FakeAudioSource(mode: .systemAppCapture)
    private lazy var mic = FakeAudioSource(mode: .microphone)
    private lazy var inApp = FakeAudioSource(mode: .inAppPlayback)
    private lazy var manager: CaptureManager = {
        let clock = self.clock
        let made = CaptureManager(sources: [capture, mic, inApp], runsAnalysisTimer: false, clock: { clock.now },
                                  analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        made.handoffTiming = .immediate
        return made
    }()
    /// Everything read from projectM's ring and the tap, in order.
    private var mainStream: [Float] = []
    private var tapStream: [Float] = []

    private func format(_ rate: Double) -> AudioFormat {
        AudioFormat(sampleRate: rate, channelCount: 2, isInterleaved: true, sampleType: .float32)
    }

    /// The indicator's source part as the app shows it (C3).
    private var label: String {
        if manager.switchingTo != nil { return "switching" }
        return manager.activeMode?.rawValue ?? "none"
    }

    private func drainRings() {
        let ring = manager.analyzerForTesting.normalizedOutput
        var buffer = [Float](repeating: .nan, count: NormalizedPCMRing.capacityFrames * 2)
        let mainFrames = buffer.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
            ring.readAll(into: b.baseAddress!, maxFrames: NormalizedPCMRing.capacityFrames)
        }
        mainStream += buffer.prefix(mainFrames * 2)
        if let tap = ring.analysisTap {
            let tapFrames = buffer.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                tap.read(into: b.baseAddress!, maxFrames: NormalizedPCMRing.capacityFrames)
            }
            tapStream += buffer.prefix(tapFrames * 2)
        }
    }

    /// Pushes `buffers` 10 ms buffers of `level` at 44.1 kHz from `source`, one analysis pass each.
    private func deliver(_ source: FakeAudioSource, _ level: Float, buffers: Int = 1) {
        for _ in 0..<buffers {
            source.pushAudio(amplitude: level, frames: 441, format: format(44_100))
            manager.stepAnalysisForTesting()
            drainRings()
        }
    }

    private func maxStep(_ samples: [Float]) -> Float {
        var largest: Float = 0
        var i = 2
        while i < samples.count {
            let step: Float = abs(samples[i] - samples[i - 2])
            largest = max(largest, step)
            i += 1
        }
        return largest
    }

    private func longestZeroRunFrames(_ samples: [Float]) -> Int {
        var best = 0
        var run = 0
        var i = 0
        while i + 1 < samples.count {
            if samples[i] == 0 && samples[i + 1] == 0 { run += 1; best = max(best, run) } else { run = 0 }
            i += 2
        }
        return best
    }

    private func assertAllFiniteAndBounded(_ samples: [Float], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let bad = samples.filter { !$0.isFinite || abs($0) > PCMSanitizer.bound }.count
        XCTAssertEqual(bad, 0, "\(what): \(bad) non-finite or out-of-bound samples", file: file, line: line)
    }

    // MARK: - User Story 1: the switch and its label (C2, C3)

    func testSwitchAToBStopsAFirstAndTheLabelGoesAThenSwitchingThenB() async {
        var labels: [String] = []
        await manager.select(.systemAppCapture)
        deliver(capture, 0.5)
        labels.append(label)
        var aRunningDuringBStart = true
        mic.onStart = { [unowned self] in
            labels.append(self.label)
            aRunningDuringBStart = self.capture.isRunning
        }
        await manager.switchSource(to: .microphone)
        labels.append(label)
        XCTAssertFalse(aRunningDuringBStart, "FR-016: A stopped before B started")
        XCTAssertTrue(mic.isRunning)
        XCTAssertEqual([capture, mic, inApp].filter(\.isRunning).count, 1, "FR-001")
        XCTAssertEqual(manager.activeMode, .microphone)
        deliver(mic, -0.5)
        labels.append(label)
        XCTAssertEqual(labels, ["systemAppCapture", "switching", "switching", "microphone"])
    }

    func testSwitchBToAAlsoHandsOff() async {
        await manager.select(.microphone)
        deliver(mic, -0.5, buffers: 2)
        await manager.switchSource(to: .systemAppCapture)
        XCTAssertEqual(label, "switching")
        deliver(capture, 0.5, buffers: 12)
        XCTAssertEqual(label, "systemAppCapture")
        XCTAssertEqual(mainStream.last, 0.5)
        XCTAssertLessThanOrEqual(maxStep(mainStream), 0.5 / Float(HandoffEnvelope.maxForcedFrames) + 1e-6)
    }

    func testSwitchingToTheRunningSourceDoesNothing() async {
        await manager.select(.systemAppCapture)
        await manager.switchSource(to: .systemAppCapture)
        XCTAssertNil(manager.switchingTo)
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 0)
    }

    func testSelectStopAndRestartNeverShowTheSwitchingLabel() async {
        await manager.select(.systemAppCapture)
        XCTAssertNil(manager.switchingTo)
        await manager.select(.microphone)
        XCTAssertNil(manager.switchingTo)
        await manager.restart()
        XCTAssertNil(manager.switchingTo)
        await manager.stop()
        XCTAssertNil(manager.switchingTo)
        XCTAssertEqual(manager.analyzerForTesting.normalizedOutput.handoffPhase, .unity, "no fade outside a switch")
    }

    func testAFailedStartOfTheTargetShowsTheTargetWithItsFailure() async {
        await manager.select(.systemAppCapture)
        mic.startError = SourceError(.permissionDenied)
        await manager.switchSource(to: .microphone)
        XCTAssertNil(manager.switchingTo)
        XCTAssertEqual(manager.activeMode, .microphone)
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertEqual(manager.stopReason, .permissionDenied)
        XCTAssertFalse(capture.isRunning)
    }

    func testADecidedStateEndsTheLabelWhenNoAudioComes() async {
        await manager.select(.systemAppCapture)
        await manager.switchSource(to: .microphone)
        XCTAssertEqual(label, "switching")
        clock.advance(6)   // past the 5 s no-audio timeout (FR-012)
        manager.stepAnalysisForTesting()
        XCTAssertEqual(manager.state, .noAudioReceived)
        XCTAssertEqual(label, "microphone")
    }

    func testTheSessionModeCallbackFollowsTheSwitchPoint() async {
        var modes: [AudioSourceMode] = []
        manager.onSessionMode = { (mode: AudioSourceMode) in modes.append(mode) }
        await manager.select(.microphone)
        mic.onStart = nil
        await manager.switchSource(to: .inAppPlayback)
        XCTAssertEqual(modes, [.microphone, .inAppPlayback])
    }

    // MARK: - User Story 2: the boundary (S1-S3, S5, S6)

    func testAConstantLevelSwitchIsBoundedReachesZeroAndFitsTheHandoffBound() async {
        await manager.select(.systemAppCapture)
        deliver(capture, 0.5, buffers: 3)
        await manager.switchSource(to: .microphone)
        deliver(mic, -0.5, buffers: 12)
        assertAllFiniteAndBounded(mainStream, "projectM's ring")
        XCTAssertLessThanOrEqual(maxStep(mainStream), 0.5 / Float(HandoffEnvelope.maxForcedFrames) + 1e-6,
                                 "the ramp bound (forced fade-out from 0.5)")
        XCTAssertGreaterThanOrEqual(longestZeroRunFrames(mainStream), HandoffEnvelope.silenceFrames, "exact silence between the sources")
        // Sample clock from A's last full-level frame to B's first full-level frame.
        let frames = mainStream.count / 2
        let lastA = (0..<frames).last { mainStream[2 * $0] == 0.5 } ?? 0
        let firstB = (0..<frames).first { mainStream[2 * $0] == -0.5 } ?? frames
        let handoffSeconds = Double(firstB - lastA) / NormalizedPCMRing.sampleRate
        XCTAssertLessThanOrEqual(handoffSeconds, 0.300, "AUD-012-R6")
        XCTAssertEqual(mainStream.last, -0.5)
    }

    func testTheFadeOutFollowsTheOldSourcesAudioWhenItKeepsDelivering() async {
        manager.handoffTiming = HandoffTiming(fadeOutWaitLimit: .seconds(5), pollInterval: .milliseconds(1))
        await manager.select(.systemAppCapture)
        deliver(capture, 0.5, buffers: 2)
        let switching = Task { @MainActor in await self.manager.switchSource(to: .microphone) }
        var buffers = 0
        while !mic.isRunning && buffers < 40 {   // the old source keeps delivering 10 ms buffers
            deliver(capture, 0.5)
            buffers += 1
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        await switching.value
        XCTAssertTrue(mic.isRunning)
        XCTAssertGreaterThanOrEqual(buffers, HandoffEnvelope.fadeFrames / 441, "the fade-out used delivered audio")
        deliver(mic, -0.5, buffers: 12)
        XCTAssertLessThanOrEqual(maxStep(mainStream), 0.5 / Float(HandoffEnvelope.fadeFrames) + 1e-6,
                                 "a fade with audio steps by at most a / 4,410")
        XCTAssertEqual(mainStream.last, -0.5)
    }

    func testNaNAndInfinityNeverReachTheRingsAcrossABAndBA() async {
        var injected = 0
        func dirty(_ source: FakeAudioSource, rate: Double, includeHuge: Bool) {
            let frames = rate == 44_100 ? 441 : 480
            var samples = [Float](repeating: 0.25, count: frames * 2)
            samples[3] = .nan
            samples[40] = .infinity
            samples[41] = -.infinity
            injected += 3
            if includeHuge {   // finite overs are counted exactly only without the resampler
                samples[100] = 50
                samples[101] = -1e30
                injected += 2
            }
            source.pushInterleaved(samples, frames: frames, format: format(rate))
            manager.stepAnalysisForTesting()
            drainRings()
        }
        await manager.select(.systemAppCapture)
        dirty(capture, rate: 44_100, includeHuge: true)
        dirty(capture, rate: 48_000, includeHuge: false)
        await manager.switchSource(to: .microphone)
        dirty(mic, rate: 48_000, includeHuge: false)
        dirty(mic, rate: 44_100, includeHuge: true)
        await manager.switchSource(to: .systemAppCapture)
        dirty(capture, rate: 44_100, includeHuge: true)
        for _ in 0..<5 { dirty(capture, rate: 48_000, includeHuge: false) }
        assertAllFiniteAndBounded(mainStream, "projectM's ring")
        assertAllFiniteAndBounded(tapStream, "the analysis tap")
        XCTAssertEqual(manager.sanitizedSampleCount, injected, "every injected bad sample counted once")
        XCTAssertGreaterThan(manager.levels.peakDBFS, -20, "levels come from the sanitized audio, not a NaN floor")
    }

    func testNoFrameOfTheOldSessionReachesTheTapAfterTheSwitchPoint() async {
        await manager.select(.systemAppCapture)
        capture.pushAudio(amplitude: 0.5, frames: 441, format: format(44_100))
        manager.stepAnalysisForTesting()   // A's frames sit unread in the tap
        let ring = manager.analyzerForTesting.normalizedOutput
        let before = ring.analysisSessionGeneration
        await manager.switchSource(to: .microphone)
        XCTAssertEqual(ring.analysisSessionGeneration, before + 1)
        deliver(mic, -0.5, buffers: 12)
        XCTAssertFalse(tapStream.isEmpty)
        XCTAssertEqual(tapStream.filter { $0 > 0 }.count, 0, "C4: no A (positive) frame after the switch point")
        XCTAssertEqual(tapStream.last, -0.5)
    }

    // MARK: - User Story 3: Stop, rapid switching (AUD-012-R11)

    func testStopDuringTheFadeOutStopsTheOldSourceAndStartsNothing() async {
        manager.handoffTiming = HandoffTiming(fadeOutWaitLimit: .seconds(5), pollInterval: .milliseconds(1))
        await manager.select(.systemAppCapture)
        deliver(capture, 0.5)
        let switching = Task { @MainActor in await self.manager.switchSource(to: .microphone) }
        while manager.switchingTo == nil { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(10))   // inside the fade-out wait
        await manager.stop()
        await switching.value
        XCTAssertNil(manager.switchingTo)
        XCTAssertEqual(mic.startCount, 0)
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(manager.state, .stopped)
    }

    func testASecondSwitchSupersedesAHeldStartAndTheGainNeverJumps() async {
        await manager.select(.systemAppCapture)
        deliver(capture, 0.5, buffers: 2)
        mic.holdsStart = true   // B's start waits like a permission prompt
        let first = Task { @MainActor in await self.manager.switchSource(to: .microphone) }
        while !mic.isHoldingStart { await Task.yield() }
        XCTAssertEqual(label, "switching")
        await manager.switchSource(to: .inAppPlayback)
        await first.value
        XCTAssertFalse(mic.isRunning, "B never runs")
        XCTAssertTrue(inApp.isRunning)
        XCTAssertEqual([capture, mic, inApp].filter(\.isRunning).count, 1)
        XCTAssertEqual(label, "switching")
        deliver(inApp, -0.25, buffers: 12)
        XCTAssertEqual(label, "inAppPlayback")
        assertAllFiniteAndBounded(mainStream, "projectM's ring")
        XCTAssertLessThanOrEqual(maxStep(mainStream), 0.5 / Float(HandoffEnvelope.maxForcedFrames) + 1e-6)
        XCTAssertEqual(mainStream.last, -0.25)
    }

    func testSwitchingBackDuringAFadeInContinuesTheGain() async {
        await manager.select(.systemAppCapture)
        deliver(capture, 0.5, buffers: 2)
        await manager.switchSource(to: .microphone)
        deliver(mic, -0.5, buffers: 3)   // part of the fade-in
        XCTAssertEqual(manager.analyzerForTesting.normalizedOutput.handoffPhase, .fadingIn)
        await manager.switchSource(to: .systemAppCapture)
        deliver(capture, 0.5, buffers: 12)
        XCTAssertEqual(label, "systemAppCapture")
        assertAllFiniteAndBounded(mainStream, "projectM's ring")
        XCTAssertLessThanOrEqual(maxStep(mainStream), 0.5 / Float(HandoffEnvelope.maxForcedFrames) + 1e-6)
        XCTAssertEqual(mainStream.last, 0.5)
    }
}
