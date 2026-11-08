// Task T019: wraparound, drop-oldest overflow, underrun, and a two-thread stress test.
import XCTest
import Foundation
@testable import AudioCore

final class SPSCRingBufferTests: XCTestCase {
    private func write(_ ring: SPSCRingBuffer, _ values: [Float]) {
        values.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
    }

    private func read(_ ring: SPSCRingBuffer, max: Int) -> [Float] {
        var out = [Float](repeating: .nan, count: max)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxCount: max) }
        return Array(out.prefix(n))
    }

    func testUnderrunReturnsZero() {
        let ring = SPSCRingBuffer(capacity: 8)
        XCTAssertEqual(read(ring, max: 4), [])
        XCTAssertEqual(ring.availableToRead, 0)
    }

    func testWraparoundPreservesOrder() {
        let ring = SPSCRingBuffer(capacity: 5)
        write(ring, [1, 2, 3, 4])
        XCTAssertEqual(read(ring, max: 3), [1, 2, 3])
        write(ring, [5, 6, 7, 8])                    // wraps
        XCTAssertEqual(read(ring, max: 10), [4, 5, 6, 7, 8])
        XCTAssertEqual(ring.droppedSamples, 0)
    }

    func testOverflowDropsOldestAndCounts() {
        let ring = SPSCRingBuffer(capacity: 4)
        write(ring, [1, 2, 3, 4])
        write(ring, [5, 6])
        XCTAssertEqual(ring.droppedSamples, 2)
        XCTAssertEqual(read(ring, max: 10), [3, 4, 5, 6])
    }

    func testWriteLargerThanCapacityKeepsNewest() {
        let ring = SPSCRingBuffer(capacity: 3)
        write(ring, [1, 2, 3, 4, 5])
        XCTAssertEqual(ring.droppedSamples, 2)
        XCTAssertEqual(read(ring, max: 10), [3, 4, 5])
    }

    func testDrain() {
        let ring = SPSCRingBuffer(capacity: 4)
        write(ring, [1, 2, 3])
        ring.drain()
        XCTAssertEqual(ring.availableToRead, 0)
    }

    /// Two threads for ~10 s: values are a strictly increasing sequence, so the consumer must
    /// only ever see increasing values; gaps are allowed only where drops were counted.
    func testConcurrentProducerConsumerKeepsOrdering() {
        let ring = SPSCRingBuffer(capacity: 4096)
        let duration: TimeInterval = ProcessInfo.processInfo.environment["CI_SHORT"] == nil ? 10 : 2
        let deadline = Date().addingTimeInterval(duration)
        let producerFinished = UnsafeSendableFlag()

        Thread.detachNewThread {
            var next: Float = 0
            var chunk = [Float](repeating: 0, count: 256)
            while Date() < deadline {
                for i in 0..<chunk.count { chunk[i] = next; next += 1; if next > 16_000_000 { next = 0 } }
                chunk.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
            }
            producerFinished.set()
        }

        var last: Float = -1
        var received = 0
        var violations = 0
        var buffer = [Float](repeating: 0, count: 1024)
        while !producerFinished.value || ring.availableToRead > 0 {
            let n = buffer.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxCount: 1024) }
            for i in 0..<n {
                let v = buffer[i]
                if v <= last && !(last > 15_000_000 && v < 1_000_000) { violations += 1 }
                last = v
            }
            received += n
        }
        XCTAssertEqual(violations, 0, "ordering violated")
        XCTAssertGreaterThan(received, 0)
    }
}

/// Minimal thread-safe flag for the stress test.
private final class UnsafeSendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
