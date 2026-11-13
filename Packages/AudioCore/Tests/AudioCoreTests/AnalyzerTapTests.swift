// AnalyzerTapTests.swift — VIS-001-T08: `AudioAnalyzer` builds its normalized ring with an optional
// analysis tap (VIS-001-R14; ANL-001-R9). Default: no tap, exactly as before. With a capacity, the tap
// receives every frame the analyzer's Normalizer writes, and the main ring is unchanged.
import XCTest
@testable import AudioCore

final class AnalyzerTapTests: XCTestCase {
    private func push(_ sink: PCMSink, value: Float, frames: Int) {
        let format = AudioFormat(sampleRate: 44_100, channelCount: 2, isInterleaved: true, sampleType: .float32)
        let samples = [Float](repeating: value, count: frames * 2)
        samples.withUnsafeBytes { sink.writeInterleaved($0.baseAddress!, frames: frames, format: format, hostTimeNs: 1) }
    }

    func testNoTapByDefault() {
        let analyzer = AudioAnalyzer(sink: PCMSink(), clock: { 0 })
        XCTAssertNil(analyzer.normalizedOutput.analysisTap)
        XCTAssertEqual(analyzer.normalizedOutput.analysisTapAvailableFrames, 0)
    }

    func testTapReceivesWhatTheAnalyzerWrites() throws {
        let sink = PCMSink()
        let analyzer = AudioAnalyzer(sink: sink, clock: { 0 }, analysisTapCapacityFrames: 22_050)
        let tap = try XCTUnwrap(analyzer.normalizedOutput.analysisTap)
        analyzer.apply(.started)
        push(sink, value: 0.25, frames: 441)
        analyzer.step()
        XCTAssertEqual(analyzer.normalizedOutput.analysisTapAvailableFrames, analyzer.normalizedOutput.availableFrames,
                       "the tap holds a copy of every frame written to the main ring")
        XCTAssertGreaterThan(analyzer.normalizedOutput.analysisTapAvailableFrames, 0)
        var out = [Float](repeating: 0, count: 2 * 4_096)
        let frames = out.withUnsafeMutableBufferPointer { tap.read(into: $0.baseAddress!, maxFrames: 4_096) }
        XCTAssertGreaterThan(frames, 0)
        XCTAssertEqual(Set(out[0..<(2 * frames)]), [0.25])
        XCTAssertGreaterThan(analyzer.normalizedOutput.availableFrames, 0, "reading the tap leaves the main ring alone")
    }
}
