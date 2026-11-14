// PlaybackBalanceTests.swift — AUD-010-T06: the monitoring balance changes what is heard and never
// what the analysis reads (AUD-010-R2 to R5, S1, S2; roadmap acceptance "Pan test track and verify
// analysis remains sourced from original PCM").
//
// The fixture is a stereo track with a different tone in each channel (440 Hz at 0.5 on the left,
// 1 kHz at 0.25 on the right), played through the production graph in AVAudioEngine's offline manual
// rendering mode, so every run is deterministic and nothing waits for real time. Each run collects
// two streams: what reached the PCM sink (the analysis input, tapped on the main mixer) and what the
// output rendered (what is heard, after the balance node). Routes, Bluetooth and interruptions on a
// real device are AUD-010-T16 {device}.
#if canImport(AVFAudio)
import AudioCore
import AVFAudio
import Foundation
import XCTest
@testable import CaptureKit

@MainActor
final class PlaybackBalanceTests: XCTestCase {
    private final class Counter: @unchecked Sendable { var value = 0 }

    private static let rate: Double = 48_000
    private static let leftAmplitude: Float = 0.5
    private static let rightAmplitude: Float = 0.25
    /// RMS of each fixture channel (a sine's RMS is amplitude / √2).
    private static let leftRMS: Float = leftAmplitude / 2.0.squareRoot().float
    private static let rightRMS: Float = rightAmplitude / 2.0.squareRoot().float

    private var root: URL!

    override func setUp() async throws {
        root = try AudioFixtures.makeTemporaryDirectory("aud010-balance")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Fixture and rig

    /// 1 s, 48 kHz, Float32 stereo: 440 Hz on the left, 1 kHz on the right. Synthesized here.
    private func stereoTones(_ name: String = "tones.caf") throws -> URL {
        let url = root.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.rate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames = Int(Self.rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
              let data = buffer.floatChannelData else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            let t = Double(frame) / Self.rate
            data[0][frame] = Self.leftAmplitude * Float(sin(2 * Double.pi * 440 * t))
            data[1][frame] = Self.rightAmplitude * Float(sin(2 * Double.pi * 1_000 * t))
        }
        try file.write(from: buffer)
        return url
    }

    private struct Run {
        var analysis: [Float] = []          // interleaved stereo, what reached the sink
        var heardLeft: [Float] = []
        var heardRight: [Float] = []

        /// RMS of the heard channels from `skip` frames on (past the player's start).
        func heardRMS(skip: Int = 4_096) -> (left: Float, right: Float) {
            (Self.rms(heardLeft.dropFirst(skip)), Self.rms(heardRight.dropFirst(skip)))
        }

        static func rms(_ samples: ArraySlice<Float>) -> Float {
            guard !samples.isEmpty else { return 0 }
            let sum: Float = samples.reduce(0) { $0 + $1 * $1 }
            return (sum / Float(samples.count)).squareRoot()
        }
    }

    private func appendOutput(_ buffer: AVAudioPCMBuffer?, to run: inout Run) {
        guard let buffer, let data = buffer.floatChannelData, buffer.format.channelCount == 2 else { return }
        let count = Int(buffer.frameLength)
        run.heardLeft.append(contentsOf: UnsafeBufferPointer(start: data[0], count: count))
        run.heardRight.append(contentsOf: UnsafeBufferPointer(start: data[1], count: count))
    }

    /// Renders `renders` × 1,024 frames with `render`, then lets the tap hand over its last block.
    private func pump(_ run: inout Run, sink: PCMSink, renders: Int,
                      render: (AVAudioFrameCount) throws -> AVAudioPCMBuffer?) async throws {
        for _ in 0..<renders {
            appendOutput(try render(1024), to: &run)
            run.analysis += PlaybackProbe.drain(sink)
            try await Task.sleep(nanoseconds: 500_000)
        }
        var quiet = 0
        while quiet < 12 {
            try await Task.sleep(nanoseconds: 5_000_000)
            let more = PlaybackProbe.drain(sink)
            if more.isEmpty { quiet += 1 } else { quiet = 0; run.analysis += more }
        }
    }

    /// Plays the fixture through a fresh graph at `balance` for 0.64 s.
    private func play(balance: Double, url: URL) async throws -> Run {
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(url), bundle: .main))
        graph.loops = true
        graph.monitorBalance = balance          // before the graph is wired: applied when it is
        try graph.enableOfflineRendering(sampleRate: Self.rate, maximumFrameCount: 1024)
        let sink = PCMSink()
        try graph.installTap(into: sink)
        try graph.start()
        defer { graph.stop() }
        var run = Run()
        try await pump(&run, sink: sink, renders: 30) { try graph.renderOfflineOutput(frames: $0) }
        return run
    }

    private func assertHeard(_ run: Run, balance: Double, file: StaticString = #filePath, line: UInt = #line) {
        let gains = MonitorBalance.gains(balance)
        let rms = run.heardRMS()
        let expectedLeft = Self.leftRMS * gains.left
        let expectedRight = Self.rightRMS * gains.right
        // S2: within 1 % (plus a floor for a silenced channel).
        XCTAssertEqual(rms.left, expectedLeft, accuracy: max(expectedLeft * 0.01, 1e-4), "heard left at \(balance)", file: file, line: line)
        XCTAssertEqual(rms.right, expectedRight, accuracy: max(expectedRight * 0.01, 1e-4), "heard right at \(balance)", file: file, line: line)
    }

    // MARK: Acceptance (S1, S2)

    /// The roadmap acceptance: fully left and fully right change what is heard as the law says, and
    /// the analysis receives exactly the PCM it receives at centre.
    func testPanningLeftAndRightLeavesTheAnalysisPCMUnchanged() async throws {
        let url = try stereoTones()
        let centre = try await play(balance: 0, url: url)
        let left = try await play(balance: -1, url: url)
        let right = try await play(balance: 1, url: url)

        // At least 0.4 s of analysis audio in every run.
        let minimum = 2 * Int(0.4 * Self.rate)
        for run in [centre, left, right] {
            XCTAssertGreaterThanOrEqual(run.analysis.count, minimum, "the tap delivered the run")
        }
        for (name, run) in [("left", left), ("right", right)] {
            let count = min(run.analysis.count, centre.analysis.count)
            var maxDifference: Float = 0
            for index in 0..<count { maxDifference = max(maxDifference, abs(run.analysis[index] - centre.analysis[index])) }
            XCTAssertLessThanOrEqual(maxDifference, 1e-6, "analysis PCM at balance \(name) equals the centre run (S1)")
        }
        // The analysis copy stays stereo and unbalanced: both tones at full level even when the
        // listener hears only one side.
        let leftAnalysis = stride(from: 8_192, to: left.analysis.count, by: 2).map { left.analysis[$0] }
        let rightAnalysis = stride(from: 8_193, to: left.analysis.count, by: 2).map { left.analysis[$0] }
        XCTAssertEqual(Run.rms(leftAnalysis[...]), Self.leftRMS, accuracy: Self.leftRMS * 0.01)
        XCTAssertEqual(Run.rms(rightAnalysis[...]), Self.rightRMS, accuracy: Self.rightRMS * 0.01)

        assertHeard(centre, balance: 0)
        assertHeard(left, balance: -1)
        assertHeard(right, balance: 1)
    }

    /// S2 at the two intermediate points of the law (the ends and centre are above).
    func testHalfBalancesFollowTheLaw() async throws {
        let url = try stereoTones()
        for balance in [-0.5, 0.5] {
            let run = try await play(balance: balance, url: url)
            assertHeard(run, balance: balance)
        }
    }

    // MARK: R4: a change while playing

    func testChangeWhilePlayingNeitherCutsNorDiscardsAndTakesEffect() async throws {
        let graph = InAppPlaybackGraph(content: try InAppPlaybackGraph.load(.file(try stereoTones()), bundle: .main))
        graph.loops = false                     // one segment to the end: any reschedule would be a cut
        try graph.enableOfflineRendering(sampleRate: Self.rate, maximumFrameCount: 1024)
        let sink = PCMSink()
        let discards = Counter()
        sink.setDiscardHandler { discards.value += 1; sink.ring.drain() }
        try graph.installTap(into: sink)
        try graph.start()
        defer { graph.stop() }
        let schedules = graph.scheduleCount
        var before = Run()
        try await pump(&before, sink: sink, renders: 10) { try graph.renderOfflineOutput(frames: $0) }
        let discardsBefore = discards.value
        let position = graph.positionFrame

        graph.monitorBalance = -1
        XCTAssertEqual(graph.positionFrame, position, "a balance change keeps the position")
        var after = Run()
        try await pump(&after, sink: sink, renders: 10) { try graph.renderOfflineOutput(frames: $0) }

        XCTAssertEqual(discards.value, discardsBefore, "no discard: the analysis stream continues (AUD-006-R10 untouched)")
        XCTAssertEqual(graph.scheduleCount, schedules, "nothing was rescheduled (no cut)")
        XCTAssertEqual(graph.positionFrame, position + 10_240, "playback continued from where it was")
        XCTAssertFalse(after.analysis.isEmpty, "the tap kept delivering")
        // The mixer ramps a parameter change over a few milliseconds; measure after the ramp.
        let rms = after.heardRMS(skip: 4_096)
        XCTAssertEqual(rms.left, Self.leftRMS, accuracy: Self.leftRMS * 0.01)
        XCTAssertEqual(rms.right, 0, accuracy: 1e-4, "the new balance is heard")
    }

    // MARK: R5: the backend keeps it across track changes, seeks and a rebuild

    func testBackendAppliesTheBalanceToEveryGraph() async throws {
        let center = NotificationCenter()
        let backend = AVInAppPlaybackBackend(offlineSampleRate: Self.rate, notificationCenter: center)
        backend.setMonitorBalance(-1)                     // before start
        let sink = PCMSink()
        try backend.start(track: .file(try stereoTones()), sink: sink) { _ in }
        defer { backend.stop() }

        func heard() async throws -> (left: Float, right: Float) {
            var run = Run()
            try await pump(&run, sink: sink, renders: 8) { try backend.renderOfflineOutput(frames: $0) }
            return run.heardRMS(skip: 2_048)
        }
        var rms = try await heard()
        XCTAssertEqual(rms.right, 0, accuracy: 1e-4, "applied to the first graph")
        XCTAssertGreaterThan(rms.left, Self.leftRMS * 0.9)

        try backend.replaceTrack(.file(try stereoTones("second.caf")))
        rms = try await heard()
        XCTAssertEqual(rms.right, 0, accuracy: 1e-4, "kept across a track change")

        backend.seek(to: 0.5)
        rms = try await heard()
        XCTAssertEqual(rms.right, 0, accuracy: 1e-4, "kept across a seek")

        backend.handle(.mediaServicesReset)               // AUD-014: a new graph
        XCTAssertEqual(backend.recoveryCount, 1)
        rms = try await heard()
        XCTAssertEqual(rms.right, 0, accuracy: 1e-4, "kept in the rebuilt graph")
        XCTAssertGreaterThan(rms.left, Self.leftRMS * 0.9, "and the rebuilt graph plays")

        backend.setMonitorBalance(0.5)                    // a change on the rebuilt graph
        rms = try await heard()
        XCTAssertEqual(rms.left, Self.leftRMS * 0.5, accuracy: Self.leftRMS * 0.01)
        XCTAssertEqual(rms.right, Self.rightRMS, accuracy: Self.rightRMS * 0.01)
    }

    // MARK: The source forwards validated values

    private final class RecordingBackend: InAppPlaybackBackend {
        var balances: [Double] = []
        var loopsCurrentTrack = true
        var onTrackEnded: (@MainActor () -> Void)?
        var position: PlaybackPosition { .zero }
        func start(track: InAppPlaybackTrack, sink: PCMSink, onEvent: @escaping @Sendable (SourceEvent) -> Void) throws {}
        func stop() {}
        func pause() {}
        func resume() throws {}
        func seek(to seconds: Double) {}
        func replaceTrack(_ track: InAppPlaybackTrack) throws {}
        func setMonitorBalance(_ balance: Double) { balances.append(balance) }
    }

    func testSourceForwardsValidatedBalance() {
        let backend = RecordingBackend()
        let source = InAppPlaybackSource(backend: backend)
        XCTAssertEqual(source.monitorBalance, 0)
        source.monitorBalance = -0.3
        source.monitorBalance = 7
        source.monitorBalance = .nan
        source.monitorBalance = 0.02
        XCTAssertEqual(backend.balances, [-0.3, 1, 0, 0])
        XCTAssertEqual(source.monitorBalance, 0, "the stored value is the validated one")
    }
}

private extension Double {
    var float: Float { Float(self) }
}
#endif
