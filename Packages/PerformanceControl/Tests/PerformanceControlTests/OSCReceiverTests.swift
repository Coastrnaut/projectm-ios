// OSC-001-T10: the receiver's lifecycle with a fake transport (OSC-001-R1 to R3; contract C5;
// research OSC-001-D5). Linux-safe: no networking.
@testable import PerformanceControl
import Synchronization
import XCTest

/// Records calls; the test delivers events by hand. `stop()` confirms `.cancelled` synchronously
/// unless `holdCancel` is set.
final class FakeTransport: OSCDatagramTransport, Sendable {
    private struct State {
        var starts: [UInt16] = []
        var stops = 0
        var events: (@Sendable (OSCTransportEvent) -> Void)?
        var holdCancel = false
    }
    private let state = Mutex(State())

    var starts: [UInt16] { state.withLock { $0.starts } }
    var stops: Int { state.withLock { $0.stops } }
    var holdCancel: Bool {
        get { state.withLock { $0.holdCancel } }
        set { state.withLock { $0.holdCancel = newValue } }
    }

    func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
        state.withLock { s in
            s.starts.append(port)
            s.events = events
        }
    }

    func stop() {
        let (hold, events) = state.withLock { s -> (Bool, (@Sendable (OSCTransportEvent) -> Void)?) in
            s.stops += 1
            return (s.holdCancel, s.events)
        }
        if !hold { events?(.cancelled) }
    }

    func send(_ event: OSCTransportEvent) {
        let events = state.withLock { $0.events }
        events?(event)
    }
}

/// Hands out fakes in order and remembers them.
final class FakeTransportFactory: Sendable {
    private let made = Mutex<[FakeTransport]>([])
    var transports: [FakeTransport] { made.withLock { $0 } }
    var last: FakeTransport? { transports.last }

    func make() -> (any OSCDatagramTransport)? {
        let t = FakeTransport()
        made.withLock { $0.append(t) }
        return t
    }
}

final class OSCReceiverTests: XCTestCase {
    private let packet = OSCEncoder.encode(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(0.5)]))

    private func makeReceiver() -> (OSCReceiver, FakeTransportFactory) {
        let factory = FakeTransportFactory()
        return (OSCReceiver(makeTransport: { factory.make() }), factory)
    }

    func testOffByDefaultAndListensAfterReady() throws {
        let (receiver, factory) = makeReceiver()
        XCTAssertEqual(receiver.state, .off)
        XCTAssertTrue(factory.transports.isEmpty, "nothing is opened before start")
        receiver.start(port: 9000)
        XCTAssertEqual(receiver.state, .starting(port: 9000))
        let t = try XCTUnwrap(factory.last)
        XCTAssertEqual(t.starts, [9000])
        t.send(.ready(port: 9000))
        XCTAssertEqual(receiver.state, .listening(port: 9000))
        XCTAssertTrue(receiver.state.isListening)
    }

    func testDatagramUpdatesTestValueAndStopClosesAfterCancel() throws {
        let (receiver, factory) = makeReceiver()
        receiver.start(port: 9000)
        let t = try XCTUnwrap(factory.last)
        t.send(.ready(port: 9000))
        t.send(.datagram(packet))
        XCTAssertEqual(receiver.testValue, 0.5)

        t.holdCancel = true
        receiver.stop()
        XCTAssertEqual(t.stops, 1)
        XCTAssertEqual(receiver.state, .stopping, "off only after the transport confirms")
        t.send(.datagram(OSCEncoder.encode(OSCMessage(address: OSCReceiverCatalog.testAddress, arguments: [.float(0.9)]))))
        XCTAssertEqual(receiver.testValue, 0.5, "nothing is applied once stop was requested")
        t.send(.cancelled)
        XCTAssertEqual(receiver.state, .off)
        XCTAssertEqual(receiver.counters.received, 1)
    }

    func testStaleEventsFromACancelledTransportAreIgnored() throws {
        let (receiver, factory) = makeReceiver()
        receiver.start(port: 9000)
        let first = try XCTUnwrap(factory.last)
        receiver.stop()                       // fake confirms at once
        XCTAssertEqual(receiver.state, .off)
        first.send(.ready(port: 9000))        // late ready from the cancelled listener
        XCTAssertEqual(receiver.state, .off)
        first.send(.datagram(packet))
        XCTAssertEqual(receiver.testValue, 0)
    }

    func testPortChangeCancelsTheOldTransportBeforeOpeningTheNew() throws {
        let (receiver, factory) = makeReceiver()
        receiver.start(port: 9000)
        let first = try XCTUnwrap(factory.last)
        first.send(.ready(port: 9000))
        first.holdCancel = true
        receiver.start(port: 8000)
        XCTAssertEqual(first.stops, 1)
        XCTAssertEqual(factory.transports.count, 1, "the new port opens only after the old one is cancelled")
        XCTAssertEqual(receiver.state, .starting(port: 8000))
        first.send(.cancelled)
        XCTAssertEqual(factory.transports.count, 2)
        let second = try XCTUnwrap(factory.last)
        XCTAssertEqual(second.starts, [8000])
        second.send(.ready(port: 8000))
        XCTAssertEqual(receiver.state, .listening(port: 8000))
        receiver.start(port: 8000)
        XCTAssertEqual(factory.transports.count, 2, "starting the same port again is a no-op")
    }

    func testFailureStopsTheTransportAndDoesNotRetry() throws {
        let (receiver, factory) = makeReceiver()
        receiver.start(port: 9000)
        let t = try XCTUnwrap(factory.last)
        t.send(.failed(.portInUse))
        XCTAssertEqual(receiver.state, .failed(port: 9000, .portInUse))
        XCTAssertEqual(t.stops, 1)
        XCTAssertEqual(factory.transports.count, 1, "no automatic retry")
        XCTAssertEqual(t.starts, [9000])
        receiver.stop()
        XCTAssertEqual(receiver.state, .off)
        receiver.start(port: 9001)
        XCTAssertEqual(factory.transports.count, 2, "an explicit start tries again")
    }

    func testNoTransportFailsAsUnavailable() {
        let receiver = OSCReceiver(makeTransport: { nil })
        receiver.start(port: 9000)
        XCTAssertEqual(receiver.state, .failed(port: 9000, .unavailable))
        receiver.stop()
        XCTAssertEqual(receiver.state, .off)
    }

    func testStopWhenOffIsANoOpAndHandlersSeeEveryChange() throws {
        let (receiver, factory) = makeReceiver()
        let seen = Mutex<[OSCReceiverState]>([])
        receiver.onStateChange { state in seen.withLock { $0.append(state) } }
        receiver.stop()
        XCTAssertTrue(seen.withLock { $0 }.isEmpty)
        receiver.start(port: 9000)
        try XCTUnwrap(factory.last).send(.ready(port: 9000))
        receiver.stop()
        XCTAssertEqual(seen.withLock { $0 }, [.starting(port: 9000), .listening(port: 9000), .stopping, .off])
    }

    func testCountersSeeOversizedAndNonLocal() throws {
        let (receiver, factory) = makeReceiver()
        receiver.start(port: 9000)
        let t = try XCTUnwrap(factory.last)
        t.send(.ready(port: 9000))
        t.send(.oversized(4000))
        t.send(.droppedNonLocal)
        XCTAssertEqual(receiver.counters.rejectedByReason, ["oversized": 1])
        XCTAssertEqual(receiver.counters.droppedNonLocal, 1)
    }
}
