// PRE-009-T06: the acceptance test of roadmap PRE-009 ("Both previews respond to identical sample timestamps";
// spec PRE-009-S1-S3, contract C2). Real engines off screen on the iOS Simulator's GPU. The recorder captures, per
// drawn batch and per engine, the tick range, frame time, sample range and sample checksum right before that
// engine is fed. The presets are written here (no third-party file); they have no custom shaders, so the
// simulator compiles them quickly. Simulator results are not device evidence (Constitution X).
import XCTest
import Rendering
@testable import ANGLERendering

@MainActor
final class PresetComparisonRunnerTests: XCTestCase {
    private func preset(_ red: Double) -> Data {
        Data("""
        MILKDROP_PRESET_VERSION=201
        [preset00]
        fDecay=0.970000
        zoom=1.010000
        wave_r=\(red)
        wave_g=0.6
        wave_b=0.3
        nWaveMode=2
        fWaveAlpha=1.0
        fWaveScale=2.0
        per_frame_1=wave_g = 0.5 + 0.4*sin(time*2.1);

        """.utf8)
    }

    /// One tick of a 110 Hz tone (1 470 frames, a 30 fps tick at 44.1 kHz), distinct per tick.
    private func block(_ tick: Int) -> [Float] {
        (0..<1_470).flatMap { (index: Int) -> [Float] in
            let value = Float(0.6 * sin(Double(tick * 1_470 + index) * 2 * .pi * 110 / 44_100))
            return [value, -value]
        }
    }

    /// Events from the worker thread.
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [PresetComparisonEvent] = []
        func add(_ event: PresetComparisonEvent) { lock.lock(); list.append(event); lock.unlock() }
        var frames: [PresetComparisonFrame] {
            lock.lock(); defer { lock.unlock() }
            return list.compactMap { (event: PresetComparisonEvent) -> PresetComparisonFrame? in
                if case .frame(let frame) = event { return frame }
                return nil
            }
        }
        var failures: [String] {
            lock.lock(); defer { lock.unlock() }
            return list.compactMap { (event: PresetComparisonEvent) -> String? in
                if case .failed(_, let message) = event { return message }
                return nil
            }
        }
    }

    /// Polls (no wall-clock assertion: the limit only ends a hung run).
    private func waitUntil(_ limit: Duration = .seconds(120), _ done: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while !done() && clock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    /// S1, S2: 30 paced ticks give 30 batches; then B is made slow and 20 ticks arrive at once, so batches merge and
    /// the mailbox drops the oldest. Throughout, A and B receive identical records, and no sample reaches twice.
    func testBothPreviewsReceiveIdenticalSampleRangesAndFrameTimesAlsoWhenOneIsSlow() async throws {
        let renderer = try ANGLERenderer.make()
        let runner = renderer.comparisonRunner
        let recorder = PresetComparisonRecorder()
        runner.recorder = recorder
        let events = Events()
        var timeline = PresetComparisonTimeline(rate: 30)
        let configuration = PresetComparisonConfiguration(width: 64, height: 36)
        XCTAssertTrue(runner.start(preset(1.0), preset(0.2), configuration: configuration) { events.add($0) })

        for tick in 0..<30 {   // paced: each tick is drawn before the next is posted
            runner.submit(timeline.stamp(block(tick)))
            await waitUntil { recorder.deliveries(.b).last?.lastTick == tick }
        }
        let paced = recorder.deliveries(.a)
        XCTAssertEqual(paced.count, 30, "one batch per tick when the worker keeps up")
        XCTAssertEqual(paced, recorder.deliveries(.b))

        runner.slowSide = (.b, 0.08)   // B is now the slow preview
        for tick in 30..<50 { runner.submit(timeline.stamp(block(tick))) }
        await waitUntil { recorder.deliveries(.b).last?.lastTick == 49 }
        runner.stop()
        XCTAssertFalse(runner.isBusy)

        let a = recorder.deliveries(.a)
        let b = recorder.deliveries(.b)
        XCTAssertEqual(a, b, "both engines received the identical sequence of sample ranges, checksums and frame times")
        XCTAssertEqual(a.last?.lastTick, 49)
        let slow = Array(a.dropFirst(30))
        XCTAssertLessThan(slow.count, 20, "batches merged while B was slow")
        XCTAssertTrue(slow.contains { $0.lastTick > $0.firstTick }, "at least one batch carries several ticks")
        for (earlier, later) in zip(a, a.dropFirst()) {   // contiguous order, nothing twice, frame time = last tick / rate
            XCTAssertEqual(later.firstSample, Int64(later.firstTick) * 1_470)
            XCTAssertGreaterThanOrEqual(later.firstSample, earlier.firstSample + Int64(earlier.frameCount))
            XCTAssertGreaterThan(later.firstTick, earlier.lastTick)
        }
        for delivery in a {
            XCTAssertEqual(delivery.frameTime, Double(delivery.lastTick) / 30, accuracy: 1e-9)
            XCTAssertEqual(delivery.frameCount, (delivery.lastTick - delivery.firstTick + 1) * 1_470)
        }
        XCTAssertEqual(events.frames.count, a.count, "one picture pair per batch")
        XCTAssertTrue(events.failures.isEmpty, "\(events.failures)")
    }

    /// S3: the same preset as A and B, fed and timed identically, draws pixel-identical frames. A suspended runner
    /// starts nothing (PERF-011).
    func testTheSamePresetAsAAndBGivesIdenticalPictures() async throws {
        let renderer = try ANGLERenderer.make()
        let runner = renderer.comparisonRunner
        let events = Events()
        var timeline = PresetComparisonTimeline(rate: 30)
        XCTAssertTrue(runner.start(preset(0.9), preset(0.9), configuration: PresetComparisonConfiguration(width: 48, height: 27)) { events.add($0) })
        for tick in 0..<6 {
            runner.submit(timeline.stamp(block(tick)))
            await waitUntil { events.frames.last?.delivery.lastTick == tick }
        }
        runner.stop()
        let frames = events.frames
        XCTAssertEqual(frames.count, 6)
        for frame in frames {
            let a = try XCTUnwrap(frame.a)
            XCTAssertEqual(a.count, 48 * 27 * 4)
            XCTAssertEqual(a, frame.b, "batch \(frame.delivery.firstTick): identical input and time, identical picture")
        }
        let last = [UInt8](try XCTUnwrap(frames.last?.a))
        XCTAssertTrue(stride(from: 0, to: last.count, by: 4).contains { last[$0] > 8 || last[$0 + 1] > 8 || last[$0 + 2] > 8 },
                      "the preview drew something")

        runner.setSuspended(true)
        XCTAssertFalse(runner.start(preset(0.9), preset(0.9), configuration: PresetComparisonConfiguration()) { _ in })
        XCTAssertEqual(runner.startedCount, 1)
    }
}
