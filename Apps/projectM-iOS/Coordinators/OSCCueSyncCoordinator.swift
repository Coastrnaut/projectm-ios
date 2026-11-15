// OSCCueSyncCoordinator.swift — Cue Sync in Settings › OSC (OSC-012; specs/291-osc-012-peer-cue-sync, contract C6;
// ADR-0102).
//
// * One key, this device's network setup (excluded from the FILE-005 backup, removed by the FILE-011 Settings erase and
//   by `-uitestResetNotice`): `settings.osc.cueSync.role` (Off, Lead, Follow; absent → Off).
// * Lead (R3 to R5): active only while Lead is chosen, the OSC receiver switch is on, "Only approved devices" is on,
//   Send OSC is active (its switch, the foreground and an approved destination: `OSCSendCoordinator.activeDestination`)
//   and the show has an active cue. Becoming active counts as a cue change. `OSCCueSyncLeader` decides every send; a
//   main-actor task sleeps until the next one is due (at most 1 s, so a gate change such as the allow list is noticed).
//   Cue changes come from `ShowCoordinator.cueStarted`, chained after SHOW-002's and SHOW-013's handlers.
// * Follow (R6 to R10, R13): the receiver's dispatcher taps `/projectm/cue` into `OSCCueSyncInbox` on the receiving
//   side (receipt time from the monotonic clock there); one main-actor hop drains it into `OSCCueSyncFollower`, which
//   acts only while the allow list is on (so every message came from an approved host). An applied cue goes through
//   SHOW-001's step path at once (`stepNow(.go)`, never quantized), unless the show is already on it. While following is
//   active the timed advance is held (`holdsTimedAdvance`, read by `ShowAutoAdvanceCoordinator.isHeld`).
// * Safety (R11): only the show position moves; no setting, file, cue or switch changes. The scene lock does not block
//   following (a cue step, as SHOW-015 allows). Nothing is announced here (R14): a step announces like any other.
import AudioCore
import Foundation
import Observation
import PerformanceControl

@MainActor
@Observable
final class OSCCueSyncCoordinator {
    static let roleKey = "settings.osc.cueSync.role"
    static let allKeys: [String] = [roleKey]
    /// While Lead is chosen, the gates are re-checked at least this often.
    static let idleCheckNanoseconds: UInt64 = 1_000_000_000

    enum Block: Equatable {
        case off, receiverOff, allowlistOff, sendInactive, noCue
    }

    private(set) var role: OSCCueSyncRole
    private(set) var isLeading = false
    private(set) var followerState: OSCCueSyncFollowerState = .waiting
    private(set) var followerCounters = OSCCueSyncFollowerCounters()
    private(set) var sentCount = 0

    @ObservationIgnored private weak var osc: OSCReceiverCoordinator?
    @ObservationIgnored private let show: ShowCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: @Sendable () -> UInt64
    @ObservationIgnored private(set) var leader: OSCCueSyncLeader
    @ObservationIgnored private var follower = OSCCueSyncFollower()
    @ObservationIgnored let inbox = OSCCueSyncInbox()
    @ObservationIgnored private var lastCueID: UUID?
    @ObservationIgnored private var cueStartedAt: UInt64
    @ObservationIgnored private var leaderTask: Task<Void, Never>?
    @ObservationIgnored private var tapInstalled = false
    /// Tests drive `tick()` and `drainInbox()` themselves.
    @ObservationIgnored private let runsTimers: Bool

    init(osc: OSCReceiverCoordinator, show: ShowCoordinator, defaults: UserDefaults,
         clock: @escaping @Sendable () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() },
         session: Int32 = OSCCueSyncLeader.randomSession(), runsTimers: Bool = true) {
        self.osc = osc
        self.show = show
        self.defaults = defaults
        self.clock = clock
        self.runsTimers = runsTimers
        leader = OSCCueSyncLeader(session: session)
        role = defaults.string(forKey: Self.roleKey).flatMap(OSCCueSyncRole.init(rawValue:)) ?? .off
        lastCueID = show.list.activeCue?.id
        cueStartedAt = clock()
        let previous: (() -> Void)? = show.cueStarted
        show.cueStarted = { [weak self] () -> Void in
            previous?()
            self?.cueStarted()
        }
        conditionsChanged()
    }

    // MARK: Settings

    func setRole(_ newRole: OSCCueSyncRole) {
        guard newRole != role else { return }
        role = newRole
        defaults.set(newRole.rawValue, forKey: Self.roleKey)
        conditionsChanged()
    }

    // MARK: Conditions

    var leadBlock: Block? {
        guard role == .lead else { return .off }
        guard let osc, osc.isEnabled else { return .receiverOff }
        guard osc.peerAllowlist.isEnabled else { return .allowlistOff }
        guard let send = osc.sender, send.activeDestination != nil else { return .sendInactive }
        guard show.list.activeCue != nil else { return .noCue }
        return nil
    }

    var followBlock: Block? {
        guard role == .follow else { return .off }
        guard let osc, osc.isEnabled else { return .receiverOff }
        guard osc.peerAllowlist.isEnabled else { return .allowlistOff }
        return nil
    }

    /// R10: the timed advance waits while following is active (Follow, the receiver switch and the allow list on; the
    /// receiver itself only runs in the foreground, where the timed advance runs too).
    var holdsTimedAdvance: Bool { followBlock == nil }

    /// Re-evaluates both roles (switches, foreground, Send OSC, the allow list).
    func conditionsChanged() {
        let leadActive: Bool = leadBlock == nil
        if leadActive && !isLeading {
            isLeading = true
            leader.cueChanged(show.list.activeCue?.id.uuidString, startedAt: cueStartedAt, now: clock())   // R5: a fresh burst
        } else if !leadActive && isLeading {
            isLeading = false
            leader.stop()
        }
        if isLeading { sendDue() }
        updateLeaderTimer(restart: false)
        updateTap()
    }

    // MARK: Leader

    private func cueStarted() {
        let id: UUID? = show.list.activeCue?.id
        guard id != lastCueID else { return }   // a dwell edit on the same cue is not a change
        lastCueID = id
        cueStartedAt = clock()
        guard role == .lead else { return }
        if isLeading {
            leader.cueChanged(id?.uuidString, startedAt: cueStartedAt, now: cueStartedAt)
            sendDue()
            updateLeaderTimer(restart: true)
        } else {
            conditionsChanged()
        }
    }

    /// One timer wake: re-check the gates and send what is due (tests call it directly).
    func tick() {
        conditionsChanged()
    }

    private func sendDue() {
        guard let message = leader.due(now: clock()) else { return }
        if osc?.sender?.postCue(message) == true { sentCount += 1 }
    }

    private func updateLeaderTimer(restart: Bool) {
        guard runsTimers else { return }
        guard role == .lead else {
            leaderTask?.cancel()
            leaderTask = nil
            return
        }
        if restart {
            leaderTask?.cancel()
            leaderTask = nil
        }
        guard leaderTask == nil else { return }
        leaderTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.nextWakeDelay() else { return }
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func nextWakeDelay() -> UInt64 {
        let now: UInt64 = clock()
        guard let due = leader.nextDue else { return Self.idleCheckNanoseconds }
        return min(due > now ? due - now : 0, Self.idleCheckNanoseconds)
    }

    // MARK: Follower

    private func updateTap() {
        guard let osc else { return }
        let wanted: Bool = role == .follow
        guard wanted != tapInstalled else { return }
        tapInstalled = wanted
        guard wanted else {
            osc.dispatcher.setMessageTap(address: OSCCueSyncMessage.address, handler: nil)
            _ = inbox.take()
            follower.reset()
            followerState = follower.state
            return
        }
        let inbox: OSCCueSyncInbox = inbox
        let clock: @Sendable () -> UInt64 = clock
        let drains: Bool = runsTimers
        osc.dispatcher.setMessageTap(address: OSCCueSyncMessage.address) { [weak self] (message: OSCMessage) -> Void in
            guard inbox.offer(OSCCueSyncReceipt(message: message, receivedAt: clock())), drains else { return }
            Task { @MainActor [weak self] in self?.drainInbox() }   // R13: one hop while one is pending
        }
    }

    /// Applies what the inbox holds (the one main-actor hop; tests call it directly).
    func drainInbox() {
        let receipts: [OSCCueSyncReceipt] = inbox.take()
        guard role == .follow else { return }
        let approved: Bool = followBlock == nil
        for receipt in receipts {
            let decision: OSCCueSyncDecision = follower.receive(receipt.message, approved: approved, now: receipt.receivedAt,
                                                               hasCue: { [show] (id: String) -> Bool in Self.cue(id, in: show) != nil })
            guard case let .apply(cueID, _) = decision, let target = Self.cue(cueID, in: show) else { continue }
            if show.list.activeCue?.id != target { show.stepNow(.go(target)) }   // R8: at once, never re-applied
        }
        followerState = follower.state
        followerCounters = follower.counters
    }

    private static func cue(_ id: String, in show: ShowCoordinator) -> UUID? {
        guard let uuid = UUID(uuidString: id), show.list.cues.contains(where: { $0.id == uuid }) else { return nil }
        return uuid
    }

    // MARK: Texts (R14)

    static func title(_ role: OSCCueSyncRole) -> String {
        switch role {
        case .off: "Off"
        case .lead: "Lead"
        case .follow: "Follow"
        }
    }

    var summaryText: String { Self.title(role) }

    /// The 1-based number of a cue in this show, nil when it is not in it.
    private func number(of id: String) -> Int? {
        guard let uuid = UUID(uuidString: id), let index = show.list.cues.firstIndex(where: { $0.id == uuid }) else { return nil }
        return index + 1
    }

    func statusText(now: UInt64) -> String {
        if role == .off { return "Off" }
        let block: Block? = role == .lead ? leadBlock : followBlock
        switch block {
        case .off: return "Off"
        case .receiverOff: return "Turn on the OSC receiver to sync cues."
        case .allowlistOff: return "Turn on Only approved devices to sync cues."
        case .sendInactive: return "Turn on Send OSC with an approved destination."
        case .noCue: return "Waiting for a cue."
        case nil: break
        }
        if role == .lead {
            let n: Int = (show.list.activeIndex ?? 0) + 1
            return "Sending cue \(n)"
        }
        switch followerState {
        case .waiting: return "Waiting for the leader."
        case .unknownCue: return "The leader's cue isn't in this show."
        case let .following(cueID, alignedStart):
            let seconds: UInt64 = now > alignedStart ? (now - alignedStart) / 1_000_000_000 : 0
            guard let n = number(of: cueID) else { return "Waiting for the leader." }
            return "Following cue \(n) · started \(seconds) s ago"
        }
    }

    var statusText: String { statusText(now: clock()) }

    var countsText: String {
        switch role {
        case .off: return ""
        case .lead: return "\(sentCount) sent"
        case .follow:
            let c: OSCCueSyncFollowerCounters = followerCounters
            let ignored: Int = c.duplicates + c.unapproved + c.malformed
            return "\(c.applied) applied, \(c.unknown) not in this show, \(ignored) ignored"
        }
    }
}
