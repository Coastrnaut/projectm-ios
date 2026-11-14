// OSCPeersCoordinator.swift — Approved Devices in Settings › OSC (OSC-008-R1, R4, R5, R9-R11;
// specs/200-osc-008-peer-allowlist, contracts/osc-peer-allowlist.md A4; ADR-0058).
//
// * "Only approved devices" is stored under `settings.osc.peerAllowlist.enabled` (absent → off: OSC unchanged) and the
//   approved hosts under `settings.osc.approvedPeers` (storage text; unreadable or non-local entries dropped on load,
//   at most 16). Both stay on this device: excluded from the FILE-005 backup, removed by the FILE-011 Settings erase.
// * Every change is pushed to the receiver's `OSCPeerAllowlist` at once; the receiver checks it per datagram, so no
//   listener restart is needed (OSC-008-R8).
// * "Recently blocked" (at most 4 hosts) and the blocked count are memory only, read on OSC-009's gated refresh (never
//   per datagram), and cleared when OSC is turned off (OSC-008-R11).
import Foundation
import Observation
import PerformanceControl

@MainActor
@Observable
final class OSCPeersCoordinator {
    static let enabledKey = "settings.osc.peerAllowlist.enabled"
    static let approvedKey = "settings.osc.approvedPeers"
    static let allKeys: [String] = [enabledKey, approvedKey]

    private(set) var isEnabled: Bool
    private(set) var approved: [OSCPeerAddress] = []
    private(set) var recentlyBlocked: [OSCPeerAddress] = []
    /// Datagrams refused since OSC was last turned on.
    private(set) var blockedCount = 0

    @ObservationIgnored private let allowlist: OSCPeerAllowlist
    @ObservationIgnored private let defaults: UserDefaults
    /// The receiver's counter when OSC was last turned off (the shown count starts from there).
    @ObservationIgnored private var blockedBaseline = 0
    @ObservationIgnored private var lastCounter = 0

    init(allowlist: OSCPeerAllowlist, defaults: UserDefaults) {
        self.allowlist = allowlist
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let lines: [String] = defaults.stringArray(forKey: Self.approvedKey) ?? []
        allowlist.setApproved(lines.compactMap { (line: String) -> OSCPeerAddress? in OSCPeerAddress(text: line) })
        allowlist.setEnabled(isEnabled)
        approved = allowlist.approved
        if approved.count != lines.count { store() }   // drop what could not be read
    }

    var isFull: Bool { approved.count >= OSCPeerAllowlist.maximumApproved }

    /// The Settings row's value: "Off" or "N approved".
    var summaryText: String { isEnabled ? "\(approved.count) approved" : "Off" }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        allowlist.setEnabled(enabled)
        recentlyBlocked = allowlist.recentlyBlocked
    }

    @discardableResult
    func allow(_ peer: OSCPeerAddress) -> OSCPeerAllowlist.ApproveResult {
        let result: OSCPeerAllowlist.ApproveResult = allowlist.approve(peer)
        if result == .approved { store() }
        recentlyBlocked = allowlist.recentlyBlocked
        return result
    }

    func remove(_ peer: OSCPeerAddress) {
        allowlist.remove(peer)
        store()
    }

    /// Called on the OSC coordinator's gated refresh with the receiver's `droppedUnapproved`.
    func refresh(droppedUnapproved: Int) {
        lastCounter = droppedUnapproved
        let shown: Int = max(droppedUnapproved - blockedBaseline, 0)
        if shown != blockedCount { blockedCount = shown }
        let blocked: [OSCPeerAddress] = allowlist.recentlyBlocked
        if blocked != recentlyBlocked { recentlyBlocked = blocked }
    }

    /// OSC turned off by the user: forget blocked hosts and restart the count (OSC-008-R11).
    func oscTurnedOff() {
        allowlist.clearRecentlyBlocked()
        blockedBaseline = lastCounter
        blockedCount = 0
        recentlyBlocked = []
    }

    private func store() {
        approved = allowlist.approved
        defaults.set(approved.map { (peer: OSCPeerAddress) -> String in peer.storageText }, forKey: Self.approvedKey)
    }
}
