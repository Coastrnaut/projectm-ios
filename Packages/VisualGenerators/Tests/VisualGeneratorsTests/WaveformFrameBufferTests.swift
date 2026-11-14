// WaveformFrameBufferTests.swift — VIS-003-T04: the wait-free hand-off of sample histories from the
// analysis worker to the frame loop (VIS-003-R2, S3; contract C2), and the pass-through tap that
// fills it (contract C3): bytes forwarded unchanged, the mid mix kept newest-last, the session
// generation forwarded. Pure Swift (Linux too).
import AudioCore
import Foundation
import XCTest
@testable import VisualBandFeed
@testable import VisualGenerators

final class WaveformFrameBufferTests: XCTestCase {
    private let n = WaveformFrameBuffer.capacity

    func testNewestFrameOnceThenNil() {
        let buffer = WaveformFrameBuffer()
        var out = [Float](repeating: -1, count: n)
        XCTAssertNil(out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: n) })
        for s in 1...3 {
            let frame = [Float](repeating: Float(s), count: n)
            frame.withUnsafeBufferPointer { buffer.write($0, totalWritten: UInt64(s * 10)) }
        }
        XCTAssertEqual(out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: n) }, 30)
        XCTAssertEqual(out, [Float](repeating: 3, count: n), "the newest frame")
        XCTAssertNil(out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: n) }, "nothing new")
    }

    func testSmallerReaderGetsTheNewestTail() {
        let buffer = WaveformFrameBuffer()
        let frame = (0..<n).map { (i: Int) -> Float in Float(i) }
        frame.withUnsafeBufferPointer { buffer.write($0, totalWritten: 1) }
        var out = [Float](repeating: 0, count: 4)
        _ = out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: 4) }
        XCTAssertEqual(out, [Float(n - 4), Float(n - 3), Float(n - 2), Float(n - 1)])
    }

    func testConcurrentWriterAndReaderNeverSeeATornFrame() {
        let buffer = WaveformFrameBuffer()
        let frames = 2_000
        let size = n
        let group = DispatchGroup()
        let failures = WaveformFailures()
        group.enter()
        Thread.detachNewThread {
            var values = [Float](repeating: 0, count: size)
            for s in 1...frames {
                for i in 0..<size { values[i] = Float(s) }
                values.withUnsafeBufferPointer { buffer.write($0, totalWritten: UInt64(s)) }
            }
            group.leave()
        }
        group.enter()
        Thread.detachNewThread {
            var out = [Float](repeating: 0, count: size)
            var last: UInt64 = 0
            while last < UInt64(frames) {
                guard let total = out.withUnsafeMutableBufferPointer({ buffer.readLatest(into: $0.baseAddress!, capacity: size) }) else {
                    continue
                }
                if total <= last { failures.add("total went from \(last) to \(total)") }
                let expected = Float(total)
                if out.contains(where: { (v: Float) -> Bool in v != expected }) { failures.add("torn frame at \(total)") }
                last = total
            }
            group.leave()
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success, "30 s ceiling")
        XCTAssertEqual(failures.messages, [])
    }
}

/// A reader that also reports a session generation.
private final class SessionPCMReader: NormalizedPCMReader, AnalysisSessionReporting, @unchecked Sendable {
    let inner: ArrayPCMReader
    var analysisSessionGeneration: UInt64 = 7
    init(_ samples: [Float]) { inner = ArrayPCMReader(samples) }
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int { inner.read(into: dst, maxFrames: maxFrames) }
}

final class WaveformTapTests: XCTestCase {
    private let n = WaveformFrameBuffer.capacity

    /// Stereo frames: left = frame index, right = −2 × frame index (so the mid is −i/2).
    private func stereo(_ frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: 2 * frames)
        for i in 0..<frames {
            out[2 * i] = Float(i)
            out[2 * i + 1] = -2 * Float(i)
        }
        return out
    }

    private func latest(_ tap: WaveformTap) -> (samples: [Float], total: UInt64?) {
        var out = [Float](repeating: .nan, count: n)
        let total = out.withUnsafeMutableBufferPointer { tap.output.readLatest(into: $0.baseAddress!, capacity: n) }
        return (out, total)
    }

    func testForwardsBytesAndKeepsTheMidMixNewestLast() {
        let source = stereo(1_000)
        let tap = WaveformTap(ArrayPCMReader(source))
        var forwarded: [Float] = []
        var scratch = [Float](repeating: 0, count: 2 * 300)
        while true {
            let frames = scratch.withUnsafeMutableBufferPointer { tap.read(into: $0.baseAddress!, maxFrames: 300) }
            if frames == 0 { break }
            forwarded += scratch[0..<(2 * frames)]
        }
        XCTAssertEqual(forwarded, source, "the analyzer reads exactly the tap's bytes (VIS-003-R15)")
        let (history, total) = latest(tap)
        XCTAssertEqual(total, 1_000)
        XCTAssertEqual(history[n - 1], -999.0 / 2, "newest last: mid of frame 999")
        XCTAssertEqual(history[n - 1_000], 0, "frame 0's mid")
        XCTAssertEqual(history[0..<(n - 1_000)].allSatisfy { (v: Float) -> Bool in v == 0 }, true, "zeros before the first sample")
    }

    func testLongReadsKeepOnlyTheNewestHistory() {
        let frames = n + 1_500
        let tap = WaveformTap(ArrayPCMReader(stereo(frames)))
        var scratch = [Float](repeating: 0, count: 2 * frames)
        let read = scratch.withUnsafeMutableBufferPointer { tap.read(into: $0.baseAddress!, maxFrames: frames) }
        XCTAssertEqual(read, frames)
        let (history, total) = latest(tap)
        XCTAssertEqual(total, UInt64(frames))
        XCTAssertEqual(history[0], -Float(frames - n) / 2)
        XCTAssertEqual(history[n - 1], -Float(frames - 1) / 2)
        // An empty read publishes nothing new.
        _ = scratch.withUnsafeMutableBufferPointer { tap.read(into: $0.baseAddress!, maxFrames: 10) }
        XCTAssertNil(latest(tap).total)
    }

    func testSessionGenerationIsForwarded() {
        let reporting = SessionPCMReader(stereo(10))
        XCTAssertEqual(WaveformTap(reporting).analysisSessionGeneration, 7)
        reporting.analysisSessionGeneration = 8
        XCTAssertEqual(WaveformTap(reporting).analysisSessionGeneration, 8)
        XCTAssertEqual(WaveformTap(ArrayPCMReader(stereo(10))).analysisSessionGeneration, 0, "none reported: 0, never changes")
    }

    func testTapFeedsTheAnalyzerUnchanged() throws {
        // The analysis pipeline sees the same bands through the tap as without it (VIS-003-R15).
        let sine = try BandFeedFixture.sine(440)
        let direct = try SpectrumBandFeed(barCount: .b32)
        let tapped = try SpectrumBandFeed(barCount: .b32)
        XCTAssertTrue(direct.pull(from: ArrayPCMReader(sine)))
        XCTAssertTrue(tapped.pull(from: WaveformTap(ArrayPCMReader(sine))))
        XCTAssertEqual(Array(direct.bands), Array(tapped.bands))
    }
}

/// Collects failures from background threads (XCTest assertions belong on the test's thread).
private final class WaveformFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ message: String) { lock.lock(); if stored.count < 10 { stored.append(message) }; lock.unlock() }
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}
