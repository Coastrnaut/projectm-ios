// OSCReceiverCoordinator.swift — the OSC receiver in the app (OSC-001; specs/032-osc-001-osc-receiver,
// contracts/osc-receiver.md C6).
//
// * Listens only while the user has turned OSC on AND the app is active in the foreground
//   (OSC-001-R1 to R3): leaving the foreground closes the listener, returning reopens it.
// * The port is applied on submit (or when the field loses focus), never per keystroke; an entry
//   outside 1024-65535 is refused and the stored port stays (OSC-001-R2).
// * Status and test value come from the receiver's queue and are copied onto the main actor.
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
    /// Shown under the port field after a refused entry; cleared by the next valid one.
    private(set) var portError: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let receiver: OSCReceiver
    @ObservationIgnored private var observation: ParameterObservation?
    @ObservationIgnored private(set) var appIsActive: Bool

    init(settings: AppSettings, receiver: OSCReceiver = .system(), appIsActive: Bool = true) {
        self.settings = settings
        self.receiver = receiver
        self.appIsActive = appIsActive
        testValue = receiver.testValue
        receiver.onStateChange { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observation = receiver.observeTestValue { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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
        state = receiver.state
        testValue = receiver.testValue
    }

    // MARK: Texts (contract C6; unit-tested)

    var statusText: String { Self.statusText(for: state, enabled: isEnabled) }

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
                return "Local network access is off for projectM in Settings › Privacy & Security › Local Network."
            case .unavailable: return "OSC isn't available on this device."
            case .other: return "OSC couldn't listen on port \(port). Turn it off and on to try again."
            }
        }
    }

    static func testValueText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
