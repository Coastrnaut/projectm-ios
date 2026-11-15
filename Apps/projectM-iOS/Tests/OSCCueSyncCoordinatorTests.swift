// OSC-012-T12, T16, T19: Cue Sync in the app (specs/291-osc-012-peer-cue-sync, contract C6). Two app coordinators in
// one process: the leader's `OSCSendCoordinator` sends through a transport that hands every datagram straight to the
// follower's receiver (a fake datagram transport from an approved local peer), so the follower's allow list, rate
// limits, decoder, message tap, inbox and show step are the app's real code. Timers are off; the tests call `tick()`
// and `drainInbox()` themselves, and the clock is injected.
import PerformanceControl
import ShowControl
import Synchronization
import XCTest
@testable import projectM_iOS

@MainActor
final class OSCCueSyncCoordinatorTests: XCTestCase {
    nonisolated static let leaderHost = OSCPeerAddress.ipv4(192, 168, 1, 20)
    static let followerHost = OSCPeerAddress.ipv4(192, 168, 1, 40)

    /// A receiver transport the test feeds by hand.
    private final class DatagramPipe: OSCDatagramTransport, Sendable {
        private let events = Mutex<(@Sendable (OSCTransportEvent) -> Void)?>(nil)
        func start(port: UInt16, events: @escaping @Sendable (OSCTransportEvent) -> Void) {
            self.events.withLock { $0 = events }
            events(.ready(port: port))
        }
        func stop() {
            let handler = events.withLock { (value: inout (@Sendable (OSCTransportEvent) -> Void)?) -> (@Sendable (OSCTransportEvent) -> Void)? in
                let current = value
                value = nil
                return current
            }
            handler?(.cancelled)
        }
        func deliver(_ bytes: [UInt8], from peer: OSCPeerAddress) {
            events.withLock { $0 }?(.datagram(bytes, source: OSCSourceID(rawValue: 1), peer: peer))
        }
    }

    /// The leader's send transport: records each datagram and forwards it to the follower's pipe.
    private final class Link: OSCSendTransport, Sendable {
        let sent = Mutex<[[UInt8]]>([])
        let pipe = Mutex<DatagramPipe?>(nil)
        let dropAll = Mutex(false)
        func open(host: OSCPeerAddress, port: UInt16, events: @escaping @Sendable (OSCSendTransportEvent) -> Void) { events(.ready) }
        func send(_ bytes: [UInt8]) {
            sent.withLock { $0.append(bytes) }
            guard !dropAll.withLock({ $0 }) else { return }
            pipe.withLock { $0 }?.deliver(bytes, from: OSCCueSyncCoordinatorTests.leaderHost)
        }
        func close() {}
    }

    private final class Clock: Sendable {
        let value = Mutex<UInt64>(1_000_000_000)
        var now: @Sendable () -> UInt64 { { [self] () -> UInt64 in value.withLock { $0 } } }
        func advance(ms: UInt64) { value.withLock { $0 += ms * 1_000_000 } }
    }

    /// One device: settings, OSC, Send OSC, the allow list, a show and Cue Sync.
    private struct Device {
        let defaults: UserDefaults
        let osc: OSCReceiverCoordinator
        let send: OSCSendCoordinator
        let show: ShowCoordinator
        let cueSync: OSCCueSyncCoordinator
        let pipe: DatagramPipe
    }

    private let clock = Clock()

    private func makeShow(_ cueIDs: [UUID]) throws -> ShowCoordinator {
        let show = ShowCoordinator(store: nil, registry: nil)
        show.announce = { (_: String) in }
        var list = ShowCueList()
        for (i, id) in cueIDs.enumerated() { _ = try list.append(sceneID: UUID().uuidString, label: "Cue \(i + 1)", cueID: id) }
        show.replaceForUITests(list)
        return show
    }

    private func makeDevice(cues: [UUID], link: Link, role: OSCCueSyncRole?) throws -> Device {
        let suite = "OSCCueSyncCoordinatorTests-\(UUID().uuidString)"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        if let role { defaults.set(role.rawValue, forKey: OSCCueSyncCoordinator.roleKey) }
        let settings = AppSettings(defaults: defaults, systemReduceMotion: false)
        let pipe = DatagramPipe()
        let receiver = OSCReceiver(makeTransport: { () -> (any OSCDatagramTransport)? in pipe })
        let osc = OSCReceiverCoordinator(settings: settings, receiver: receiver)
        let send = OSCSendCoordinator(osc: osc, defaults: defaults, transport: link,
                                      beatGrid: { () -> (anchor: UInt64, period: UInt64)? in nil }, clock: clock.now, pollsBeats: false)
        osc.sender = send
        let show = try makeShow(cues)
        let cueSync = OSCCueSyncCoordinator(osc: osc, show: show, defaults: defaults, clock: clock.now, session: 11, runsTimers: false)
        osc.cueSync = cueSync
        return Device(defaults: defaults, osc: osc, send: send, show: show, cueSync: cueSync, pipe: pipe)
    }

    /// OSC on, allow list on with the other device approved; the leader also sends to the follower.
    private func connect(leader: Device, follower: Device, link: Link) {
        link.pipe.withLock { $0 = follower.pipe }
        for (device, other) in [(leader, Self.followerHost), (follower, Self.leaderHost)] {
            device.osc.setEnabled(true)
            device.osc.peerAllowlist.setEnabled(true)
            device.osc.peerAllowlist.setApproved([other])
        }
        leader.send.setEnabled(true)
        XCTAssertTrue(leader.send.submitDestination(host: "192.168.1.40", port: "9000"))
    }

    private func cueSends(_ link: Link) -> Int {
        link.sent.withLock { $0 }.filter { (bytes: [UInt8]) -> Bool in bytes.starts(with: Array(OSCCueSyncMessage.address.utf8)) }.count
    }

    // MARK: T12

    func testFollowerShowStepsToTheLeadersCue() throws {
        let cues = [UUID(), UUID(), UUID()]
        let link = Link()
        let leader = try makeDevice(cues: cues, link: link, role: .lead)
        let follower = try makeDevice(cues: cues, link: link, role: .follow)
        connect(leader: leader, follower: follower, link: link)
        XCTAssertEqual(leader.cueSync.statusText, "Waiting for a cue.", "Standby sends nothing")
        XCTAssertEqual(cueSends(link), 0)

        leader.show.go(to: cues[1])
        XCTAssertTrue(leader.cueSync.isLeading)
        XCTAssertEqual(cueSends(link), 1, "the burst's first send at once")
        XCTAssertTrue(follower.cueSync.inbox.isHopPending)
        follower.cueSync.drainInbox()
        XCTAssertEqual(follower.show.list.activeCue?.id, cues[1], "the follower's show stepped to the cue")
        XCTAssertEqual(follower.cueSync.statusText(now: clock.now()), "Following cue 2 · started 0 s ago")
        XCTAssertTrue(follower.cueSync.holdsTimedAdvance, "R10: the follower's timed advance waits")
        XCTAssertEqual(leader.cueSync.statusText, "Sending cue 2")

        // The rest of the burst and a heartbeat: duplicates, never re-applied.
        let applied = follower.cueSync.followerCounters.applied
        for _ in 0..<4 {
            clock.advance(ms: 1_000)
            leader.cueSync.tick()
        }
        follower.cueSync.drainInbox()
        XCTAssertEqual(follower.cueSync.followerCounters.applied, applied)
        XCTAssertGreaterThan(follower.cueSync.followerCounters.duplicates, 0)
        XCTAssertEqual(follower.cueSync.statusText(now: clock.now()), "Following cue 2 · started 4 s ago", "the leader's offset")
        XCTAssertLessThanOrEqual(cueSends(link), 1 + 2 + 2, "burst plus at most one heartbeat per 2 s")

        // R11: the scene lock does not block following, and following changes no setting.
        let lock = SceneLock(defaults: follower.defaults)
        lock.lock()
        follower.show.sceneLock = lock
        let keysBefore = Set(follower.defaults.dictionaryRepresentation().keys)
        leader.show.go(to: cues[2])
        follower.cueSync.drainInbox()
        XCTAssertEqual(follower.show.list.activeCue?.id, cues[2])
        XCTAssertEqual(Set(follower.defaults.dictionaryRepresentation().keys), keysBefore, "no setting written")
    }

    func testLateJoinerRecoversFromTheNextRepeat() throws {
        let cues = [UUID(), UUID()]
        let link = Link()
        let leader = try makeDevice(cues: cues, link: link, role: .lead)
        let follower = try makeDevice(cues: cues, link: link, role: .off)
        connect(leader: leader, follower: follower, link: link)
        leader.show.go(to: cues[0])
        XCTAssertEqual(follower.show.list.activeCue, nil, "Off: nothing applied")
        XCTAssertEqual(follower.osc.dispatcher.messageTapAddress, nil, "Off: no tap")

        follower.cueSync.setRole(.follow)
        for _ in 0..<3 {
            clock.advance(ms: 1_000)
            leader.cueSync.tick()
        }
        follower.cueSync.drainInbox()
        XCTAssertEqual(follower.show.list.activeCue?.id, cues[0])
    }

    // MARK: T16

    func testUnknownCueIsReportedAndAllowListOffAppliesNothing() throws {
        let link = Link()
        let leader = try makeDevice(cues: [UUID()], link: link, role: .lead)
        let followerCues = [UUID()]
        let follower = try makeDevice(cues: followerCues, link: link, role: .follow)
        connect(leader: leader, follower: follower, link: link)
        leader.show.next()
        follower.cueSync.drainInbox()
        XCTAssertNil(follower.show.list.activeCue, "an unknown cue is not applied")
        XCTAssertEqual(follower.cueSync.statusText, "The leader's cue isn't in this show.")
        XCTAssertEqual(follower.cueSync.followerCounters.unknown, 1)
        XCTAssertEqual(follower.cueSync.countsText, "0 applied, 1 not in this show, 0 ignored")

        // Allow list off on the follower: nothing is acted on; on the leader: nothing is sent.
        follower.osc.peerAllowlist.setEnabled(false)
        XCTAssertEqual(follower.cueSync.statusText, "Turn on Only approved devices to sync cues.")
        XCTAssertFalse(follower.cueSync.holdsTimedAdvance)
        let before = cueSends(link)
        leader.osc.peerAllowlist.setEnabled(false)
        leader.cueSync.tick()
        XCTAssertFalse(leader.cueSync.isLeading)
        clock.advance(ms: 5_000)
        leader.cueSync.tick()
        XCTAssertEqual(cueSends(link), before, "no sends without the allow list")
        XCTAssertEqual(leader.cueSync.statusText, "Turn on Only approved devices to sync cues.")
    }

    // MARK: T19

    func testOffByDefaultSendsAndAppliesNothing() throws {
        let cues = [UUID(), UUID()]
        let link = Link()
        let leader = try makeDevice(cues: cues, link: link, role: nil)
        let follower = try makeDevice(cues: cues, link: link, role: nil)
        connect(leader: leader, follower: follower, link: link)
        XCTAssertEqual(leader.cueSync.role, .off)
        XCTAssertNil(leader.defaults.object(forKey: OSCCueSyncCoordinator.roleKey))
        XCTAssertEqual(leader.cueSync.summaryText, "Off")
        leader.show.go(to: cues[1])
        clock.advance(ms: 5_000)
        leader.cueSync.tick()
        XCTAssertEqual(cueSends(link), 0)
        XCTAssertNil(follower.osc.dispatcher.messageTapAddress)
        XCTAssertNil(follower.show.list.activeCue)

        // The choice is stored under the one device-only key and survives a relaunch.
        follower.cueSync.setRole(.follow)
        XCTAssertEqual(follower.defaults.string(forKey: OSCCueSyncCoordinator.roleKey), "follow")
        let again = OSCCueSyncCoordinator(osc: follower.osc, show: follower.show, defaults: follower.defaults,
                                          clock: clock.now, runsTimers: false)
        XCTAssertEqual(again.role, .follow)
    }
}
