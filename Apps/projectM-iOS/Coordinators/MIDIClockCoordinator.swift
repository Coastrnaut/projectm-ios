// MIDIClockCoordinator.swift — "Follow MIDI clock" (MIDI-010-R5 to R7; specs/273-midi-010-midi-clock-receive,
// contracts/midi-clock.md C4; research MIDI-010-D2, D8).
//
// * The setting `settings.midi.followClock` (absent = off) is stored here, outside `AppSettings.allKeys`: excluded
//   from library backups (this device's MIDI setup, like Listen for MIDI devices), erased with Settings.
// * While following, the coordinator is the shared input's client "midiClock" (so the input receives while discovery
//   listens), enables the ring's clock lane and, on every delivered batch, feeds the lane's events (clock pulses with
//   their timestamps, in order with Start, Continue, Stop and Song Position) to a `MIDIClockTracker`. A 100 ms task
//   checks the 0.5 s timeout, because the input calls clients only when something arrives; tests call `tick()`.
// * The tracker's tempo (locked only) goes to `TempoCoordinator.updateMIDIClock`; off, the input stopping or the clock
//   lost hand it nil, so the tempo falls back to tap, else the estimate.
// * MIDI Start/Stop never act on the show here (MIDI-008's learned rows do that).
// Nothing here logs or stores messages, times or endpoints.
import AudioCore
import Foundation
import Observation
import PerformanceControl

@MainActor
@Observable
final class MIDIClockCoordinator {
    static let followKey: String = "settings.midi.followClock"
    static let allKeys: [String] = [followKey]
    static let clientName: String = "midiClock"
    static let tickInterval: Duration = .milliseconds(100)

    private(set) var isFollowing: Bool
    private(set) var status: MIDIClockStatus = .noClock
    private(set) var isListening: Bool = false

    @ObservationIgnored private let input: MIDIInputCoordinator
    @ObservationIgnored private let tempo: TempoCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> UInt64
    @ObservationIgnored private let runsTicker: Bool
    @ObservationIgnored private var tracker = MIDIClockTracker()
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var scratch: [MIDIEvent] = []

    /// `now`: monotonic nanoseconds on the events' clock (the system's uptime clock).
    init(input: MIDIInputCoordinator, tempo: TempoCoordinator, defaults: UserDefaults,
         now: @escaping @MainActor () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() },
         runsTicker: Bool = true) {
        self.input = input
        self.tempo = tempo
        self.defaults = defaults
        self.now = now
        self.runsTicker = runsTicker
        isFollowing = defaults.bool(forKey: Self.followKey)
        scratch.reserveCapacity(MIDIClockLane.defaultCapacity)
        input.addStateObserver { [weak self] () -> Void in self?.inputStateChanged() }
        apply()
    }

    isolated deinit {
        tickTask?.cancel()
    }

    private var lane: MIDIClockLane { input.service.ring.clockLane }

    // MARK: Setting

    func setFollowing(_ on: Bool) {
        guard on != isFollowing else { return }
        isFollowing = on
        if on { defaults.set(true, forKey: Self.followKey) } else { defaults.removeObject(forKey: Self.followKey) }
        apply()
    }

    /// Re-reads the stored value (after a Settings erase or restore).
    func refresh() {
        let stored: Bool = defaults.bool(forKey: Self.followKey)
        guard stored != isFollowing else { return }
        isFollowing = stored
        apply()
    }

    private func apply() {
        if isFollowing {
            lane.discardAll()
            lane.isEnabled = true
            input.addClient(Self.clientName) { [weak self] (_: [MIDIEvent]) -> Void in self?.drainLane() }
            startTicker()
        } else {
            input.removeClient(Self.clientName)
            lane.isEnabled = false
            lane.discardAll()
            stopTicker()
            tracker.reset()
            publish()
        }
    }

    private func inputStateChanged() {
        let listening: Bool = input.isDiscoveryListening
        if listening != isListening { isListening = listening }
        if !input.isReceiving {   // the input stopped: whatever the clock was doing is unknown now
            tracker.reset()
            publish()
        }
    }

    // MARK: Clock

    /// Feeds the lane's events to the tracker (each input batch; tests call `input.drain()`).
    func drainLane() {
        guard isFollowing else { return }
        scratch.removeAll(keepingCapacity: true)
        lane.drain(into: &scratch)
        for event in scratch { tracker.receive(event) }
        tracker.tick(now: now())
        publish()
    }

    /// Checks the timeout (the 100 ms task; tests call it directly).
    func tick() {
        guard isFollowing else { return }
        tracker.tick(now: now())
        publish()
    }

    private func publish() {
        let next: MIDIClockStatus = isFollowing ? tracker.status : .noClock
        if next != status { status = next }
        tempo.updateMIDIClock(isFollowing ? tracker.tempo : nil)
    }

    private func startTicker() {
        guard runsTicker, tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: MIDIClockCoordinator.tickInterval)
                self?.tick()
            }
        }
    }

    private func stopTicker() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: Texts (contracts/midi-clock.md C4)

    var statusText: String { Self.statusText(status, isListening: isListening) }

    /// "MIDI clock: 120.0 BPM", "MIDI clock: measuring", "MIDI clock: stopped", "MIDI clock: out of range",
    /// "No MIDI clock", or "Turn on Listen for MIDI devices" while discovery does not listen.
    static func statusText(_ status: MIDIClockStatus, isListening: Bool) -> String {
        guard isListening else { return "Turn on Listen for MIDI devices" }
        switch status {
        case .locked(let bpm):
            let tenths: Int = Int((bpm * 10).rounded())
            let text: String = String(tenths / 10) + "." + String(tenths % 10)
            return "MIDI clock: " + text + " BPM"
        case .acquiring:
            return "MIDI clock: measuring"
        case .stopped:
            return "MIDI clock: stopped"
        case .outOfRange:
            return "MIDI clock: out of range"
        case .noClock:
            return "No MIDI clock"
        }
    }
}
