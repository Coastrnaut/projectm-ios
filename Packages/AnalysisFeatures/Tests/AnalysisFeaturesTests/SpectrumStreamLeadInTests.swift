// SpectrumStreamLeadInTests.swift — ANL-004's additive deltas to ANL-001's stream (ANL-004-T02;
// ANL-004-R7, R8, S7): frames carry their hop, and an opt-in lead-in starts the stream as if
// preceded by `size − hop` samples of silence. Without the lead-in nothing changes.
import XCTest
@testable import AnalysisFeatures

final class SpectrumStreamLeadInTests: XCTestCase {
    private func feed(_ stream: SpectrumStream, _ samples: [Float]) -> [(frame: SpectrumFrame, magnitudes: [Float])] {
        var out: [(SpectrumFrame, [Float])] = []
        samples.withUnsafeBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                offset += stream.append(mono: buffer.baseAddress! + offset, count: buffer.count - offset)
                while let frame = stream.nextFrame() { out.append((frame, Array(stream.magnitudes))) }
            }
        }
        return out
    }

    func testDefaultStreamIsUnchangedAndFramesCarryTheirHop() throws {
        let configuration = try SpectrumConfiguration(size: .n1024, hop: 256)
        let input = TestSupport.noise(count: 8_192)
        let stream = SpectrumStream(configuration: configuration, backend: .portable, clock: { 0 })
        XCTAssertEqual(stream.leadIn, .none)
        let frames = feed(stream, input)
        XCTAssertEqual(frames.count, (input.count - 1_024) / 256 + 1)
        let analyzer = SpectrumAnalyzer(backend: .portable)
        for (i, item) in frames.enumerated() {
            XCTAssertEqual(item.frame.index, Int64(i * 256))
            XCTAssertEqual(item.frame.hop, 256)
            let expected = analyzer.magnitudes(of: Array(input[(i * 256)..<(i * 256 + 1_024)]), size: .n1024)
            XCTAssertEqual(TestSupport.bitPattern(item.magnitudes), TestSupport.bitPattern(expected), "frame \(i)")
        }
    }

    func testSilenceLeadInEqualsExplicitZerosWithShiftedIndices() throws {
        for backend in TestSupport.backends {
            let configuration = try SpectrumConfiguration(size: .n2048, hop: 512)
            let input = TestSupport.noise(count: 12_000, seed: 7)
            let lead = SpectrumStream(configuration: configuration, backend: backend, clock: { 0 }, leadIn: .silence)
            XCTAssertEqual(lead.leadIn, .silence)
            XCTAssertEqual(lead.bufferedSamples, 1_536)
            let padded = SpectrumStream(configuration: configuration, backend: backend, clock: { 0 })
            let a = feed(lead, input)
            let b = feed(padded, [Float](repeating: 0, count: 1_536) + input)
            XCTAssertEqual(a.count, b.count)
            XCTAssertEqual(a.first?.frame.index, -1_536)
            for (x, y) in zip(a, b) {
                XCTAssertEqual(x.frame.index + 1_536, y.frame.index)
                XCTAssertEqual(x.frame.hop, 512)
                XCTAssertEqual(TestSupport.bitPattern(x.magnitudes), TestSupport.bitPattern(y.magnitudes), "\(backend) frame \(x.frame.index)")
            }
            // Consecutive indices advance by the hop.
            for (p, q) in zip(a, a.dropFirst()) { XCTAssertEqual(q.frame.index - p.frame.index, 512) }
        }
    }

    func testResetReappliesTheLeadInWithTheCurrentConfiguration() throws {
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n1024, hop: 512),
                                    backend: .portable, clock: { 0 }, leadIn: .silence)
        XCTAssertEqual(stream.bufferedSamples, 512)
        _ = feed(stream, TestSupport.noise(count: 3_000))
        stream.setConfiguration(try SpectrumConfiguration(size: .n4096, hop: 1_024))
        stream.reset()
        XCTAssertEqual(stream.bufferedSamples, 3_072)
        let frames = feed(stream, TestSupport.noise(count: 2_000))
        XCTAssertEqual(frames.first?.frame.index, -3_072)
        XCTAssertEqual(frames.first?.frame.hop, 1_024)
        // Without a lead-in, reset empties the FIFO as before.
        let plain = SpectrumStream(configuration: try SpectrumConfiguration(size: .n1024), clock: { 0 })
        _ = feed(plain, TestSupport.noise(count: 3_000))
        plain.reset()
        XCTAssertEqual(plain.bufferedSamples, 0)
    }

    func testHopChangeIsReportedInTheNextFrame() throws {
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n512, hop: 256),
                                    backend: .portable, clock: { 0 })
        let input = TestSupport.noise(count: 2_048)
        var frames: [SpectrumFrame] = []
        input.withUnsafeBufferPointer { buffer in
            _ = stream.append(mono: buffer.baseAddress!, count: buffer.count)
            frames.append(stream.nextFrame()!)
            stream.setConfiguration(try! SpectrumConfiguration(size: .n512, hop: 128))
            frames.append(stream.nextFrame()!)
            frames.append(stream.nextFrame()!)
        }
        XCTAssertEqual(frames.map(\.index), [0, 256, 384])
        XCTAssertEqual(frames.map(\.hop), [256, 128, 128])
    }

    func testFrameInitializerDefaultsTheHopToHalfTheSize() {
        let frame = SpectrumFrame(index: 5, size: .n2048, sampleRate: 48_000, timestampNanoseconds: 9)
        XCTAssertEqual(frame.hop, 1_024)
        XCTAssertEqual(SpectrumFrame(index: 0, size: .n512, sampleRate: 44_100, timestampNanoseconds: 0, hop: 64).hop, 64)
    }
}
