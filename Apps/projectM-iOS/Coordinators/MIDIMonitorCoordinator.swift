// MIDIMonitorCoordinator.swift — the MIDI Monitor's state (MIDI-002-R6-R10, R15; specs/125-midi-002-midi-input-monitor,
// contracts/midi-input.md C4; data-model "Monitor entry").
//
// * `open()` registers the monitor as a client of the shared input; `close()` unregisters (receiving stops when
//   no other client needs it) and drops every entry and counter (MIDI-002-R8).
// * Entries: newest first, at most 64, in memory only. Each holds the message and its texts and the time since
//   the monitor opened or was last cleared ("12.40 s"). No entry names a source: `MIDIEvent` has no such field
//   (MIDI-002-R7). Nothing is logged or stored.
// * Pause freezes the list and counts what arrives; Clear empties entries and counters (MIDI-002-R9).
// * Timing clock, active sensing and messages dropped by the queue are counted in one summary line (R4, R5).
// * No announcement for live traffic (MIDI-002-R10): VoiceOver reads rows one by one.
import Foundation
import Observation
import PerformanceControl

/// One monitor row (data-model "Monitor entry").
struct MIDIMonitorEntry: Identifiable, Equatable {
    let id: Int
    let event: MIDIEvent
    let text: MIDIEventText
    /// "12.40 s"
    let time: String

    /// "Control change, channel 1, controller 7, value 100"
    var accessibilityLabel: String { text.spoken }
}

@MainActor
@Observable
final class MIDIMonitorCoordinator {
    static let entryLimit: Int = 64
    static let clientName: String = "monitor"
    static let offText: String = "Turn on Listen for MIDI devices to see messages."
    static let unavailableText: String = "MIDI isn't available on this device."

    private(set) var entries: [MIDIMonitorEntry] = []
    private(set) var isOpen = false
    private(set) var isPaused = false
    private(set) var whilePaused: Int = 0
    private(set) var clockCount: Int = 0
    private(set) var activeSensingCount: Int = 0
    private(set) var droppedCount: Int = 0
    private(set) var inputState: MIDIInputState = .off

    @ObservationIgnored private let input: MIDIInputCoordinator
    @ObservationIgnored private let discovery: MIDIDiscoveryCoordinator
    @ObservationIgnored private let clock: @MainActor () -> UInt64
    @ObservationIgnored private var origin: UInt64 = 0
    @ObservationIgnored private var nextID: Int = 0
    @ObservationIgnored private var clockBase: Int = 0
    @ObservationIgnored private var sensingBase: Int = 0
    @ObservationIgnored private var droppedBase: Int = 0

    /// `clock`: monotonic nanoseconds on the same clock as the events (the system's uptime clock).
    init(input: MIDIInputCoordinator, discovery: MIDIDiscoveryCoordinator,
         clock: @escaping @MainActor () -> UInt64 = { () -> UInt64 in DispatchTime.now().uptimeNanoseconds }) {
        self.input = input
        self.discovery = discovery
        self.clock = clock
        input.addStateObserver { [weak self] () -> Void in self?.inputStateChanged() }
    }

    // MARK: Lifecycle (the screen's appear and disappear)

    func open() {
        guard !isOpen else { return }
        isOpen = true
        resetContents()
        input.addClient(Self.clientName) { [weak self] (batch: [MIDIEvent]) -> Void in self?.receive(batch) }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        isPaused = false
        input.removeClient(Self.clientName)
        entries = []
        whilePaused = 0
        clockCount = 0
        activeSensingCount = 0
        droppedCount = 0
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused { whilePaused = 0 }
    }

    func clear() {
        resetContents()
    }

    private func resetContents() {
        entries = []
        whilePaused = 0
        origin = clock()
        let ring: MIDIEventRing = input.service.ring
        clockBase = ring.clockCount
        sensingBase = ring.activeSensingCount
        droppedBase = ring.dropped
        clockCount = 0
        activeSensingCount = 0
        droppedCount = 0
    }

    private func inputStateChanged() {
        inputState = input.state
    }

    // MARK: Receiving

    func receive(_ batch: [MIDIEvent]) {
        guard isOpen else { return }
        let ring: MIDIEventRing = input.service.ring
        clockCount = max(0, ring.clockCount - clockBase)
        activeSensingCount = max(0, ring.activeSensingCount - sensingBase)
        droppedCount = max(0, ring.dropped - droppedBase)
        guard !batch.isEmpty else { return }
        if isPaused {
            whilePaused += batch.count
            return
        }
        var added: [MIDIMonitorEntry] = []
        added.reserveCapacity(min(batch.count, Self.entryLimit))
        for event in batch.suffix(Self.entryLimit).reversed() {
            added.append(MIDIMonitorEntry(id: nextID, event: event, text: MIDIEventText(event), time: timeText(event.timestamp)))
            nextID += 1
        }
        var updated: [MIDIMonitorEntry] = added + entries
        if updated.count > Self.entryLimit { updated.removeLast(updated.count - Self.entryLimit) }
        entries = updated
    }

    /// Seconds since the monitor opened or was cleared, two decimals ("12.40 s"); 0 for earlier stamps.
    func timeText(_ timestamp: UInt64) -> String {
        let elapsed: UInt64 = timestamp > origin ? timestamp - origin : 0
        let centiseconds: UInt64 = elapsed / 10_000_000
        let whole: UInt64 = centiseconds / 100
        let fraction: UInt64 = centiseconds % 100
        let padded: String = fraction < 10 ? "0" + String(fraction) : String(fraction)
        return String(whole) + "." + padded + " s"
    }

    // MARK: Texts

    var statusText: String {
        if case .unavailable = discovery.state { return Self.unavailableText }
        if case .unavailable = inputState { return Self.unavailableText }
        guard discovery.state.isListening else { return Self.offText }
        if isPaused { return "Paused" }
        return entries.isEmpty ? "Waiting for MIDI messages" : "Receiving"
    }

    var summaryText: String {
        var parts: [String] = ["Clock " + String(clockCount), "Active sensing " + String(activeSensingCount),
                               "Dropped " + String(droppedCount)]
        if whilePaused > 0 { parts.append("While paused " + String(whilePaused)) }
        return parts.joined(separator: " · ")
    }
}
