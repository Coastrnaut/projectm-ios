// OSC-004-T08: OSC learn in the app (specs/274-osc-004-osc-learn, contract L2) with the DEBUG stand-in OSC transport
// (`UITestFakeOSC.Transport`, no socket), an injected clock and a manual timer. Datagrams go through the receiver's
// real path (allow list, limiter, decoder, routes); the learned alias is stored and drives the live value.
import ParameterGraph
import PerformanceControl
import Synchronization
import VisualParameters
import XCTest
@testable import projectM_iOS

/// The fake transports a receiver made.
private final class Transports: Sendable {
    private let list = Mutex<[UITestFakeOSC.Transport]>([])
    func make() -> UITestFakeOSC.Transport {
        let transport = UITestFakeOSC.Transport()
        list.withLock { $0.append(transport) }
        return transport
    }
    var last: UITestFakeOSC.Transport? { list.withLock { $0.last } }
}

@MainActor
final class OSCLearnCoordinatorTests: XCTestCase {
    private static let intensity: ParameterID = VisualParameterIDs.bloomIntensity
    private static let radius: ParameterID = VisualParameterIDs.bloomRadius
    private static let peer = OSCPeerAddress.ipv4(192, 168, 1, 20)

    @MainActor private final class Harness {
        let defaults: UserDefaults
        let settings: AppSettings
        let transports = Transports()
        var receiver: OSCReceiver!
        var osc: OSCReceiverCoordinator!
        var routes: OSCRoutesCoordinator!
        var learn: OSCLearnCoordinator!
        var now: UInt64 = 1_000
        var timers: [(UInt64, @MainActor () -> Void)] = []
        var announced: [String] = []

        init(defaults: UserDefaults) {
            self.defaults = defaults
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        }
    }

    private func makeHarness() throws -> Harness {
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: "OSCLearnCoordinatorTests-\(UUID().uuidString)"))
        let h = Harness(defaults: defaults)
        let routable: [ParameterDescriptor] = OSCRoutesCoordinator.routable()
        let transports = h.transports
        h.receiver = OSCReceiver(store: OSCRoutesCoordinator.makeStore(routable: routable),
                                 routes: OSCRoutesCoordinator.initialRoutes(routable: routable, defaults: defaults),
                                 makeTransport: { () -> (any OSCDatagramTransport)? in transports.make() })
        h.osc = OSCReceiverCoordinator(settings: h.settings, receiver: h.receiver)
        h.routes = OSCRoutesCoordinator(routable: routable, defaults: defaults) { [weak osc = h.osc] (r: [OSCRoute]) -> Void in osc?.setRoutes(r) }
        h.osc.routes = h.routes
        h.learn = OSCLearnCoordinator(osc: h.osc, routes: h.routes,
                                      announce: { [unowned h] (text: String) -> Void in h.announced.append(text) },
                                      clock: { [unowned h] () -> UInt64 in h.now },
                                      scheduler: { [unowned h] (delay: UInt64, work: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) in
                                          h.timers.append((delay, work))
                                          return { () -> Void in }
                                      })
        h.osc.learn = h.learn
        return h
    }

    private func turnOn(_ h: Harness) async throws {
        h.osc.setEnabled(true)
        try await settle { h.osc.state.isListening }
        XCTAssertTrue(h.learn.canLearn)
    }

    private func send(_ h: Harness, _ address: String, _ value: Float = 0.5, peer: OSCPeerAddress = peer) {
        let bytes: [UInt8] = OSCEncoder.encode(OSCMessage(address: address, arguments: [.float(value)]))
        h.transports.last?.deliver(.datagram(bytes, source: OSCSourceID(rawValue: 1), peer: peer))
    }

    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testArmInjectBurstBindsOneAliasThatPersistsAndDrivesTheGlow() async throws {
        let h = try makeHarness()
        h.learn.startLearning(Self.intensity)
        XCTAssertFalse(h.learn.isLearning, "Learn needs a listening receiver (R2)")
        XCTAssertEqual(h.learn.statusText, OSCLearnCoordinator.offText)
        try await turnOn(h)

        h.learn.startLearning(Self.intensity)
        XCTAssertEqual(h.learn.learningTarget, Self.intensity)
        XCTAssertEqual(h.timers.first?.0, OSCLearnSession<ParameterID>.timeoutNanoseconds, "a 10 s timer")
        XCTAssertEqual(h.announced.last, "Send a message from your OSC controller to bind Glow intensity.")
        send(h, "/fader/7", 0.42)
        send(h, "/fader/8")
        send(h, "/fader/7", 0.9)
        try await settle { !h.learn.isLearning }

        XCTAssertEqual(h.learn.statusText, "Glow intensity now listens to /fader/7.")
        XCTAssertEqual(h.announced.last, h.learn.statusText)
        XCTAssertEqual(h.defaults.stringArray(forKey: OSCRoutesCoordinator.aliasesKey), ["/fader/7=" + Self.intensity.rawValue],
                       "exactly one alias stored")
        XCTAssertNil(h.osc.liveValues[Self.intensity], "learning applied no value")
        send(h, "/fader/7", 1)
        try await settle { h.osc.liveValues[Self.intensity] != nil }
        XCTAssertEqual(h.osc.liveValues[Self.intensity], 1, "the learned route drives the glow at its maximum")

        // A relaunch reads the alias back.
        let reloaded = OSCRoutesCoordinator(routable: OSCRoutesCoordinator.routable(), defaults: h.defaults)
        XCTAssertTrue(reloaded.rows.contains { (row: OSCRouteRow) -> Bool in row.address == "/fader/7" && row.origin == .userAlias })
    }

    func testTimeoutCancelReplaceAndReceiverOff() async throws {
        let h = try makeHarness()
        try await turnOn(h)

        h.learn.startLearning(Self.intensity)
        h.now += OSCLearnSession<ParameterID>.timeoutNanoseconds
        h.timers.last?.1()
        XCTAssertFalse(h.learn.isLearning)
        XCTAssertEqual(h.announced.last, OSCLearnCoordinator.timedOutText)
        XCTAssertFalse(h.osc.dispatcher.isLearnArmed, "the capture is disarmed")
        send(h, "/late")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(h.defaults.stringArray(forKey: OSCRoutesCoordinator.aliasesKey), "nothing bound after the timeout")

        h.learn.startLearning(Self.intensity)
        h.learn.cancelLearning()
        XCTAssertEqual(h.announced.last, OSCLearnCoordinator.cancelledText)
        XCTAssertFalse(h.osc.dispatcher.isLearnArmed)

        XCTAssertTrue(h.routes.addAlias(address: "/x", parameter: Self.radius))
        h.learn.startLearning(Self.intensity)
        send(h, "/x")
        try await settle { !h.learn.isLearning }
        XCTAssertEqual(h.learn.statusText, "Glow intensity now listens to /x (it controlled Glow radius).")
        XCTAssertEqual(h.routes.userAliases, [OSCRouteAlias(address: "/x", parameter: Self.intensity)])

        h.learn.startLearning(Self.radius)
        h.osc.setEnabled(false)
        try await settle { !h.learn.isLearning }
        XCTAssertEqual(h.learn.statusText, OSCLearnCoordinator.stoppedText)
        XCTAssertFalse(h.osc.dispatcher.isLearnArmed)
    }
}
