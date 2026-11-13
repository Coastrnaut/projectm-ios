// BandFrameBufferTests.swift — VIS-001-T04: the lock-free triple buffer between the analysis queue
// and the frame loop (research VIS-001-D6). No timing assertions: the threaded test waits on
// completion with a 30 s ceiling.
import Foundation
import XCTest
@testable import VisualGenerators

final class BandFrameBufferTests: XCTestCase {
    private func write(_ buffer: BandFrameBuffer, _ values: [Float], time: UInt64 = 0) {
        values.withUnsafeBufferPointer { buffer.write($0, timestampNanoseconds: time) }
    }

    func testNothingToReadBeforeTheFirstWrite() {
        let buffer = BandFrameBuffer()
        var out = [Float](repeating: -1, count: 128)
        XCTAssertNil(out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: 128) })
        XCTAssertEqual(out[0], -1, "untouched")
    }

    func testReaderGetsTheNewestCompleteFrameOnce() {
        let buffer = BandFrameBuffer()
        write(buffer, [1, 1, 1], time: 10)
        write(buffer, [2, 2, 2, 2], time: 20)
        write(buffer, [3, 3], time: 30)
        var out = [Float](repeating: 0, count: 128)
        let info = out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: 128) }
        XCTAssertEqual(info?.count, 2)
        XCTAssertEqual(info?.timestampNanoseconds, 30)
        XCTAssertEqual(info?.sequence, 3)
        XCTAssertEqual(Array(out[0..<2]), [3, 3])
        XCTAssertNil(out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: 128) },
                     "no new frame")
        XCTAssertEqual(Array(out[0..<2]), [3, 3], "the reader keeps its last values")
        write(buffer, [4], time: 40)
        XCTAssertEqual(out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: 128) }?.sequence, 4)
        XCTAssertEqual(out[0], 4)
    }

    func testCountIsClampedToCapacity() {
        let buffer = BandFrameBuffer()
        write(buffer, [Float](repeating: 5, count: 300))
        var out = [Float](repeating: 0, count: 16)
        let info = out.withUnsafeMutableBufferPointer { buffer.readLatest(into: $0.baseAddress!, capacity: 16) }
        XCTAssertEqual(BandFrameBuffer.capacity, 128)
        XCTAssertEqual(info?.count, 16, "clamped to the reader's capacity (and to 128 on write)")
        XCTAssertEqual(out, [Float](repeating: 5, count: 16))
    }

    func testConcurrentWriterAndReaderNeverSeeATornFrame() {
        let buffer = BandFrameBuffer()
        let frames = 10_000
        let group = DispatchGroup()
        let failures = FailureBox()
        group.enter()
        Thread.detachNewThread {
            var values = [Float](repeating: 0, count: 128)
            for s in 1...frames {
                for i in 0..<128 { values[i] = Float(s) }
                values.withUnsafeBufferPointer { buffer.write($0, timestampNanoseconds: UInt64(s)) }
            }
            group.leave()
        }
        group.enter()
        Thread.detachNewThread {
            var out = [Float](repeating: 0, count: 128)
            var last: UInt64 = 0
            while last < UInt64(frames) {
                guard let info = out.withUnsafeMutableBufferPointer({ buffer.readLatest(into: $0.baseAddress!, capacity: 128) }) else {
                    continue
                }
                if info.sequence <= last { failures.add("sequence went from \(last) to \(info.sequence)") }
                if info.count != 128 { failures.add("count \(info.count)") }
                let expected = Float(info.sequence)
                if out.contains(where: { $0 != expected }) || UInt64(expected) != info.timestampNanoseconds {
                    failures.add("torn frame at \(info.sequence)")
                }
                last = info.sequence
            }
            group.leave()
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success, "30 s ceiling")
        XCTAssertEqual(failures.messages, [])
    }
}

/// Collects failures from background threads (XCTest assertions belong on the test's thread).
private final class FailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func add(_ message: String) { lock.lock(); if stored.count < 10 { stored.append(message) }; lock.unlock() }
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}
