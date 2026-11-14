// MIDIDiscoveryCoordinator.swift — MIDI endpoint discovery in the app (MIDI-001; specs/107-midi-001-midi-endpoint-discovery,
// contracts/midi-discovery.md C3).
//
// * Discovery runs only while the user has turned "Listen for MIDI devices" on AND the app is active in
//   the foreground (MIDI-001-R7): leaving the foreground or turning it off clears the list.
// * Updates arrive on discovery's serial queue and are copied onto the main actor; the list shown is
//   always discovery's latest, so a late update can never bring back an older list.
// * Appearances and disappearances after the first list are announced once per update through the
//   shared announcer (`announce`, wired to `AccessibilityAnnouncer` kind `.midi`; MIDI-001-R11). The
//   first list after a start is silent; the status line states the count.
// * Nothing is stored except the toggle (`settings.midi.enabled`), and no name is logged (MIDI-001-R10).
// No MIDI message is received in MIDI-001; this is discovery only (ADR-0038).
import Foundation
import Observation
import PerformanceControl

/// One Settings row (contract C3).
struct MIDIEndpointRow: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let accessibilityLabel: String
}

@MainActor
@Observable
final class MIDIDiscoveryCoordinator {
    static let unavailableText = "MIDI isn't available on this device."
    static let backgroundText = "Paused while projectM is in the background."

    private(set) var state: MIDIDiscoveryState = .off
    private(set) var list: MIDIEndpointList = .empty

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored let discovery: MIDIEndpointDiscovery
    @ObservationIgnored private(set) var appIsActive: Bool
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    init(settings: AppSettings, discovery: MIDIEndpointDiscovery = .system(), appIsActive: Bool = true,
         announce: @escaping @MainActor (String) -> Void = { (_: String) -> Void in }) {
        self.settings = settings
        self.discovery = discovery
        self.appIsActive = appIsActive
        self.announce = announce
        discovery.onUpdate { [weak self] (update: MIDIDiscoveryUpdate) -> Void in
            Self.onMain { self?.receive(update) }
        }
        discovery.onStateChange { [weak self] (_: MIDIDiscoveryState) -> Void in
            Self.onMain { self?.refresh() }
        }
        apply()
    }

    /// Runs `work` on the main actor: at once when already on the main thread (tests' manual scheduler),
    /// otherwise as a main-actor task (discovery's queue in the app).
    nonisolated private static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }

    var isEnabled: Bool { settings.midiEnabled }

    func setEnabled(_ enabled: Bool) {
        settings.midiEnabled = enabled
        apply()
    }

    func sceneBecame(active: Bool) {
        appIsActive = active
        apply()
    }

    /// Discovering iff enabled and active (C3).
    private func apply() {
        if settings.midiEnabled && appIsActive {
            discovery.start()
        } else {
            discovery.stop()
        }
        refresh()
    }

    private func refresh() {
        state = discovery.state
        list = discovery.endpoints
    }

    private func receive(_ update: MIDIDiscoveryUpdate) {
        guard discovery.state.isListening else { return }   // stopped since: nothing to show or say
        refresh()
        if let text = Self.announcement(for: update) { announce(text) }
    }

    // MARK: Rows and texts (contract C3; unit-tested)

    var rows: [MIDIEndpointRow] { Self.rows(for: list) }

    var statusText: String { Self.statusText(for: state, enabled: isEnabled, count: list.count) }

    static func rows(for list: MIDIEndpointList) -> [MIDIEndpointRow] {
        let names: [MIDIEndpointID: String] = list.displayNames
        return list.endpoints.map { (endpoint: MIDIEndpoint) -> MIDIEndpointRow in
            let title: String = names[endpoint.id] ?? endpoint.name
            let detail: String = Self.detail(for: endpoint)
            return MIDIEndpointRow(id: endpoint.id.description, title: title, detail: detail,
                                   accessibilityLabel: title + ", " + detail)
        }
    }

    static func detail(for endpoint: MIDIEndpoint) -> String {
        var parts: [String] = [endpoint.direction == .source ? "Input" : "Output"]
        if endpoint.isVirtual { parts.append("Virtual") }
        if !endpoint.isOnline { parts.append("Offline") }
        return parts.joined(separator: ", ")
    }

    static func statusText(for state: MIDIDiscoveryState, enabled: Bool, count: Int) -> String {
        switch state {
        case .off:
            return enabled ? backgroundText : "Off"
        case .unavailable:
            return unavailableText
        case .listening:
            switch count {
            case 0: return "Listening — no MIDI devices"
            case 1: return "Listening — 1 device"
            default: return "Listening — " + String(count) + " devices"
            }
        }
    }

    /// One text per update (research MIDI-001-D7); nil for the first list and for renames or online
    /// changes only. A device's input and output count as one device, named by the device.
    static func announcement(for update: MIDIDiscoveryUpdate) -> String? {
        guard !update.isInitial else { return nil }
        var connected: [String] = []
        var disconnected: [String] = []
        for change in update.changes {
            switch change {
            case .appeared(let endpoint):
                let name: String = deviceLabel(endpoint)
                if !connected.contains(name) { connected.append(name) }
            case .disappeared(let endpoint):
                let name: String = deviceLabel(endpoint)
                if !disconnected.contains(name) { disconnected.append(name) }
            case .renamed, .onlineChanged:
                break
            }
        }
        var sentences: [String] = []
        if let sentence = sentence(connected, verb: "connected") { sentences.append(sentence) }
        if let sentence = sentence(disconnected, verb: "disconnected") { sentences.append(sentence) }
        return sentences.isEmpty ? nil : sentences.joined(separator: ". ")
    }

    private static func deviceLabel(_ endpoint: MIDIEndpoint) -> String {
        let device: String = endpoint.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.isVirtual || device.isEmpty ? endpoint.name : device
    }

    private static func sentence(_ names: [String], verb: String) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return "MIDI device " + verb + ": " + names[0]
        default: return String(names.count) + " MIDI devices " + verb
        }
    }
}
