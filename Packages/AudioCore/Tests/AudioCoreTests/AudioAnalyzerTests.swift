// AudioAnalyzer drives the classifier from a real PCMSink with an injected clock.
import XCTest
import Foundation
@testable import AudioCore

final class AudioAnalyzerTests: XCTestCase {
    private final class TestClock: @unchecked Sendable {
        var now: Double = 0
    }

    private let format = AudioFormat(sampleRate: 48_000, channelCount: 2, isInterleaved: true, sampleType: .float32)

    private func push(_ sink: PCMSink, amplitude: Float, seconds: Double) {
        let frames = Int(48_000 * seconds)
        let samples = [Float](repeating: amplitude, count: frames * 2)
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: format, hostTimeNs: 1) }
    }

    func testLoudAudioBecomesActiveAndPublishesTransitions() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        let received = UpdateCollector()
        analyzer.setUpdateHandler { received.append($0) }
        XCTAssertEqual(analyzer.apply(.started).state, .waiting)

        for i in 1...30 {          // 30 × 10 ms of loud audio
            push(sink, amplitude: 0.5, seconds: 0.01)
            clock.now = Double(i) * 0.01
            analyzer.step()
        }
        XCTAssertEqual(analyzer.currentState, .active)
        let states = received.all.flatMap { $0.newTransitions.map(\.state) }
        XCTAssertEqual(states, [.waiting, .active])
        XCTAssertTrue(received.all.last!.hasVerifiedActiveAudio)
    }

    func testNoDataBecomesNoAudioReceived() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        clock.now = 5.01
        XCTAssertEqual(analyzer.step().state, .noAudioReceived)
    }

    func testDigitalSilenceIsSilentNotNoAudio() {
        let sink = PCMSink()
        let clock = TestClock()
        let analyzer = AudioAnalyzer(sink: sink, clock: { clock.now })
        analyzer.apply(.started)
        push(sink, amplitude: 0, seconds: 0.01)
        clock.now = 0.01
        XCTAssertEqual(analyzer.step().state, .silent)
    }
}

private final class UpdateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AnalyzerUpdate] = []
    func append(_ u: AnalyzerUpdate) { lock.lock(); items.append(u); lock.unlock() }
    var all: [AnalyzerUpdate] { lock.lock(); defer { lock.unlock() }; return items }
}
