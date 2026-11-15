// OSC-011-T07, T08, T12, T17: Nearby Devices in the app (specs/289-osc-011-local-peer-discovery, contract D3).
// The receiver runs over a spy transport that records what it is asked to announce; browsers come from a spy
// factory, and found devices are fake browser results. No network is used.
import PerformanceControl
import Synchronization
import XCTest
@testable import projectM_iOS

@MainActor
final class OSCDiscoveryCoordinatorTests: XCTestCase {
    /// Reports ready on start and cancelled on stop; records every `advertise` call.
    private final class SpyTransport: OSCDatagramTransport, Sendable {
        let advertised = Mutex<[String?]>([])
        private let handler = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)
        func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
            handler.withLock { $0 = events }
            events(.ready(port: port))
        }
        func stop() {
            let events = handler.withLock { (h: inout (@Sendable (OSCTransportEvent) -> Void)?) -> (@Sendable (OSCTransportEvent) -> Void)? in
                defer { h = nil }
                return h
            }
            events?(.cancelled)
        }
        func advertise(_ name: String?) { advertised.withLock { $0.append(name) } }
    }

    /// Records start and cancel; the test delivers results by hand.
    private final class SpyBrowser: OSCPeerBrowsing, Sendable {
        let started = Mutex(false)
        let cancelled = Mutex(false)
        private let events = Mutex<(@Sendable (OSCBrowserEvent) -> Void)?>(nil)
        func start(events: @escaping @Sendable (OSCBrowserEvent) -> Void) {
            started.withLock { $0 = true }
            self.events.withLock { $0 = events }
        }
        func cancel() { cancelled.withLock { $0 = true } }
        func deliver(_ event: OSCBrowserEvent) { events.withLock { $0 }?(event) }
    }

    private final class TransportLog: Sendable {
        let list = Mutex<[SpyTransport]>([])
    }

    private final class Harness {
        let defaults: UserDefaults
        let settings: AppSettings
        let osc: OSCReceiverCoordinator
        let discovery: OSCDiscoveryCoordinator
        let transports = TransportLog()
        var browsers: [SpyBrowser] = []

        @MainActor init(defaults: UserDefaults) {
            self.defaults = defaults
            settings = AppSettings(defaults: defaults, systemReduceMotion: false)
            let made: TransportLog = transports
            let receiver = OSCReceiver(makeTransport: { () -> (any OSCDatagramTransport)? in
                let t = SpyTransport()
                made.list.withLock { $0.append(t) }
                return t
            })
            osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
            osc.peers = OSCPeersCoordinator(allowlist: osc.peerAllowlist, defaults: defaults)
            osc.sender = OSCSendCoordinator(osc: osc, defaults: defaults, transport: NoTransport(),
                                            beatGrid: { () -> (anchor: UInt64, period: UInt64)? in nil }, pollsBeats: false)
            var box: [SpyBrowser] = []
            discovery = OSCDiscoveryCoordinator(osc: osc, defaults: defaults, advertisedName: "projectM 0A1F") { () -> any OSCPeerBrowsing in
                let b = SpyBrowser()
                box.append(b)
                return b
            }
            browsersBox = { box }
            osc.discovery = discovery
        }

        var browsersBox: () -> [SpyBrowser] = { [] }
        var advertised: [String?] { transports.list.withLock { $0.flatMap { $0.advertised.withLock { $0 } } } }
        var lastAdvertised: String?? { advertised.last }
    }

    private final class NoTransport: OSCSendTransport, Sendable {
        func open(host: OSCPeerAddress, port: UInt16, events: @escaping @Sendable (OSCSendTransportEvent) -> Void) {}
        func send(_ bytes: [UInt8]) {}
        func close() {}
    }

    private static let desk = OSCDiscoveredPeer(name: "Lighting Desk", address: .ipv4(192, 168, 1, 40), port: 9001)

    private func makeHarness() throws -> Harness {
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: "OSCDiscoveryCoordinatorTests-\(UUID().uuidString)"))
        return Harness(defaults: defaults)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: T07 default off (OSC-011-R4, S1)

    func testDiscoveryIsOffByDefaultAcrossOSCAndForegroundChanges() throws {
        let h = try makeHarness()
        XCTAssertFalse(h.discovery.browseEnabled)
        XCTAssertFalse(h.discovery.advertiseEnabled)
        XCTAssertNil(h.defaults.object(forKey: OSCDiscoveryCoordinator.browseKey), "a fresh install stores nothing")
        h.osc.setEnabled(true)
        h.osc.sceneBecame(active: false)
        h.osc.sceneBecame(active: true)
        h.osc.setEnabled(false)
        h.osc.setEnabled(true)
        XCTAssertEqual(h.discovery.browsersCreated, 0, "no browser ever exists while off")
        XCTAssertNil(h.osc.advertisement, "no service is announced")
        XCTAssertTrue(h.advertised.allSatisfy { $0 == nil }, "no transport was asked to announce")
        XCTAssertEqual(h.discovery.statusText, "Off")
        XCTAssertNil(h.discovery.advertiseStatusText)
        XCTAssertTrue(h.discovery.peers.isEmpty)
    }

    // MARK: T08 lifecycle (OSC-011-R5, R6, S2)

    func testBrowserStartsOnlyWithOSCAndStopsOnEveryCondition() async throws {
        let h = try makeHarness()
        h.discovery.setBrowse(true)
        XCTAssertEqual(h.discovery.browsersCreated, 0, "OSC off: nothing runs")
        XCTAssertEqual(h.discovery.statusText, "Turn on the OSC receiver to find nearby devices.")
        h.osc.setEnabled(true)
        XCTAssertEqual(h.discovery.browsersCreated, 1)
        let first = try XCTUnwrap(h.browsersBox().last)
        XCTAssertTrue(first.started.withLock { $0 })
        first.deliver(.peers([Self.desk]))
        await settle()
        XCTAssertEqual(h.discovery.peers, [Self.desk])

        h.discovery.setBrowse(false)   // the switch
        XCTAssertTrue(first.cancelled.withLock { $0 })
        XCTAssertTrue(h.discovery.peers.isEmpty)
        first.deliver(.peers([Self.desk]))   // late event of a cancelled browser
        await settle()
        XCTAssertTrue(h.discovery.peers.isEmpty, "a cancelled browser's results are ignored")

        h.discovery.setBrowse(true)
        let second = try XCTUnwrap(h.browsersBox().last)
        h.osc.setEnabled(false)   // the OSC receiver switch (OSC-007)
        XCTAssertTrue(second.cancelled.withLock { $0 })

        h.osc.setEnabled(true)
        let third = try XCTUnwrap(h.browsersBox().last)
        h.osc.sceneBecame(active: false)   // background
        XCTAssertTrue(third.cancelled.withLock { $0 })
        XCTAssertEqual(h.discovery.statusText, "Paused while projectM is in the background.")
        XCTAssertEqual(h.discovery.browsersCreated, 3)
    }

    func testAnnouncingFollowsItsSwitchOSCAndForeground() throws {
        let h = try makeHarness()
        h.discovery.setAdvertise(true)
        XCTAssertNil(h.osc.advertisement, "OSC off: nothing is announced")
        h.osc.setEnabled(true)
        XCTAssertEqual(h.osc.advertisement, "projectM 0A1F")
        XCTAssertEqual(h.lastAdvertised, "projectM 0A1F", "the listener announces the generic name")
        h.osc.sceneBecame(active: false)
        XCTAssertNil(h.osc.advertisement, "background withdraws it")
        h.osc.sceneBecame(active: true)
        XCTAssertEqual(h.osc.advertisement, "projectM 0A1F")
        h.discovery.setAdvertise(false)
        XCTAssertNil(h.osc.advertisement)
        XCTAssertEqual(h.lastAdvertised, .some(nil), "turning it off withdraws the announcement")
        XCTAssertEqual(h.discovery.browsersCreated, 0, "announcing never browses")
    }

    func testFailureIsShownAndNotRetried() async throws {
        let h = try makeHarness()
        h.osc.setEnabled(true)
        h.discovery.setBrowse(true)
        try XCTUnwrap(h.browsersBox().last).deliver(.failed(.localNetworkDenied))
        await settle()
        XCTAssertEqual(h.discovery.statusText, PermissionCatalog.localNetworkDenied)
        h.osc.sceneBecame(active: true)   // a condition re-check alone does not retry
        XCTAssertEqual(h.discovery.browsersCreated, 1)
    }

    // MARK: T12 no auto-approval (OSC-011-R9, S3)

    func testFoundDevicesAreNeverTrustedWithoutATap() async throws {
        let h = try makeHarness()
        h.osc.setEnabled(true)
        h.discovery.setBrowse(true)
        let browser = try XCTUnwrap(h.browsersBox().last)
        let public8 = OSCDiscoveredPeer(name: "Elsewhere", address: .ipv4(8, 8, 8, 8), port: 9000)
        let own = OSCDiscoveredPeer(name: "projectM 0A1F", address: .ipv4(192, 168, 1, 2), port: 9000)
        browser.deliver(.peers([Self.desk, public8, own]))
        await settle()
        XCTAssertEqual(h.discovery.peers, [Self.desk], "non-local and own announcement left out")
        XCTAssertTrue(h.osc.peers?.approved.isEmpty ?? false, "nothing approved by itself")
        XCTAssertNil(h.osc.sender?.destination, "no destination by itself")

        h.discovery.allow(Self.desk)
        XCTAssertEqual(h.osc.peers?.approved, [.ipv4(192, 168, 1, 40)])
        XCTAssertFalse(h.osc.peers?.isEnabled ?? true, "Allow never turns the allow list on")
        XCTAssertTrue(h.discovery.isApproved(Self.desk))

        h.discovery.useAsSendDestination(Self.desk)
        XCTAssertEqual(h.osc.sender?.destination, OSCSendDestination(host: .ipv4(192, 168, 1, 40), port: 9001))
        XCTAssertFalse(h.osc.sender?.isEnabled ?? true, "Send OSC stays off")
        XCTAssertEqual(h.discovery.actionNote, "Send OSC will send to 192.168.1.40:9001.")
    }

    func testIPv6LinkLocalPeerOffersNoDestination() throws {
        let h = try makeHarness()
        var bytes: [UInt8] = Array(repeating: 0, count: 16)
        bytes[0] = 0xFE; bytes[1] = 0x80; bytes[15] = 7
        let peer = OSCDiscoveredPeer(name: "v6", address: .ipv6(bytes), port: 9000)
        h.discovery.useAsSendDestination(peer)
        XCTAssertNil(h.osc.sender?.destination)
    }

    // MARK: T17 Info.plist (OSC-011-R11, S4)

    func testInfoPlistDeclaresOnlyTheAppsBonjourType() {
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]
        XCTAssertEqual(services, [OSCDiscovery.serviceType])
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String
        XCTAssertTrue(usage?.contains("Nearby Devices") ?? false)
    }
}
