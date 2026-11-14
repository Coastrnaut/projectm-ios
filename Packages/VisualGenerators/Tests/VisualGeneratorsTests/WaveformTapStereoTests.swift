// WaveformTapStereoTests.swift — VIS-004-T02 (contract C1; VIS-004-R2, R16, R17): the pass-through tap's
// stereo history for the Lissajous scope. The forwarded reads and the mono history are unchanged.
import AudioCore
@testable import VisualBandFeed
import VisualGenerators
import XCTest

final class WaveformTapStereoTests: XCTestCase {
    /// Frame f: L = f + 1, R = −(f + 1) (scaled to stay small), so every value names its frame and channel.
    private func ramp(frames: Int) -> [Float] {
        var out = [Float](repeating: 0, count: 2 * frames)
        for f in 0..<frames {
            let v: Float = Float(f + 1) * 1e-4
            out[2 * f] = v
            out[2 * f + 1] = -v
        }
        return out
    }

    private func readAll(_ tap: WaveformTap, chunk: Int, frames: Int) -> [Float] {
        var forwarded: [Float] = []
        var scratch = [Float](repeating: 0, count: 2 * chunk)
        var left = frames
        while left > 0 {
            let n = scratch.withUnsafeMutableBufferPointer { (b: inout UnsafeMutableBufferPointer<Float>) -> Int in
                tap.read(into: b.baseAddress!, maxFrames: chunk)
            }
            guard n > 0 else { break }
            forwarded += scratch[0..<(2 * n)]
            left -= n
        }
        return forwarded
    }

    private func stereo(_ tap: WaveformTap) -> (values: [Float], total: UInt64?) {
        let n = WaveformFrameBuffer.capacity
        var out = [Float](repeating: .nan, count: n)
        let total = out.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Float>) -> UInt64? in
            tap.stereoOutput.readLatest(into: p.baseAddress!, capacity: n)
        }
        return (out, total)
    }

    func testShortInputFillsTheTailWithZerosBefore() {
        let fixture = ramp(frames: 300)
        let tap = WaveformTap(ArrayPCMReader(fixture))
        let forwarded = readAll(tap, chunk: 128, frames: 300)
        XCTAssertEqual(forwarded, fixture, "the forwarded frames are the wrapped reader's")
        let (history, total) = stereo(tap)
        XCTAssertEqual(total, 300)
        XCTAssertEqual(WaveformTap.stereoFrames, 2_048)
        let start = 2 * (WaveformTap.stereoFrames - 300)
        XCTAssertTrue(history[0..<start].allSatisfy { (v: Float) -> Bool in v == 0 }, "zeros before the first frames")
        XCTAssertEqual(Array(history[start...]), fixture, "interleaved L, R, oldest first")
    }

    func testLongInputKeepsTheNewestFramesAndTheMonoHistory() {
        let frames = 5_000
        let fixture = ramp(frames: frames)
        let tap = WaveformTap(ArrayPCMReader(fixture))
        _ = readAll(tap, chunk: 3_000, frames: frames)   // one read larger than the history
        let (history, total) = stereo(tap)
        XCTAssertEqual(total, UInt64(frames))
        XCTAssertEqual(history, Array(fixture[(2 * (frames - 2_048))...]))
        // The mono history (VIS-003) is still the mid mix: (v + −v)/2 = 0 for this fixture.
        let n = WaveformFrameBuffer.capacity
        var mono = [Float](repeating: .nan, count: n)
        _ = mono.withUnsafeMutableBufferPointer { (p: inout UnsafeMutableBufferPointer<Float>) -> UInt64? in
            tap.output.readLatest(into: p.baseAddress!, capacity: n)
        }
        XCTAssertTrue(mono.allSatisfy { (v: Float) -> Bool in v == 0 })
    }

    func testStorageIsAllocatedOnce() {
        let fixture = ramp(frames: 20_000)
        let tap = WaveformTap(ArrayPCMReader(fixture))
        let before = tap.storageAddresses
        _ = readAll(tap, chunk: 512, frames: 20_000)
        XCTAssertEqual(tap.storageAddresses, before)
    }
}
