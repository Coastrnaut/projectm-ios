// OSC-009-T06, T10: the roadmap acceptance fixture, "Flood fixture cannot starve render loop or
// exceed configured rate" (OSC-009-S1 to S3, R4, R8, R10), and the fast-sweep case of US2.
//
// 100,000 `/projectm/test` datagrams from 3 sources go through the receiver (fake transport, no
// networking) with a fake monotonic clock advancing 1 ms per 50 datagrams (2 simulated seconds) and
// a manual flush scheduler run when due. Work is bounded by counts, never by wall time. Linux-safe.
import ParameterGraph
@testable import PerformanceControl
import Synchronization
import XCTest

/// A clock the test advances by hand.
final class FakeMonotonicClock: Sendable {
    private let value = Mutex<UInt64>(0)
    var now: UInt64 { value.withLock { $0 } }
    func advance(by nanoseconds: UInt64) { value.withLock { $0 += nanoseconds } }
    var clock: OSCMonotonicClock { OSCMonotonicClock(now: { [self] () -> UInt64 in now }) }
}

/// Keeps scheduled flushes until the test runs the due ones.
final class ManualFlushScheduler: Sendable {
    private let queue = Mutex<[(due: UInt64, work: @Sendable () -> Void)]>([])
    private let peak = Mutex(0)
    private let clock: FakeMonotonicClock

    init(clock: FakeMonotonicClock) { self.clock = clock }

    var scheduler: OSCFlushScheduler {
        OSCFlushScheduler(schedule: { [self] (delay: UInt64, work: @escaping @Sendable () -> Void) in
            let due = clock.now + delay
            let count = queue.withLock { q -> Int in
                q.append((due, work))
                return q.count
            }
            peak.withLock { $0 = max($0, count) }
        })
    }

    /// Most flushes ever pending at once.
    var maximumPending: Int { peak.withLock { $0 } }
    var pending: Int { queue.withLock { $0.count } }

    /// Runs every flush due at the clock's current time (a flush may schedule the next one).
    func runDue() {
        while true {
            let now = clock.now
            let work = queue.withLock { q -> (@Sendable () -> Void)? in
                guard let index = q.firstIndex(where: { $0.due <= now }) else { return nil }
                return q.remove(at: index).work
            }
            guard let work else { return }
            work()
        }
    }
}

/// Apply times recorded by a store observer.
final class ApplyLog: Sendable {
    private let times = Mutex<[UInt64]>([])
    func record(_ t: UInt64) { times.withLock { $0.append(t) } }
    var all: [UInt64] { times.withLock { $0 } }
}

final class OSCFloodTests: XCTestCase {
    private let ms: UInt64 = 1_000_000

    private func packet(_ value: Float, address: String = OSCReceiverCatalog.testAddress) -> [UInt8] {
        OSCEncoder.encode(OSCMessage(address: address, arguments: [.float(value)]))
    }

    /// The largest number of applies in any window of `length` ns starting at an apply.
    private func busiestWindow(_ times: [UInt64], length: UInt64) -> Int {
        var best = 0, end = 0
        for start in times.indices {
            while end < times.count && times[end] < times[start] + length { end += 1 }
            best = max(best, end - start)
        }
        return best
    }

    func testFloodFromThreeSourcesNeverExceedsTheConfiguredRates() throws {
        let fake = FakeMonotonicClock()
        let flushes = ManualFlushScheduler(clock: fake)
        let factory = FakeTransportFactory()
        let receiver = OSCReceiver(clock: fake.clock, scheduler: flushes.scheduler, makeTransport: { factory.make() })
        let applies = ApplyLog()
        let observation = receiver.store.observe { change in
            if change.id == OSCReceiverCatalog.testValueID { applies.record(fake.now) }
        }
        defer { observation.cancel() }
        receiver.start(port: 9000)
        let transport = try XCTUnwrap(factory.last)
        transport.send(.ready(port: 9000))

        let total = 100_000
        var lastAdmitted: Double?
        var rateLimitedSoFar = 0
        for i in 0..<total {
            if i > 0 && i % 50 == 0 { fake.advance(by: ms) }
            flushes.runDue()
            XCTAssertLessThanOrEqual(flushes.pending, 1, "never two flushes pending")
            let value = Float(i + 1) / Float(total + 1)
            transport.send(.datagram(packet(value), source: OSCSourceID(rawValue: UInt64(i % 3 + 1))))
            let limited = receiver.counters.rateLimited
            if limited == rateLimitedSoFar { lastAdmitted = Double(value) }
            rateLimitedSoFar = limited
        }
        let floodEnd = fake.now                                  // 1,999 ms
        fake.advance(by: 100 * ms)
        flushes.runDue()

        let c = receiver.counters
        let decoded = c.received - c.rateLimited
        let seconds = Double(floodEnd) / 1e9
        // S1, S3: decoding is bounded by the global allowance; every other datagram cost only the check.
        XCTAssertEqual(c.received, total)
        XCTAssertLessThanOrEqual(Double(decoded), 100 + 500 * seconds + 1, "global: burst 100 + 500/s")
        XCTAssertGreaterThanOrEqual(Double(decoded), 500 * seconds, "the global rate is reached, not undershot")
        XCTAssertEqual(c.rejected, 0)
        XCTAssertEqual(c.ignored, 0)
        XCTAssertGreaterThanOrEqual(c.applied + c.coalesced, decoded, "every decoded message was applied at once or held (flushes add applies)")
        // S1: applied updates never exceed burst 10 + 60/s in any window.
        let times = applies.all
        XCTAssertEqual(times.count, c.applied)
        for (length, label) in [(ms, "1 ms"), (100 * ms, "100 ms"), (1_000 * ms, "1 s")] {
            let bound = 10 + 60 * Double(length) / 1e9
            XCTAssertLessThanOrEqual(Double(busiestWindow(times, length: length)), bound, "applies in any \(label) window")
        }
        XCTAssertLessThanOrEqual(Double(c.applied), 10 + 60 * (seconds + 0.1) + 1)
        XCTAssertEqual(flushes.maximumPending, 1, "one deferred flush at a time")
        // S2: the last value that passed the datagram limits is the final state.
        XCTAssertEqual(receiver.testValue, try XCTUnwrap(lastAdmitted))
        XCTAssertEqual(receiver.dispatcher.heldCount, 0)

        // S2: a value sent after the flood is applied.
        transport.send(.datagram(packet(0.125), source: OSCSourceID(rawValue: 2)))
        flushes.runDue()
        XCTAssertEqual(receiver.testValue, 0.125)
    }

    func testIgnoredAndMalformedMessagesTakeNoTargetSlot() {
        let fake = FakeMonotonicClock()
        let flushes = ManualFlushScheduler(clock: fake)
        let wide = OSCRateLimitConfiguration(perSource: OSCRateLimit(perSecond: 1_000, burst: 1_000),
                                             global: OSCRateLimit(perSecond: 1_000, burst: 1_000))
        let dispatcher = OSCDispatcher(store: OSCReceiverCatalog.makeStore(), routes: OSCReceiverCatalog.routes,
                                       limits: wide, clock: fake.clock, scheduler: flushes.scheduler)
        for _ in 0..<50 { dispatcher.handle(packet(0.5, address: "/unknown")) }
        for _ in 0..<50 { dispatcher.handle([0x2F, 0x00]) }                                  // malformed
        for _ in 0..<50 { dispatcher.handle(OSCEncoder.encode(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: []))) }
        var applied = 0
        for i in 0..<10 {
            if case .applied = dispatcher.handle(packet(Float(i) / 10)) { applied += 1 }
        }
        XCTAssertEqual(applied, 10, "the target's full burst is still available (OSC-009-R4)")
        XCTAssertEqual(dispatcher.handle(packet(0.95)), .coalesced(OSCReceiverCatalog.testValueID))
        let c = dispatcher.counters
        XCTAssertEqual(c.ignored, 100)
        XCTAssertEqual(c.rejected, 50)
        XCTAssertEqual(c.coalesced, 1)
    }

    func testFastSweepEndsAtTheLastValueWithoutAnotherMessage() {
        let fake = FakeMonotonicClock()
        let flushes = ManualFlushScheduler(clock: fake)
        let wide = OSCRateLimitConfiguration(perSource: OSCRateLimit(perSecond: 1_000, burst: 1_000),
                                             global: OSCRateLimit(perSecond: 1_000, burst: 1_000))
        let dispatcher = OSCDispatcher(store: OSCReceiverCatalog.makeStore(), routes: OSCReceiverCatalog.routes,
                                       limits: wide, clock: fake.clock, scheduler: flushes.scheduler)
        for i in 1...1_000 { dispatcher.handle(packet(Float(i) / 1_000)) }
        XCTAssertEqual(dispatcher.counters.applied, 10)
        XCTAssertEqual(dispatcher.counters.coalesced, 990)
        XCTAssertEqual(flushes.pending, 1)
        XCTAssertNotEqual(dispatcher.store.double(OSCReceiverCatalog.testValueID), 1)
        fake.advance(by: 16 * ms)
        flushes.runDue()
        XCTAssertNotEqual(dispatcher.store.double(OSCReceiverCatalog.testValueID), 1, "not before the next slot")
        fake.advance(by: 1 * ms)
        flushes.runDue()
        XCTAssertEqual(dispatcher.store.double(OSCReceiverCatalog.testValueID), 1, "the sweep's last value (US2)")
        XCTAssertEqual(dispatcher.counters.applied, 11)
        XCTAssertEqual(flushes.pending, 0, "nothing left to flush")
    }

    func testStopDiscardsHeldValuesAndRestartStartsWithFullBuckets() throws {
        let fake = FakeMonotonicClock()
        let flushes = ManualFlushScheduler(clock: fake)
        let factory = FakeTransportFactory()
        let receiver = OSCReceiver(clock: fake.clock, scheduler: flushes.scheduler, makeTransport: { factory.make() })
        receiver.start(port: 9000)
        var transport = try XCTUnwrap(factory.last)
        transport.send(.ready(port: 9000))
        for i in 1...60 { transport.send(.datagram(packet(Float(i) / 100))) }
        XCTAssertEqual(receiver.counters.rateLimited, 10, "unattributed source: burst 50")
        XCTAssertEqual(receiver.dispatcher.heldCount, 1)
        let held = receiver.testValue
        receiver.stop()
        XCTAssertEqual(receiver.dispatcher.heldCount, 0, "a stop discards held values")
        fake.advance(by: 100 * ms)
        flushes.runDue()
        XCTAssertEqual(receiver.testValue, held, "nothing is applied after the stop")

        receiver.start(port: 9000)
        transport = try XCTUnwrap(factory.last)
        transport.send(.ready(port: 9000))
        for i in 1...50 { transport.send(.datagram(packet(Float(i) / 100))) }
        XCTAssertEqual(receiver.counters.rateLimited, 10, "full buckets after a restart; counters persist")
    }
}
