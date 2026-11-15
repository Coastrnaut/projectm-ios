// OSCSendCoordinator.swift — Send OSC in Settings › OSC (OSC-005-R1 to R12; specs/277-osc-005-osc-send,
// contracts/osc-send.md S3; ADR-0088).
//
// * Five keys, all this device's network setup (excluded from the FILE-005 backup, removed by the FILE-011 Settings
//   erase and by `-uitestResetNotice`): `settings.osc.send.enabled` (absent → off), `settings.osc.send.host` (storage
//   text of a validated local address), `settings.osc.send.port` (absent → 9000), `settings.osc.send.kinds`
//   ([String], absent → scene + status), `settings.osc.send.sceneNames` (absent → off).
// * Active (R4) only while Send OSC is on, the OSC receiver switch (OSC-007) is on, the app is in the foreground, a
//   destination is set and, with OSC-008's "Only approved devices" on, the destination is approved. Otherwise the
//   sender is configured with nil, which cancels the flow at once (R5). `OSCReceiverCoordinator.apply()` calls
//   `conditionsChanged()` for the switch and the foreground; every event re-checks too (the allow list can change).
// * Beats (R8): while active with Beats on, a main-actor task polls the tempo grid every 50 ms; `OSCBeatGate`
//   decides. Scene and status events come from AppCoordinator (show cues, source start and stop).
// * Counts are memory only; traffic is never announced. The flow itself is `NetworkOSCSender` in PerformanceControl's
//   `OSCTransport/`, the only folder where FR-068 (ADR-0008) allows the Network framework.
import AudioCore
import Foundation
import Observation
import PerformanceControl

@MainActor
@Observable
final class OSCSendCoordinator {
    static let enabledKey = "settings.osc.send.enabled"
    static let hostKey = "settings.osc.send.host"
    static let portKey = "settings.osc.send.port"
    static let kindsKey = "settings.osc.send.kinds"
    static let sceneNamesKey = "settings.osc.send.sceneNames"
    static let allKeys: [String] = [enabledKey, hostKey, portKey, kindsKey, sceneNamesKey]
    /// 20 Hz: a beat is late by at most 50 ms.
    static let beatPollNanoseconds: UInt64 = 50_000_000

    private(set) var isEnabled: Bool
    private(set) var destination: OSCSendDestination?
    private(set) var kinds: Set<OSCSendKind>
    private(set) var includeSceneNames: Bool
    /// Shown under the address field after a refused entry; cleared by the next valid one.
    private(set) var destinationError: String?
    private(set) var senderState: OSCSenderState = .off
    private(set) var sentCount = 0
    private(set) var droppedCount = 0
    /// The port shown when no destination is stored yet.
    private(set) var storedPort: UInt16

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sender: OSCSender
    @ObservationIgnored private weak var osc: OSCReceiverCoordinator?
    /// The tempo grid (anchor, period) in the clock's nanoseconds, nil without phase.
    @ObservationIgnored private let beatGrid: @MainActor () -> (anchor: UInt64, period: UInt64)?
    @ObservationIgnored private let clock: @Sendable () -> UInt64
    @ObservationIgnored private var beatGate = OSCBeatGate()
    @ObservationIgnored private var beatTask: Task<Void, Never>?
    /// Tests drive `tick(now:)` themselves.
    @ObservationIgnored private let pollsBeats: Bool

    init(osc: OSCReceiverCoordinator, defaults: UserDefaults, transport: any OSCSendTransport = NetworkOSCSender(),
         beatGrid: @escaping @MainActor () -> (anchor: UInt64, period: UInt64)?,
         clock: @escaping @Sendable () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() }, pollsBeats: Bool = true) {
        self.osc = osc
        self.defaults = defaults
        self.beatGrid = beatGrid
        self.clock = clock
        self.pollsBeats = pollsBeats
        sender = OSCSender(transport: transport, clock: OSCMonotonicClock(now: clock))
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let storedKinds: [String]? = defaults.stringArray(forKey: Self.kindsKey)
        kinds = storedKinds.map { (raw: [String]) -> Set<OSCSendKind> in Set(raw.compactMap(OSCSendKind.init(rawValue:))) } ?? OSCSendKind.defaults
        includeSceneNames = defaults.bool(forKey: Self.sceneNamesKey)
        let port: Int = defaults.object(forKey: Self.portKey) as? Int ?? Int(OSCPort.defaultPort)
        storedPort = OSCPort.isValid(port) ? UInt16(port) : OSCPort.defaultPort
        if let text = defaults.string(forKey: Self.hostKey), let host = OSCPeerAddress(text: text) {
            destination = OSCSendDestination(host: host, port: storedPort)   // nil when no longer sendable
        }
        sender.setOptions(kinds: kinds, includeSceneNames: includeSceneNames)
        sender.onStateChange { [weak self] (_: OSCSenderState) -> Void in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        conditionsChanged()
    }

    // MARK: Settings

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        conditionsChanged()
    }

    /// Applies a typed address and port; returns false (and sets `destinationError`) when refused (R3).
    @discardableResult
    func submitDestination(host: String, port: String) -> Bool {
        switch OSCSendDestination.parse(host: host, port: port) {
        case .failure(let error):
            destinationError = error.message
            return false
        case .success(let parsed):
            destinationError = nil
            destination = parsed
            storedPort = parsed.port
            defaults.set(parsed.host.storageText, forKey: Self.hostKey)
            defaults.set(Int(parsed.port), forKey: Self.portKey)
            conditionsChanged()
            return true
        }
    }

    func setKind(_ kind: OSCSendKind, on: Bool) {
        if on { kinds.insert(kind) } else { kinds.remove(kind) }
        let ordered: [String] = OSCSendKind.allCases.filter { (k: OSCSendKind) -> Bool in kinds.contains(k) }.map(\.rawValue)
        defaults.set(ordered, forKey: Self.kindsKey)
        sender.setOptions(kinds: kinds, includeSceneNames: includeSceneNames)
        conditionsChanged()
    }

    func setIncludeSceneNames(_ on: Bool) {
        includeSceneNames = on
        defaults.set(on, forKey: Self.sceneNamesKey)
        sender.setOptions(kinds: kinds, includeSceneNames: on)
    }

    // MARK: Conditions (R4, R5)

    private enum Block: Equatable {
        case off, receiverOff, noDestination, background, notApproved
    }

    private var block: Block? {
        guard isEnabled else { return .off }
        guard let osc, osc.isEnabled else { return .receiverOff }
        guard let destination else { return .noDestination }
        guard osc.appIsActive else { return .background }
        let allowlist: OSCPeerAllowlist = osc.peerAllowlist
        if allowlist.isEnabled && !allowlist.approved.contains(destination.host.normalized) { return .notApproved }
        return nil
    }

    /// The destination to send to now, or nil.
    var activeDestination: OSCSendDestination? { block == nil ? destination : nil }

    /// Re-evaluates R4: configures or stops the sender and the beat poll.
    func conditionsChanged() {
        let target: OSCSendDestination? = activeDestination
        if target == nil || sender.destination != target { beatGate.reset() }
        sender.configure(destination: target)
        updateBeatPoll(active: target != nil && kinds.contains(.beat))
        refresh()
    }

    private func updateBeatPoll(active: Bool) {
        guard pollsBeats else { return }
        if !active {
            beatTask?.cancel()
            beatTask = nil
            return
        }
        guard beatTask == nil else { return }
        beatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.beatPollNanoseconds)
                guard let self, !Task.isCancelled else { return }
                self.tick(now: self.clock())
            }
        }
    }

    // MARK: Events

    /// A scene, beat or status event (AppCoordinator, the beat poll).
    func post(_ event: OSCSendEvent) {
        if sender.destination != activeDestination { conditionsChanged() }   // the allow list may have changed
        guard sender.destination != nil else { return }
        sender.post(event)
        refresh()
    }

    /// One beat poll (R8).
    func tick(now: UInt64) {
        guard sender.destination != nil, kinds.contains(.beat) else { return }
        let grid: (anchor: UInt64, period: UInt64)? = beatGrid()
        guard let n = beatGate.beat(anchor: grid?.anchor, period: grid?.period, now: now) else { return }
        post(.beat(n))
    }

    private func refresh() {
        senderState = sender.state
        let counters: OSCSenderCounters = sender.counters
        sentCount = counters.sent
        droppedCount = counters.dropped
    }

    // MARK: Texts (R10)

    var summaryText: String { isEnabled ? "On" : "Off" }

    var statusText: String {
        switch block {
        case .off: return "Off"
        case .receiverOff: return "Turn on the OSC receiver to send."
        case .noDestination: return "Enter a destination address."
        case .background: return "Paused while projectM is in the background."
        case .notApproved: return "The destination is not an approved device."
        case nil: break
        }
        switch senderState {
        case .failed(_, .localNetworkDenied): return "Local Network access is off for projectM."
        case .failed(let target, _): return "Couldn't send to \(target.text). Turn Send OSC off and on to try again."
        case .ready(let target), .connecting(let target): return "Sending to \(target.text)"
        case .off: return "Off"
        }
    }

    var countsText: String { "\(sentCount) sent, \(droppedCount) dropped" }

    var hostText: String { destination?.host.text ?? "" }
}
