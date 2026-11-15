// OSC-004-T04, T11: OSC learn (specs/274-osc-004-osc-learn, contract L1). The roadmap acceptance, "Learn mode
// records one allowed address and exits after timeout", goes through a receiver with a fake transport (the OSC-008
// allow list, the OSC-009 limiter and the OSC-002 decoder all in the path) and a fake monotonic clock. No
// networking, no wall clock; Linux-safe.
import ParameterGraph
@testable import PerformanceControl
import Synchronization
import XCTest

/// The addresses a learn handler received.
private final class Captured: Sendable {
    private let list = Mutex<[String]>([])
    func append(_ address: String) { list.withLock { $0.append(address) } }
    var all: [String] { list.withLock { $0 } }
}

final class OSCLearnTests: XCTestCase {
    private static let intensity: ParameterID = "effect.bloom.intensity"
    private static let radius: ParameterID = "effect.bloom.radius"
    private static let approvedHost = OSCPeerAddress.ipv4(192, 168, 1, 20)
    private static let otherHost = OSCPeerAddress.ipv4(192, 168, 1, 30)

    private struct Fixture {
        let receiver: OSCReceiver
        let transport: FakeTransport
        let clock: FakeMonotonicClock
        let routable: [ParameterDescriptor]
        let captured = Captured()
    }

    private func makeFixture(limits: OSCRateLimitConfiguration = .default) throws -> Fixture {
        let group = ParameterGroup(id: "effect.bloom", displayName: "Glow")
        let routable: [ParameterDescriptor] = [
            ParameterDescriptor(id: Self.intensity, displayName: "Intensity", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: Self.radius, displayName: "Radius", group: group, unit: .none,
                                kind: .continuous(minimum: 0, maximum: 2, defaultValue: 1), modulation: .continuousDefault),
        ]
        let registry = try ParameterRegistry(descriptors: [OSCReceiverCatalog.testValueDescriptor] + routable)
        let table = OSCParameterRoutes.table(routable: routable, builtInAliases: [], userAliases: [])
        let clock = FakeMonotonicClock()
        let factory = FakeTransportFactory()
        let receiver = OSCReceiver(store: ParameterStore(registry: registry), routes: OSCParameterRoutes.active(table, disabled: []),
                                   limits: limits, clock: clock.clock, scheduler: ManualFlushScheduler(clock: clock).scheduler,
                                   makeTransport: { factory.make() })
        receiver.start(port: 9000)
        let transport = try XCTUnwrap(factory.last)
        transport.send(.ready(port: 9000))
        return Fixture(receiver: receiver, transport: transport, clock: clock, routable: routable)
    }

    private func message(_ address: String, _ arguments: [OSCArgument] = [.float(0.5)]) -> OSCMessage {
        OSCMessage(address: address, arguments: arguments)
    }

    private func send(_ f: Fixture, _ message: OSCMessage, peer: OSCPeerAddress = approvedHost, source: UInt64 = 1) {
        f.transport.send(.datagram(OSCEncoder.encode(message), source: OSCSourceID(rawValue: source), peer: peer))
    }

    private func arm(_ f: Fixture) {
        let captured = f.captured
        f.receiver.dispatcher.armLearn { (address: String) -> Void in captured.append(address) }
    }

    // MARK: Acceptance (T04)

    func testLearnRecordsOneAllowedAddressFromABurstAndExitsAfterTimeoutOtherwise() throws {
        let f = try makeFixture()
        f.receiver.peerAllowlist.setEnabled(true)
        f.receiver.peerAllowlist.approve(Self.approvedHost)
        var session = OSCLearnSession<ParameterID>()
        session.start(target: Self.intensity, now: f.clock.now)
        arm(f)

        // A burst: a disallowed peer first (ignored), then three eligible messages; then a bundle.
        send(f, message("/1/fader9"), peer: Self.otherHost)
        send(f, message("/1/fader3", [.float(0.42)]))
        send(f, message("/1/fader4"))
        send(f, message("/1/fader3", [.float(0.9)]))
        let bundle = OSCPacket.bundle(OSCBundle(timeTag: .immediately, elements: [.message(message("/1/fader5"))]))
        f.transport.send(.datagram(OSCEncoder.encode(bundle), peer: Self.approvedHost))
        XCTAssertEqual(f.captured.all, ["/1/fader3"], "exactly one address, the first allowed one")
        XCTAssertFalse(f.receiver.dispatcher.isLearnArmed, "the capture disarmed itself")
        XCTAssertEqual(f.receiver.peerAllowlist.approved, [Self.approvedHost], "the disallowed peer was never approved")

        f.clock.advance(by: 1_000_000_000)
        let outcome = session.handle(f.captured.all, now: f.clock.now)
        XCTAssertEqual(outcome, .bound(address: "/1/fader3", target: Self.intensity))
        XCTAssertFalse(session.isLearning)

        // Bind as a user alias; the captured message applied no value (R6), the next one drives the parameter.
        let table = OSCParameterRoutes.table(routable: f.routable, builtInAliases: [], userAliases: [])
        let (resolution, aliases) = OSCLearnBinding.bind(address: "/1/fader3", parameter: Self.intensity, table: table, userAliases: [])
        XCTAssertEqual(resolution, .added)
        XCTAssertEqual(f.receiver.store.double(Self.intensity), 0.5, "learning applied nothing")
        let learned = OSCParameterRoutes.table(routable: f.routable, builtInAliases: [], userAliases: aliases)
        f.receiver.dispatcher.setRoutes(OSCParameterRoutes.active(learned, disabled: []))
        send(f, message("/1/fader3", [.float(1)]))
        XCTAssertEqual(f.receiver.store.double(Self.intensity), 1)
        XCTAssertEqual(f.receiver.dispatcher.liveValues[Self.intensity], 1)

        // A second session with no eligible message times out at 10 s on the clock, binding nothing.
        session.start(target: Self.radius, now: f.clock.now)
        f.clock.advance(by: OSCLearnSession<ParameterID>.timeoutNanoseconds - 1)
        XCTAssertNil(session.expire(now: f.clock.now), "still learning just before the deadline")
        f.clock.advance(by: 1)
        XCTAssertEqual(session.handle(["/late"], now: f.clock.now), .timedOut(target: Self.radius), "expires before binding")
        XCTAssertNil(session.handle(["/late"], now: f.clock.now))
    }

    func testCancelAndRestartAndDisarm() throws {
        var session = OSCLearnSession<ParameterID>()
        XCTAssertNil(session.cancel())
        session.start(target: Self.intensity, now: 0)
        session.start(target: Self.radius, now: 5)
        XCTAssertEqual(session.cancel(), .cancelled(target: Self.radius), "the newest request won")
        XCTAssertNil(session.handle(["/a/b"], now: 6), "nothing binds after cancel")

        let f = try makeFixture()
        arm(f)
        f.receiver.dispatcher.disarmLearn()
        send(f, message("/1/fader3"))
        XCTAssertEqual(f.captured.all, [], "a disarmed capture records nothing")
    }

    func testBindingResolutions() {
        let group = ParameterGroup(id: "effect.bloom", displayName: "Glow")
        let routable: [ParameterDescriptor] = [Self.intensity, Self.radius].map { (id: ParameterID) -> ParameterDescriptor in
            ParameterDescriptor(id: id, displayName: id.rawValue, group: group, unit: .none,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault)
        }
        let existing = [OSCRouteAlias(address: "/x", parameter: Self.radius)]
        let table = OSCParameterRoutes.table(routable: routable, builtInAliases: [("/projectm/param/glow.i", Self.intensity)],
                                             userAliases: existing)
        func bind(_ address: String, _ id: ParameterID, _ aliases: [OSCRouteAlias] = existing) -> (OSCLearnResolution, [OSCRouteAlias]) {
            OSCLearnBinding.bind(address: address, parameter: id, table: table, userAliases: aliases)
        }
        XCTAssertEqual(bind("/x", Self.radius).0, .alreadyBound)
        let replaced = bind("/x", Self.intensity)
        XCTAssertEqual(replaced.0, .replaced(previous: Self.radius))
        XCTAssertEqual(replaced.1, [OSCRouteAlias(address: "/x", parameter: Self.intensity)])
        XCTAssertEqual(bind("/projectm/param/glow.i", Self.intensity).0, .unavailable)
        XCTAssertEqual(bind("/a*", Self.intensity).0, .unavailable)
        let full: [OSCRouteAlias] = (0..<OSCRouteAliasRules.maximumUserAliases).map { (i: Int) -> OSCRouteAlias in
            OSCRouteAlias(address: "/f/\(i)", parameter: Self.radius)
        }
        XCTAssertEqual(bind("/new", Self.intensity, full).0, .full)
        XCTAssertEqual(bind("/new", Self.intensity).1.count, 2)
    }

    // MARK: Nothing else gets bound (T11)

    func testMalformedInvalidReservedNonNumericAndRateLimitedMessagesAreNotLearned() throws {
        let f = try makeFixture(limits: OSCRateLimitConfiguration(perSource: OSCRateLimit(perSecond: 1, burst: 8)))
        arm(f)
        f.transport.send(.datagram([0x2F, 0x61, 0x00], source: OSCSourceID(rawValue: 1), peer: Self.approvedHost))         // malformed: no padding
        send(f, message("/a*b"))                                                           // pattern character
        send(f, message("/projectm/test"))                                                 // the app's namespace
        send(f, message("/fader/1", [.string("up")]))                                      // not a number
        send(f, message("/fader/2", [.true]))
        send(f, message("/fader/3", [.float(0.1), .float(0.2)]))                           // two arguments
        send(f, message("/fader/4", [.float(.nan)]))
        XCTAssertEqual(f.captured.all, [], "nothing eligible so far")
        XCTAssertTrue(f.receiver.dispatcher.isLearnArmed, "learn keeps waiting")

        send(f, message("/fader/5"))                                                       // 8th datagram: last token
        XCTAssertEqual(f.captured.all, ["/fader/5"])
        arm(f)
        send(f, message("/fader/6"))                                                       // over the source's limit
        XCTAssertEqual(f.receiver.counters.rateLimited, 1)
        XCTAssertEqual(f.captured.all, ["/fader/5"], "a rate-limited datagram is never learned")
        send(f, message("/fader/7", [.int(1)]), source: 2)                                  // another source, an int
        XCTAssertEqual(f.captured.all, ["/fader/5", "/fader/7"])
    }
}
