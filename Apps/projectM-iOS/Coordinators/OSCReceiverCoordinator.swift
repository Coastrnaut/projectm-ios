// OSCReceiverCoordinator.swift — the OSC receiver in the app (OSC-001; specs/032-osc-001-osc-receiver,
// contracts/osc-receiver.md C6).
//
// * Listens only while the user has turned OSC on AND the app is active in the foreground
//   (OSC-001-R1 to R3): leaving the foreground closes the listener, returning reopens it.
// * The port is applied on submit (or when the field loses focus), never per keystroke; an entry
//   outside 1024-65535 is refused and the stored port stays (OSC-001-R2).
// * Status and test value come from the receiver's queue and are copied onto the main actor.
// * OSC-009-R11 (specs/041-osc-009-osc-rate-limiter, research OSC-009-D7): traffic never schedules
//   main-thread work per message. Every datagram, drop or flush asks an `OSCRefreshGate`; only when
//   no refresh is pending does one main-actor task start, no sooner than 1/30 s after the previous
//   refresh, and it reads the latest state. A flood therefore costs the main thread (and the
//   render loop it drives) at most about 30 short refreshes a second.
// * A failure is shown and never retried by itself (OSC-001-R3).
// The test value feeds nothing that renders (OSC-001-R7). The networking itself lives in
// PerformanceControl's OSCTransport/ folder (FR-068 amendment, ADR-0008).
import Foundation
import Observation
import ParameterGraph
import PerformanceControl

@MainActor
@Observable
final class OSCReceiverCoordinator {
    static let portRangeMessage = "Use a port from 1024 to 65535."

    private(set) var state: OSCReceiverState = .off
    private(set) var testValue: Double = 0
    /// OSC-009-R12: datagrams dropped plus updates held by the rate limiter since launch.
    private(set) var rateLimitedCount = 0
    /// Shown under the port field after a refused entry; cleared by the next valid one.
    private(set) var portError: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let receiver: OSCReceiver
    @ObservationIgnored private(set) var appIsActive: Bool
    @ObservationIgnored private let refreshGate = OSCRefreshGate()
    @ObservationIgnored private let refreshClock = OSCMonotonicClock.continuous()
    /// Main-actor refreshes so far (tests: a flood must not add one per message).
    @ObservationIgnored private(set) var refreshCount = 0

    init(settings: AppSettings, receiver: OSCReceiver = .system(), appIsActive: Bool = true) {
        self.settings = settings
        self.receiver = receiver
        self.appIsActive = appIsActive
        testValue = receiver.testValue
        receiver.onStateChange { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let gate = refreshGate, clock = refreshClock
        receiver.onActivity { [weak self] in
            guard let delay = gate.request(now: clock.now()) else { return }   // one refresh pending at most
            Task { @MainActor [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                gate.begin(now: clock.now())
                self?.refresh()
            }
        }
        apply()
    }

    var isEnabled: Bool { settings.oscEnabled }
    var port: Int { settings.oscPort }

    func setEnabled(_ enabled: Bool) {
        settings.oscEnabled = enabled
        apply()
    }

    /// Applies a typed port; returns false (and sets `portError`) when it is refused.
    @discardableResult
    func submitPort(_ text: String) -> Bool {
        guard let port = OSCPort.parse(text) else {
            portError = Self.portRangeMessage
            return false
        }
        portError = nil
        if Int(port) != settings.oscPort {
            settings.oscPort = Int(port)
            apply()
        }
        return true
    }

    func sceneBecame(active: Bool) {
        appIsActive = active
        apply()
    }

    /// Listening iff enabled and active (C6).
    private func apply() {
        if settings.oscEnabled && appIsActive {
            receiver.start(port: UInt16(settings.oscPort))
        } else {
            receiver.stop()
        }
        refresh()
    }

    private func refresh() {
        refreshCount += 1
        state = receiver.state
        testValue = receiver.testValue
        let counters = receiver.counters
        rateLimitedCount = counters.rateLimited + counters.coalesced
    }

    // MARK: Listener badge (OSC-007; specs/038-osc-007-osc-network-access-switch, contract)

    /// The port the visualizer's badge names: only while the listener is actually ready
    /// (`listening`), never from the toggle alone (OSC-007-R2, R3; research OSC-007-D1).
    static func listenerBadgePort(for state: OSCReceiverState) -> UInt16? {
        if case .listening(let port) = state { port } else { nil }
    }

    var badgePort: UInt16? { Self.listenerBadgePort(for: state) }

    /// PERF-010-R12: the transport is listening or about to (the DEBUG recovery probe).
    var isListenerOpen: Bool {
        switch state {
        case .starting, .listening: true
        default: false
        }
    }

    static func badgeText(port: UInt16) -> String { "OSC listening on port \(port)" }

    /// VoiceOver value of the badge (OSC-007-R7), a plain String so the port is never grouped.
    static func badgeAccessibilityValue(port: UInt16) -> String { "Port \(port)" }

    /// The badge's Stop (OSC-007-R4, R5): the same path as the Settings toggle, so the stored
    /// setting turns off and the listener closes with OSC-001's confirmed cancel. Nothing else changes.
    func stopFromBadge() {
        guard settings.oscEnabled else { return }
        setEnabled(false)
    }

    // MARK: Texts (contract C6; unit-tested)

    var statusText: String { Self.statusText(for: state, enabled: isEnabled) }

    /// FILE-013-R3, R4: the Local Network notice (with Open Settings) while the listener is denied.
    var permissionNotice: PermissionNotice? {
        PermissionCatalog.state(localNetwork: state).flatMap { (s: PermissionState) -> PermissionNotice? in
            PermissionCatalog.notice(.localNetwork, s)
        }
    }

    static func statusText(for state: OSCReceiverState, enabled: Bool) -> String {
        switch state {
        case .off, .stopping:
            return enabled ? "Paused while projectM is in the background." : "Off"
        case .starting:
            return "Starting…"
        case .listening(let port):
            return "Listening on port \(port)"
        case let .failed(port, failure):
            switch failure {
            case .portInUse: return "Port \(port) is in use. Choose another port."
            case .localNetworkDenied:
                return PermissionCatalog.localNetworkDenied   // FILE-013-R3: the catalog's text
            case .unavailable: return "OSC isn't available on this device."
            case .other: return "OSC couldn't listen on port \(port). Turn it off and on to try again."
            }
        }
    }

    /// The Settings row's value (OSC-009-R12): a plain number, never grouped.
    static func rateLimitedText(_ count: Int) -> String { String(count) }

    static func testValueText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
