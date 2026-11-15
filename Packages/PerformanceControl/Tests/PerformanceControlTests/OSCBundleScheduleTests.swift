// OSC-006-T05, T08: timestamped bundles on injected clocks (OSC-006-R1 to R11, S1 to S3, S5; contract B1).
// The wall clock is the fake monotonic clock plus a fixed NTP base, and wake-ups run only when the fake clock
// reaches them, so every assertion is about ticks, never about wall time.
import ParameterGraph
@testable import PerformanceControl
import Synchronization
import XCTest

/// Monotonic nanoseconds advanced by hand; scheduled work runs when the clock reaches its time.
private final class ScheduledTime: Sendable {
    private struct Pending {
        let at: UInt64
        let order: Int
        let work: @Sendable () -> Void
    }

    private let nanoseconds = Mutex<UInt64>(1_000_000_000)
    private let pending = Mutex<(items: [Pending], order: Int)>(([], 0))
    /// The wall clock at monotonic 0 (2025, NTP).
    static let base = OSCTimeTag(seconds: 3_950_000_000, fraction: 0)

    var now: UInt64 { nanoseconds.withLock { $0 } }
    var clock: OSCMonotonicClock { OSCMonotonicClock(now: { [self] () -> UInt64 in now }) }
    var wallClock: OSCWallClock {
        OSCWallClock(now: { [self] () -> OSCTimeTag in Self.base.adding(nanoseconds: Int64(now)) })
    }
    var scheduler: OSCFlushScheduler {
        OSCFlushScheduler(schedule: { [self] (delay: UInt64, work: @escaping @Sendable () -> Void) in
            pending.withLock { p in
                p.order += 1
                p.items.append(Pending(at: now + delay, order: p.order, work: work))
            }
        })
    }

    /// The wall-clock tag `offset` nanoseconds from now.
    func tag(_ offsetMilliseconds: Int64) -> OSCTimeTag {
        Self.base.adding(nanoseconds: Int64(now) + offsetMilliseconds * 1_000_000)
    }

    /// Moves the clock to `now + delta`, running due work in time order at its own time.
    func advance(byMilliseconds delta: UInt64) {
        let target = now + delta * 1_000_000
        while true {
            let next = pending.withLock { p -> Pending? in
                guard let index = p.items.indices.filter({ p.items[$0].at <= target })
                    .min(by: { (p.items[$0].at, p.items[$0].order) < (p.items[$1].at, p.items[$1].order) }) else { return nil }
                return p.items.remove(at: index)
            }
            guard let next else { break }
            nanoseconds.withLock { $0 = max($0, next.at) }
            next.work()
        }
        nanoseconds.withLock { $0 = target }
    }
}

final class OSCBundleScheduleTests: XCTestCase {
    private let a: ParameterID = "osc.bundle.a"
    private let b: ParameterID = "osc.bundle.b"
    private let ms: UInt64 = 1_000_000

    private func makeDispatcher(timing: OSCBundleTiming = .default) throws -> (OSCDispatcher, ParameterStore, ScheduledTime) {
        let group = ParameterGroup(id: "osc.bundle", displayName: "OSC")
        let registry = try ParameterRegistry(descriptors: [a, b].map { (id: ParameterID) -> ParameterDescriptor in
            ParameterDescriptor(id: id, displayName: id.rawValue, group: group, unit: .none,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0), modulation: ModulationPolicy(isModulatable: false, mixModes: [], allowsExternalControl: true))
        })
        let store = ParameterStore(registry: registry)
        let time = ScheduledTime()
        let dispatcher = OSCDispatcher(store: store, routes: [OSCRoute(address: "/a", parameter: a), OSCRoute(address: "/b", parameter: b)],
                                       clock: time.clock, scheduler: time.scheduler,
                                       wallClock: time.wallClock, timing: timing)
        return (dispatcher, store, time)
    }

    private func bundle(_ tag: OSCTimeTag, _ elements: [OSCPacket]) -> OSCPacket {
        .bundle(OSCBundle(timeTag: tag, elements: elements))
    }

    private func set(_ address: String, _ value: Float) -> OSCPacket {
        .message(OSCMessage(address: address, arguments: [.float(value)]))
    }

    private func send(_ dispatcher: OSCDispatcher, _ packet: OSCPacket) -> OSCDispatchOutcome {
        dispatcher.handle(OSCEncoder.encode(packet))
    }

    // MARK: US1 (S1, S2)

    /// The roadmap acceptance: two scheduled events execute in deterministic timestamp order.
    func testTwoScheduledEventsExecuteInTimestampOrderAtTheirTicks() throws {
        let (dispatcher, store, time) = try makeDispatcher()
        var applied: [Double] = []
        let log = Mutex<[Double]>([])
        let watched = a
        let observation = store.observe { change in
            if change.id == watched, let value = change.newValue.doubleValue { log.withLock { $0.append(value) } }
        }
        // Received in reverse order: t+20 ms first, then t+10 ms.
        XCTAssertEqual(send(dispatcher, bundle(time.tag(20), [set("/a", 0.75)])), .bundle([.scheduled]))
        XCTAssertEqual(send(dispatcher, bundle(time.tag(10), [set("/a", 0.25)])), .bundle([.scheduled]))
        XCTAssertEqual(store.double(a), 0, "nothing applies at receipt")
        XCTAssertEqual(dispatcher.pendingScheduledCount, 2)

        time.advance(byMilliseconds: 9)
        XCTAssertEqual(store.double(a), 0, "not before t+10 ms")
        time.advance(byMilliseconds: 1)
        XCTAssertEqual(store.double(a), 0.25, "t+10 ms applies first")
        time.advance(byMilliseconds: 9)
        XCTAssertEqual(store.double(a), 0.25)
        time.advance(byMilliseconds: 1)
        XCTAssertEqual(store.double(a), 0.75, "then t+20 ms")
        applied = log.withLock { $0 }
        XCTAssertEqual(applied, [0.25, 0.75])
        XCTAssertEqual(dispatcher.pendingScheduledCount, 0)
        let c = dispatcher.counters
        XCTAssertEqual(c.scheduled, 2)
        XCTAssertEqual(c.applied, 2)
        XCTAssertEqual(c.bundles, 2)
        _ = observation
    }

    func testEqualTagsKeepArrivalOrderAndImmediateAppliesAtOnce() throws {
        let (dispatcher, store, time) = try makeDispatcher()
        let tag = time.tag(15)
        _ = send(dispatcher, bundle(tag, [set("/a", 0.1), set("/a", 0.2)]))
        _ = send(dispatcher, bundle(tag, [set("/a", 0.3)]))
        XCTAssertEqual(send(dispatcher, bundle(.immediately, [set("/b", 0.5)])), .bundle([.applied(b, 0.5)]))
        XCTAssertEqual(store.double(b), 0.5, "the immediate tag applies at receipt")
        let log = Mutex<[Double]>([])
        let watched = a
        let observation = store.observe { change in
            if change.id == watched, let value = change.newValue.doubleValue { log.withLock { $0.append(value) } }
        }
        time.advance(byMilliseconds: 15)
        XCTAssertEqual(log.withLock { $0 }.map { Float($0) }, [0.1, 0.2, 0.3], "equal tags: arrival order")
        _ = observation
    }

    func testNestedBundlesUseTheLaterOfTheirOwnAndTheEnclosingTag() throws {
        let (dispatcher, store, time) = try makeDispatcher()
        // Outer t+20: /a 0.2, inner tagged t+5 (earlier: treated as t+20) /a 0.4, inner t+30 /b 0.6,
        // then outer's own /b 0.1 after the nested ones.
        let packet = bundle(time.tag(20), [
            set("/a", 0.2),
            bundle(time.tag(5), [set("/a", 0.4)]),
            bundle(time.tag(30), [set("/b", 0.6)]),
            bundle(.immediately, [set("/b", 0.1)]),
        ])
        XCTAssertEqual(send(dispatcher, packet), .bundle([.scheduled, .scheduled, .scheduled, .scheduled]))
        time.advance(byMilliseconds: 19)
        XCTAssertEqual(store.double(a), 0, "the inner t+5 bundle never runs before its container")
        time.advance(byMilliseconds: 1)
        XCTAssertEqual(Float(try XCTUnwrap(store.double(a))), 0.4, "t+20: packet order, the inner one second")
        XCTAssertEqual(Float(try XCTUnwrap(store.double(b))), 0.1, "the inner 'immediately' takes the outer tag")
        time.advance(byMilliseconds: 10)
        XCTAssertEqual(Float(try XCTUnwrap(store.double(b))), 0.6, "t+30 last")
    }

    // MARK: US2 (S3, S5)

    func testLatePolicy() throws {
        let (dispatcher, store, time) = try makeDispatcher()
        XCTAssertEqual(send(dispatcher, bundle(time.tag(-15), [set("/a", 0.1)])), .bundle([.applied(a, Double(Float(0.1)))]),
                       "within the 20 ms tolerance: on time")
        XCTAssertEqual(dispatcher.counters.lateApplied, 0)
        XCTAssertEqual(send(dispatcher, bundle(time.tag(-500), [set("/a", 0.2)])), .bundle([.applied(a, Double(Float(0.2)))]),
                       "500 ms late: applied now")
        XCTAssertEqual(dispatcher.counters.lateApplied, 1)
        XCTAssertEqual(send(dispatcher, bundle(time.tag(-2_000), [set("/a", 0.9)])), .bundle([.dropped(.tooLate)]),
                       "2 s late: dropped")
        XCTAssertEqual(dispatcher.counters.lateDropped, 1)
        XCTAssertEqual(Float(try XCTUnwrap(store.double(a))), 0.2)
        XCTAssertEqual(dispatcher.counters.applied, 2)
    }

    func testHorizonAndCapacityBounds() throws {
        let timing = OSCBundleTiming(onTimeTolerance: 20 * ms, maximumLateness: 1_000 * ms, horizon: 10_000 * ms, capacity: 3)
        let (dispatcher, store, time) = try makeDispatcher(timing: timing)
        XCTAssertEqual(send(dispatcher, bundle(time.tag(30_000), [set("/a", 1)])), .bundle([.dropped(.beyondHorizon)]))
        XCTAssertEqual(dispatcher.counters.beyondHorizon, 1)
        XCTAssertEqual(send(dispatcher, bundle(time.tag(10_000), [set("/a", 0.5)])), .bundle([.scheduled]), "the horizon itself fits")
        XCTAssertEqual(send(dispatcher, bundle(time.tag(50), [set("/b", 0.3), set("/b", 0.4)])), .bundle([.scheduled, .scheduled]))
        // Full (3): the newest datagram's future part is dropped whole; its immediate part still applies.
        let mixed = bundle(.immediately, [set("/a", 0.05), bundle(time.tag(40), [set("/b", 0.9)])])
        XCTAssertEqual(send(dispatcher, mixed), .bundle([.applied(a, Double(Float(0.05))), .dropped(.queueFull)]))
        XCTAssertEqual(dispatcher.counters.scheduleOverflow, 1)
        XCTAssertEqual(dispatcher.pendingScheduledCount, 3)
        time.advance(byMilliseconds: 50)
        XCTAssertEqual(Float(try XCTUnwrap(store.double(b))), 0.4, "the earlier cues survive the overflow")
        time.advance(byMilliseconds: 10_000)
        XCTAssertEqual(store.double(a), 0.5)
    }

    func testClearDropsEverythingPendingAndAStaleWakeAppliesNothing() throws {
        let (dispatcher, store, time) = try makeDispatcher()
        _ = send(dispatcher, bundle(time.tag(10), [set("/a", 0.5)]))
        dispatcher.clearScheduled()
        XCTAssertEqual(dispatcher.pendingScheduledCount, 0)
        time.advance(byMilliseconds: 100)
        XCTAssertEqual(store.double(a), 0)
    }

    func testReceiverStopClearsTheSchedule() throws {
        let time = ScheduledTime()
        let receiver = OSCReceiver(store: OSCReceiverCatalog.makeStore(), clock: time.clock, scheduler: time.scheduler,
                                   wallClock: time.wallClock, makeTransport: { nil })
        let packet = bundle(time.tag(10), [.message(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(0.5)]))])
        XCTAssertEqual(receiver.dispatcher.handle(OSCEncoder.encode(packet)), .bundle([.scheduled]))
        receiver.stop()
        XCTAssertEqual(receiver.dispatcher.pendingScheduledCount, 0)
        time.advance(byMilliseconds: 20)
        XCTAssertEqual(receiver.testValue, 0, "nothing applies after the switch went off")
    }

    /// R9: a due message passes the routes and the per-target limiter at dispatch, like an immediate one.
    func testScheduledMessagesUseTheRoutesAndLimiterAtTheirDueTime() throws {
        let (dispatcher, store, time) = try makeDispatcher()
        _ = send(dispatcher, bundle(time.tag(10), [set("/a", 0.5), set("/b", 0.7)]))
        dispatcher.setRoutes([OSCRoute(address: "/a", parameter: a)])          // /b removed before it is due
        time.advance(byMilliseconds: 10)
        XCTAssertEqual(store.double(a), 0.5)
        XCTAssertEqual(store.double(b), 0, "the route table at the due time decides")
        XCTAssertEqual(dispatcher.counters.unknownAddresses, 1)

        let limited = OSCDispatcher(store: store, routes: [OSCRoute(address: "/a", parameter: a)],
                                    limits: OSCRateLimitConfiguration(perTarget: OSCRateLimit(perSecond: 1, burst: 1)),
                                    clock: time.clock, scheduler: time.scheduler, wallClock: time.wallClock)
        let outcome = limited.handle(OSCEncoder.encode(bundle(.immediately, [set("/a", 0.1), set("/a", 0.2)])))
        XCTAssertEqual(outcome, .bundle([.applied(a, Double(Float(0.1))), .coalesced(a)]))
    }

    func testTimeTagArithmeticIsEraSafe() {
        let late2036 = OSCTimeTag(seconds: 0xFFFF_FFFF, fraction: 0)
        let after = late2036.adding(nanoseconds: 2_000_000_000)
        XCTAssertEqual(after.seconds, 1, "wraps into the next era")
        XCTAssertEqual(after.nanoseconds(since: late2036), 2_000_000_000)
        XCTAssertEqual(late2036.nanoseconds(since: after), -2_000_000_000)
        let mapping = OSCTimeMapping(monotonicNow: 5_000, wallNow: late2036)
        XCTAssertNil(mapping.due(for: .immediately))
        XCTAssertEqual(mapping.due(for: after), 2_000_005_000)
        XCTAssertNil(mapping.due(for: late2036.adding(nanoseconds: -1_000_000)), "late: no due time")
        XCTAssertEqual(mapping.offset(for: late2036.adding(nanoseconds: -3_000_000_000)), -3_000_000_000,
                       "lateness is not limited by the monotonic clock's origin")
        let ntp = OSCTimeTag(ntpSeconds: 3_950_000_000.5)
        XCTAssertEqual(ntp.seconds, 3_950_000_000)
        XCTAssertEqual(ntp.fraction, 0x8000_0000)
    }
}
