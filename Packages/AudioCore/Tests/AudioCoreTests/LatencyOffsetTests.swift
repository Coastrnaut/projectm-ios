// LatencyOffsetTests.swift — AUD-013-T02: the visual delay's law on the sample clock
// (specs/095-aud-013-source-latency-calibration, contracts/latency-delay.md C1-C3; research
// AUD-013-D1 to D5). Each fixture frame carries its own index (L = R = index), so a released frame
// shows exactly when it entered. Arrivals are 441 frames (10 ms at 44.1 kHz); no wall clock.
import AudioCore
import XCTest

/// Writes index-valued stereo frames into a ring (main ring and analysis tap).
private final class IndexFeed {
    let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
    private(set) var next: Int
    private var buffer: [Float] = []

    init(start: Int = 0) { next = start }

    func arrive(_ frames: Int) {
        let count: Int = frames * NormalizedPCMRing.channelCount
        if buffer.count < count { buffer = [Float](repeating: 0, count: count) }
        for i in 0..<frames {
            let value: Float = Float(next + i)
            buffer[2 * i] = value
            buffer[2 * i + 1] = value
        }
        buffer.withUnsafeBufferPointer { (p: UnsafeBufferPointer<Float>) -> Void in
            ring.write(p.baseAddress!, frames: frames)
        }
        next += frames
    }

    /// Continues the indices from `value` (a new session's content).
    func jump(to value: Int) { next = value }
}

/// Reads until the reader returns 0; returns the left channel of every frame read.
private func drain(_ reader: any NormalizedPCMReader, chunk: Int = 2_048) -> [Float] {
    var out: [Float] = []
    let scratch = UnsafeMutablePointer<Float>.allocate(capacity: chunk * 2)
    defer { scratch.deallocate() }
    while true {
        let n: Int = reader.read(into: scratch, maxFrames: chunk)
        if n == 0 { break }
        for i in 0..<n { out.append(scratch[2 * i]) }
    }
    return out
}

private let arrival = 441

/// Returns fixed samples, then 0 (not real-time: tests only).
private final class ArrayReader: NormalizedPCMReader, @unchecked Sendable {
    private let samples: [Float]
    private var offset = 0
    init(_ samples: [Float]) { self.samples = samples }
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let left: Int = (samples.count - offset) / 2
        let n: Int = min(left, maxFrames)
        for i in 0..<(2 * n) { dst[i] = samples[offset + i] }
        offset += 2 * n
        return n
    }
}

final class LatencyOffsetLawTests: XCTestCase {
    /// (a) Steady state: a frame leaves exactly `target` frames after it entered.
    func testSteadyStateDelayIsExactOnTheSampleClock() {
        let targets: [Int] = [0, 4_410, 11_025]
        for target in targets {
            let feed = IndexFeed()
            let control = LatencyOffsetControl(targetFrames: target)
            let reader = LatencyDelayReader(feed.ring.analysisTap!, control: control, mode: .analysis)
            var released: [Float] = []
            for _ in 0..<150 {   // 1.5 s
                feed.arrive(arrival)
                released += drain(reader)
                let expected: Int = max(0, feed.next - target)
                XCTAssertEqual(released.count, expected, "target \(target) after \(feed.next) frames")
            }
            for (i, value) in released.enumerated() where value != Float(i) {
                XCTFail("target \(target): frame \(i) carried \(value)")
                break
            }
            XCTAssertEqual(reader.appliedDelayFrames, target)
        }
    }

    /// (b) Bounds, conversion and clamping (S2).
    func testValidationConversionAndClamping() {
        XCTAssertEqual(LatencyOffset.validatedMilliseconds(400), 250)
        XCTAssertEqual(LatencyOffset.validatedMilliseconds(-50), 0)
        XCTAssertEqual(LatencyOffset.validatedMilliseconds(.nan), 0)
        XCTAssertEqual(LatencyOffset.validatedMilliseconds(.infinity), 250)
        XCTAssertEqual(LatencyOffset.validatedMilliseconds(12.4), 12)
        XCTAssertEqual(LatencyOffset.frames(milliseconds: 100), 4_410)
        XCTAssertEqual(LatencyOffset.frames(milliseconds: 250), LatencyOffset.maximumDelayFrames)
        XCTAssertEqual(LatencyOffset.frames(milliseconds: -100), 0)
        let control = LatencyOffsetControl(targetFrames: 99_999)
        XCTAssertEqual(control.targetFrames, 11_025)
        control.targetFrames = -5
        XCTAssertEqual(control.targetFrames, 0)
    }

    /// (c) Pass-through at 0 ms: bit-identical, same frame counts (S6).
    func testZeroDelayIsBitIdenticalPassThrough() {
        let special: [Float] = [.nan, 3.5e9, -0.0, .infinity, 1e-40, -7]
        var input: [Float] = []
        for i in 0..<600 { input.append(special[i % special.count]); input.append(Float(i)) }
        // A plain fixture reader: the ring would sanitize NaN/Inf at its boundary (AUD-012).
        let reader = LatencyDelayReader(ArrayReader(input), control: LatencyOffsetControl(), mode: .analysis)
        let dst = UnsafeMutablePointer<Float>.allocate(capacity: 2 * 256)
        defer { dst.deallocate() }
        var offset = 0
        let counts: [Int] = [256, 256, 88, 0]
        for expected in counts {
            let n: Int = reader.read(into: dst, maxFrames: 256)
            XCTAssertEqual(n, expected)
            for i in 0..<(2 * n) {
                XCTAssertEqual(dst[i].bitPattern, input[offset + i].bitPattern, "sample \(offset + i)")
            }
            offset += 2 * n
        }
        XCTAssertEqual(reader.bufferedFrames, 0, "pass-through holds nothing")
    }
}

final class LatencyOffsetSlewTests: XCTestCase {
    private func run(from start: Int, to target: Int) {
        let feed = IndexFeed()
        let control = LatencyOffsetControl(targetFrames: start)
        let reader = LatencyDelayReader(feed.ring.analysisTap!, control: control, mode: .analysis)
        var released: [Float] = []
        for _ in 0..<100 {   // 1 s settled at `start`
            feed.arrive(arrival)
            released += drain(reader)
        }
        control.targetFrames = target
        let low: Double = 0.75 * Double(arrival) - 1
        let high: Double = 1.25 * Double(arrival) + 1
        var settledAfter: Int?
        for step in 1...150 {
            feed.arrive(arrival)
            let batch: [Float] = drain(reader)
            let n: Double = Double(batch.count)
            XCTAssertGreaterThanOrEqual(n, low, "\(start)→\(target): arrival \(step) released \(batch.count)")
            XCTAssertLessThanOrEqual(n, high, "\(start)→\(target): arrival \(step) released \(batch.count)")
            released += batch
            if settledAfter == nil && reader.appliedDelayFrames == target { settledAfter = step }
        }
        let settled: Int = try! XCTUnwrap(settledAfter)
        XCTAssertLessThanOrEqual(settled, 110, "settles within 1.1 s of arrivals")
        XCTAssertEqual(released.count, feed.next - target, "the delay is the new target")
        for (i, value) in released.enumerated() where value != Float(i) {
            XCTFail("frames are released in order without a skip: frame \(i) carried \(value)")
            break
        }
    }

    /// (d) 0 → 250 ms and 250 → 0 ms mid-run: 75…125 % per arrival, settled within 1.1 s (S4).
    func testChangeUpIsBounded() { run(from: 0, to: LatencyOffset.maximumDelayFrames) }
    func testChangeDownIsBounded() { run(from: LatencyOffset.maximumDelayFrames, to: 0) }
}

final class LatencyOffsetSessionTests: XCTestCase {
    /// (e) Analysis: a generation change empties the line; no old-session frame is released (S5).
    func testAnalysisLineIsEmptiedOnANewSession() {
        let feed = IndexFeed()
        let control = LatencyOffsetControl(targetFrames: 4_410)
        let reader = LatencyDelayReader(feed.ring.analysisTap!, control: control, mode: .analysis)
        for _ in 0..<50 {
            feed.arrive(arrival)
            _ = drain(reader)
        }
        XCTAssertEqual(reader.bufferedFrames, 4_410)
        feed.ring.reset()   // a restart or a switch's new session
        control.targetFrames = 2_205
        feed.jump(to: 1_000_000)
        var released: [Float] = []
        feed.arrive(arrival)
        released += drain(reader)
        XCTAssertEqual(reader.bufferedFrames, arrival, "only the new session's audio is held")
        XCTAssertEqual(reader.appliedDelayFrames, 2_205, "the new target applies at once")
        for _ in 0..<20 {
            feed.arrive(arrival)
            released += drain(reader)
        }
        XCTAssertEqual(released.count, 21 * arrival - 2_205)
        XCTAssertEqual(released.first, 1_000_000)
        XCTAssertTrue(released.allSatisfy { (v: Float) -> Bool in v >= 1_000_000 }, "no old-session frame")
    }

    /// (f) Renderer: a ring reset keeps the line; a slow consumer is trimmed to delay + 2,205.
    func testRendererKeepsItsLineAndTrimsTheExcess() {
        let feed = IndexFeed()
        let control = LatencyOffsetControl(targetFrames: 4_410)
        let reader = LatencyDelayReader(feed.ring, control: control, mode: .renderer)
        let dst = UnsafeMutablePointer<Float>.allocate(capacity: 2 * 256)
        defer { dst.deallocate() }
        for _ in 0..<20 {
            feed.arrive(arrival)
            _ = reader.read(into: dst, maxFrames: 256)
        }
        let before: Int = reader.bufferedFrames
        feed.ring.reset()
        _ = reader.read(into: dst, maxFrames: 256)
        XCTAssertGreaterThan(reader.bufferedFrames, 0, "the renderer's line survives a reset")
        XCTAssertLessThanOrEqual(reader.bufferedFrames, before)
        var previous: Float = -1
        for _ in 0..<200 {   // 2 s, reading 256 frames per 441 arrived
            feed.arrive(arrival)
            let n: Int = reader.read(into: dst, maxFrames: 256)
            XCTAssertLessThanOrEqual(reader.bufferedFrames - reader.appliedDelayFrames, LatencyOffset.rendererExcessFrames)
            for i in 0..<n {
                XCTAssertGreaterThan(dst[2 * i], previous, "order is kept")
                previous = dst[2 * i]
            }
        }
        XCTAssertGreaterThan(reader.droppedFrames, 0, "the excess was trimmed and counted")
    }

    /// (g) Overflow: the oldest frames are dropped and counted.
    func testOverflowDropsTheOldest() {
        let feed = IndexFeed()
        let reader = LatencyDelayReader(feed.ring.analysisTap!, control: LatencyOffsetControl(targetFrames: 1_000),
                                        mode: .analysis, capacityFrames: 4_096)
        feed.arrive(8_192)
        let released: [Float] = drain(reader, chunk: 8_192)
        XCTAssertEqual(reader.droppedFrames, 4_096)
        XCTAssertEqual(released.count, 4_096 - 1_000)
        XCTAssertEqual(released.first, 4_096, "the newest 4,096 frames were kept")
    }
}

final class LatencyOffsetEstimateTests: XCTestCase {
    /// (h) The estimate from injected values (US3).
    func testEstimate() {
        let playback: Double = LatencyOffset.estimateMilliseconds(mode: .inAppPlayback, outputLatency: 0.160, ioBufferDuration: 0.005)
        XCTAssertEqual(playback, 165)
        XCTAssertEqual(LatencyOffset.estimateMilliseconds(mode: .systemAppCapture, outputLatency: 0.160, ioBufferDuration: 0.005), 165)
        XCTAssertEqual(LatencyOffset.estimateMilliseconds(mode: .inAppPlayback, outputLatency: 0.400, ioBufferDuration: 0), 250)
        XCTAssertEqual(LatencyOffset.estimateMilliseconds(mode: .inAppPlayback, outputLatency: .nan, ioBufferDuration: -1), 0)
        XCTAssertEqual(LatencyOffset.estimateMilliseconds(mode: .inAppPlayback, outputLatency: -1, ioBufferDuration: 0.012), 12)
        XCTAssertEqual(LatencyOffset.estimateMilliseconds(mode: .microphone, outputLatency: 0.160, ioBufferDuration: 0.005), 0)
    }
}
