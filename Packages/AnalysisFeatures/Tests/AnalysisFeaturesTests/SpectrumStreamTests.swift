// SpectrumStreamTests.swift — framing, hop, channel modes, size and hop changes, timestamps and
// pulling from the normalized ring's analysis tap (ANL-001-T14; ANL-001-R5 to R7, R9, R17).
import XCTest
import AudioCore
@testable import AnalysisFeatures

final class SpectrumStreamTests: XCTestCase {
    private func feed(_ stream: SpectrumStream, mono: [Float]) -> [(SpectrumFrame, [Float])] {
        var out: [(SpectrumFrame, [Float])] = []
        mono.withUnsafeBufferPointer { b in
            var offset = 0
            repeat {
                offset += stream.append(mono: b.baseAddress! + offset, count: b.count - offset)
                while let frame = stream.nextFrame() { out.append((frame, Array(stream.magnitudes))) }
            } while offset < b.count
        }
        return out
    }

    func testNoFrameBeforeAWholeWindow() throws {
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n1024), clock: { 0 })
        let input = TestSupport.noise(count: 1_023)
        _ = input.withUnsafeBufferPointer { stream.append(mono: $0.baseAddress!, count: $0.count) }
        XCTAssertNil(stream.nextFrame())
        XCTAssertEqual(stream.bufferedSamples, 1_023)
        var one: Float = 0.1
        XCTAssertEqual(stream.append(mono: &one, count: 1), 1)
        XCTAssertEqual(stream.nextFrame()?.index, 0)
        XCTAssertNil(stream.nextFrame())
        XCTAssertEqual(stream.bufferedSamples, 512, "advanced by the default hop")
    }

    func testFramesMatchTheAnalyzerAtEveryHop() throws {
        let input = TestSupport.noise(count: 12_000, seed: 3)
        for backend in TestSupport.backends {
            let analyzer = SpectrumAnalyzer(backend: backend)
            for (size, hop) in [(FFTSize.n512, 512), (.n512, 1), (.n1024, 300), (.n2048, 1_024), (.n8192, 777)] {
                let frames = feed(SpectrumStream(configuration: try SpectrumConfiguration(size: size, hop: hop), backend: backend, clock: { 0 }), mono: input)
                XCTAssertEqual(frames.count, (input.count - size.rawValue) / hop + 1, "N=\(size.rawValue) hop=\(hop)")
                for (i, (frame, magnitudes)) in frames.enumerated() where i % max(1, frames.count / 7) == 0 || i == frames.count - 1 {
                    XCTAssertEqual(frame.index, Int64(i * hop))
                    XCTAssertEqual(frame.size, size)
                    XCTAssertEqual(frame.sampleRate, 44_100)
                    let expected = analyzer.magnitudes(of: Array(input[(i * hop)..<(i * hop + size.rawValue)]), size: size)
                    XCTAssertEqual(TestSupport.bitPattern(magnitudes), TestSupport.bitPattern(expected), "\(backend) N=\(size.rawValue) hop=\(hop) frame \(i)")
                }
            }
        }
    }

    func testAppendNeverExceedsTheFIFO() throws {
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n512), clock: { 0 })
        let input = TestSupport.noise(count: 20_000)
        let accepted = input.withUnsafeBufferPointer { stream.append(mono: $0.baseAddress!, count: $0.count) }
        XCTAssertEqual(accepted, SpectrumStream.fifoCapacity)
        XCTAssertEqual(SpectrumStream.fifoCapacity, 16_384)
        XCTAssertEqual(input.withUnsafeBufferPointer { stream.append(mono: $0.baseAddress!, count: $0.count) }, 0)
        XCTAssertNotNil(stream.nextFrame())
        XCTAssertEqual(input.withUnsafeBufferPointer { stream.append(mono: $0.baseAddress!, count: $0.count) }, 256)
        XCTAssertEqual(stream.append(mono: input, count: 0), 0)
    }

    func testChannelModes() throws {
        let left = TestSupport.binCentredSine(bin: 10, size: 512, amplitude: 0.5)
        let right = TestSupport.binCentredSine(bin: 40, size: 512, amplitude: 0.25)
        var stereo = [Float](repeating: 0, count: 1_024)
        for i in 0..<512 { stereo[2 * i] = left[i]; stereo[2 * i + 1] = right[i] }
        let analyzer = SpectrumAnalyzer()
        for mode in [ChannelMode.mid, .left, .right] {
            let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n512, channelMode: mode), clock: { 0 })
            XCTAssertEqual(stereo.withUnsafeBufferPointer { stream.append(interleaved: $0.baseAddress!, frames: 512, channels: 2) }, 512)
            XCTAssertNotNil(stream.nextFrame())
            let mono: [Float] = switch mode {
            case .mid: (0..<512).map { (left[$0] + right[$0]) * 0.5 }
            case .left: left
            case .right: right
            }
            XCTAssertEqual(TestSupport.bitPattern(Array(stream.magnitudes)), TestSupport.bitPattern(analyzer.magnitudes(of: mono, size: .n512)), "\(mode)")
        }
        // Mono input through the interleaved API with one channel, and more than two channels.
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n512, channelMode: .right), clock: { 0 })
        XCTAssertEqual(left.withUnsafeBufferPointer { stream.append(interleaved: $0.baseAddress!, frames: 512, channels: 1) }, 512)
        XCTAssertNotNil(stream.nextFrame())
        XCTAssertEqual(TestSupport.bitPattern(Array(stream.magnitudes)), TestSupport.bitPattern(analyzer.magnitudes(of: left, size: .n512)))
        XCTAssertEqual(stream.append(interleaved: left, frames: 10, channels: 0), 0)
    }

    func testSizeChangeMidStreamKeepsBufferedAudioAndIndices() throws {
        let input = TestSupport.noise(count: 6_000, seed: 11)
        let analyzer = SpectrumAnalyzer()
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n2048), clock: { 0 })
        _ = input.withUnsafeBufferPointer { stream.append(mono: $0.baseAddress!, count: $0.count) }
        XCTAssertEqual(stream.nextFrame()?.index, 0)
        XCTAssertEqual(stream.nextFrame()?.index, 1_024)
        stream.setConfiguration(try SpectrumConfiguration(size: .n512, hop: 100))
        let next = try XCTUnwrap(stream.nextFrame())
        XCTAssertEqual(next.index, 2_048, "previous start 1,024 + old hop 1,024")
        XCTAssertEqual(next.size, .n512)
        XCTAssertEqual(stream.magnitudes.count, 257)
        XCTAssertEqual(TestSupport.bitPattern(Array(stream.magnitudes)),
                       TestSupport.bitPattern(analyzer.magnitudes(of: Array(input[2_048..<2_560]), size: .n512)))
        XCTAssertEqual(stream.nextFrame()?.index, 2_148, "new hop")
        // Growing the size waits for enough audio.
        stream.setConfiguration(try SpectrumConfiguration(size: .n8192))
        XCTAssertNil(stream.nextFrame())
        XCTAssertEqual(stream.bufferedSamples, 6_000 - 2_248)
    }

    func testTimestampsComeFromTheInjectedClock() throws {
        let counter = Counter()
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n512, hop: 512), clock: { counter.next() })
        let frames = feed(stream, mono: TestSupport.noise(count: 2_048))
        XCTAssertEqual(frames.map(\.0.timestampNanoseconds), [1, 2, 3, 4])
        XCTAssertEqual(frames.map(\.0.index), [0, 512, 1_024, 1_536])
    }

    func testResetRestartsIndices() throws {
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n512), clock: { 0 })
        _ = feed(stream, mono: TestSupport.noise(count: 3_000))
        stream.reset()
        XCTAssertEqual(stream.bufferedSamples, 0)
        XCTAssertEqual(feed(stream, mono: TestSupport.noise(count: 512)).map(\.0.index), [0])
    }

    func testCopyMagnitudes() throws {
        let stream = SpectrumStream(configuration: try SpectrumConfiguration(size: .n512), clock: { 0 })
        _ = feed(stream, mono: TestSupport.noise(count: 512))
        var copy = [Float](repeating: -1, count: 257)
        copy.withUnsafeMutableBufferPointer { stream.copyMagnitudes(into: $0.baseAddress!) }
        XCTAssertEqual(TestSupport.bitPattern(copy), TestSupport.bitPattern(Array(stream.magnitudes)))
    }

    func testPullFromTheAnalysisTapMatchesDirectAppend() throws {
        let ring = NormalizedPCMRing(analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        let tap = try XCTUnwrap(ring.analysisTap)
        let left = TestSupport.noise(count: 10_000, seed: 21)
        let right = TestSupport.noise(count: 10_000, seed: 22)
        var stereo = [Float](repeating: 0, count: 20_000)
        for i in 0..<10_000 { stereo[2 * i] = left[i]; stereo[2 * i + 1] = right[i] }
        stereo.withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 10_000) }
        let configuration = try SpectrumConfiguration(size: .n1024, hop: 333)
        let pulled = SpectrumStream(configuration: configuration, clock: { 0 })
        var fromTap: [(SpectrumFrame, [Float])] = []
        let read = pulled.pull(from: tap) { frame, magnitudes in fromTap.append((frame, Array(magnitudes))) }
        XCTAssertEqual(read, 10_000)
        XCTAssertEqual(ring.analysisTapAvailableFrames, 0)
        XCTAssertEqual(ring.availableFrames, 10_000, "projectM's ring is untouched")
        let direct = SpectrumStream(configuration: configuration, clock: { 0 })
        var fromAppend: [(SpectrumFrame, [Float])] = []
        stereo.withUnsafeBufferPointer { b in
            var offset = 0
            while offset < 10_000 {
                offset += direct.append(interleaved: b.baseAddress! + 2 * offset, frames: 10_000 - offset, channels: 2)
                while let frame = direct.nextFrame() { fromAppend.append((frame, Array(direct.magnitudes))) }
            }
        }
        XCTAssertEqual(fromTap.count, (10_000 - 1_024) / 333 + 1)
        XCTAssertEqual(fromTap.map(\.0), fromAppend.map(\.0))
        XCTAssertEqual(fromTap.map { TestSupport.bitPattern($0.1) }, fromAppend.map { TestSupport.bitPattern($0.1) })
    }
}

/// A deterministic clock for tests: 1, 2, 3, … Used from one thread only.
private final class Counter: @unchecked Sendable {
    private var value: UInt64 = 0
    func next() -> UInt64 { value += 1; return value }
}
