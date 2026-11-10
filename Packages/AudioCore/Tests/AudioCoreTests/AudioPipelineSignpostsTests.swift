// Task T062: the analyzer reports the three latency stages (research R-06) through
// AudioPipelineSignposts; PCMSink measures capture delivery from capture timestamps.
import XCTest
import Foundation
@testable import AudioCore

final class RecordingSignposts: AudioPipelineSignposts, @unchecked Sendable {
    private let lock = NSLock()
    private var _intervals = 0
    private var _deliveries: [Double] = []
    private var _residencies: [Double] = []
    /// lock()/unlock() rather than withLock, for older Linux Foundation.
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    var intervals: Int { locked { _intervals } }
    var deliveries: [Double] { locked { _deliveries } }
    var residencies: [Double] { locked { _residencies } }

    func ringAndConversion(_ body: () -> Void) {
        body()
        locked { _intervals += 1 }
    }
    func captureDelivery(milliseconds: Double) { locked { _deliveries.append(milliseconds) } }
    func normalizedResidency(milliseconds: Double) { locked { _residencies.append(milliseconds) } }
}

final class AudioPipelineSignpostsTests: XCTestCase {
    private let stereo44 = AudioFormat(sampleRate: 44_100, channelCount: 2, isInterleaved: true, sampleType: .float32)

    private func write(_ sink: PCMSink, frames: Int, captureTimeNs: UInt64 = 0, hostTimeNs: UInt64) {
        let samples = [Float](repeating: 0.5, count: frames * 2)
        samples.withUnsafeBytes {
            sink.writeInterleaved($0.baseAddress!, frames: frames, format: stereo44,
                                  captureTimeNs: captureTimeNs, hostTimeNs: hostTimeNs)
        }
    }

    func testSinkKeepsTheLongestPlausibleDeliveryUntilTaken() {
        let sink = PCMSink()
        write(sink, frames: 10, captureTimeNs: 1_000_000_000, hostTimeNs: 1_012_000_000)   // 12 ms
        write(sink, frames: 10, captureTimeNs: 1_020_000_000, hostTimeNs: 1_025_000_000)   // 5 ms
        write(sink, frames: 10, hostTimeNs: 1_030_000_000)                                  // no timestamp
        write(sink, frames: 10, captureTimeNs: 2_000_000_000, hostTimeNs: 1_040_000_000)   // in the future
        write(sink, frames: 10, captureTimeNs: 1, hostTimeNs: 60_000_000_000)              // another clock
        XCTAssertEqual(sink.takeCaptureDeliveryMaxNs(), 12_000_000)
        XCTAssertEqual(sink.takeCaptureDeliveryMaxNs(), 0, "taking starts a new measurement")
    }

    func testAnalyzerSignpostsDrainsWithAudioAndReportsLatencies() {
        let sink = PCMSink()
        let analyzer = AudioAnalyzer(sink: sink, clock: { 0 })
        let signposts = RecordingSignposts()
        analyzer.setSignposts(signposts)
        analyzer.step()
        XCTAssertEqual(signposts.intervals, 0, "no interval without audio")
        let now = MonotonicClock.nowNanoseconds()
        write(sink, frames: 4_410, captureTimeNs: now - 8_000_000, hostTimeNs: now)        // 8 ms delivery
        analyzer.step()
        XCTAssertEqual(signposts.intervals, 1)
        XCTAssertEqual(signposts.deliveries.count, 1)
        XCTAssertEqual(signposts.deliveries.first ?? 0, 8, accuracy: 0.001)
        XCTAssertTrue(signposts.residencies.isEmpty, "the renderer has not read yet")

        var out = [Float](repeating: 0, count: 2 * 1_024)
        _ = out.withUnsafeMutableBufferPointer { analyzer.normalizedOutput.read(into: $0.baseAddress!, maxFrames: 1_024) }
        analyzer.step()
        // 4,410 frames were waiting; the freshness rule skipped all but the newest 50 ms.
        XCTAssertEqual(signposts.residencies.last ?? 0, 50, accuracy: 0.001)
    }

    func testNoSignpostsByDefault() {
        let sink = PCMSink()
        let analyzer = AudioAnalyzer(sink: sink, clock: { 0 })
        write(sink, frames: 441, hostTimeNs: MonotonicClock.nowNanoseconds())
        XCTAssertEqual(analyzer.step().statistics.sampleCount, 441)
    }
}
