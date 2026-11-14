// MIDIInputCoordinator.swift — the app's shared MIDI input (MIDI-002-R1, R2, R5; specs/125-midi-002-midi-input-monitor,
// contracts/midi-input.md C4; research MIDI-002-D5).
//
// * Features register as named clients with a batch handler (MIDI-002: the monitor; MIDI-003: learn). The input
//   receives iff at least one client is registered AND MIDI-001 discovery is listening (toggle on, app in the
//   foreground); otherwise the service is stopped and no source is connected.
// * While receiving, the service is connected to the online inputs of discovery's list and follows every list
//   change (plug, unplug). Network MIDI is never listed (ADR-0038), so it is never connected.
// * The ring is drained on the main actor by a `CADisplayLink` capped at 30 Hz; each non-empty batch (or a change
//   of the clock, active sensing or dropped counters) goes to every client. Tests drive `drain()` directly.
// * MIDI-011: the provider repairs connections on hot-plug by itself; when it reports a lost source, the next drain
//   runs the state observers first (held keys are released).
// Nothing here logs or stores messages or names an endpoint (MIDI-002-R7).
import Foundation
import Observation
import PerformanceControl
import QuartzCore

@MainActor
final class MIDIInputCoordinator {
    typealias BatchHandler = @MainActor ([MIDIEvent]) -> Void

    static let drainLimit: Int = MIDIEventRing.defaultCapacity

    let service: MIDIInputService
    private let discovery: MIDIDiscoveryCoordinator
    private var clients: [String: BatchHandler] = [:]
    private var stateObservers: [@MainActor () -> Void] = []
    private var ticker: MIDIDrainTicker?
    private let drivesDisplayLink: Bool
    private var batch: [MIDIEvent] = []
    private var lastCounters: Int = 0
    /// MIDI-011-R5: the provider's loss count at the last drain.
    private var lastLossCount: Int = 0

    init(service: MIDIInputService, discovery: MIDIDiscoveryCoordinator, drivesDisplayLink: Bool = true) {
        self.service = service
        self.discovery = discovery
        self.drivesDisplayLink = drivesDisplayLink
        batch.reserveCapacity(Self.drainLimit)
        discovery.addListObserver { [weak self] () -> Void in self?.apply() }
    }

    var state: MIDIInputState { service.state }
    var isReceiving: Bool { service.state.isReceiving }
    var isDiscoveryListening: Bool { discovery.state.isListening }
    var hasClients: Bool { !clients.isEmpty }
    /// MIDI-011-R5: increases each time the input saw a connected source go away (even if it came straight back).
    var sourceLossCount: Int { service.sourceLossCount }

    func addClient(_ name: String, handler: @escaping BatchHandler) {
        clients[name] = handler
        apply()
    }

    func removeClient(_ name: String) {
        clients[name] = nil
        apply()
    }

    /// Runs after every apply (clients read `state`).
    func addStateObserver(_ observer: @escaping @MainActor () -> Void) {
        stateObservers.append(observer)
    }

    /// The online inputs MIDI-001 lists.
    var listedSources: Set<MIDIEndpointID> {
        let inputs: [MIDIEndpoint] = discovery.list.endpoints.filter { (endpoint: MIDIEndpoint) -> Bool in
            endpoint.direction == .source && endpoint.isOnline
        }
        return Set(inputs.map { (endpoint: MIDIEndpoint) -> MIDIEndpointID in endpoint.id })
    }

    /// Receiving iff a client and discovery listening (MIDI-002-R1).
    private func apply() {
        if !clients.isEmpty && discovery.state.isListening {
            service.start(sources: listedSources)
        } else {
            service.stop()
        }
        updateTicker()
        for observer in stateObservers { observer() }
    }

    private func updateTicker() {
        guard drivesDisplayLink else { return }
        if service.state.isReceiving {
            if ticker == nil {
                let created = MIDIDrainTicker { [weak self] () -> Void in self?.drain() }
                created.start()
                ticker = created
            }
        } else {
            ticker?.stop()
            ticker = nil
        }
    }

    /// Moves queued events to the clients (display rate in the app; called directly by tests).
    func drain() {
        let losses: Int = service.sourceLossCount
        if losses != lastLossCount {   // MIDI-011-R5: observers release held keys before newer messages arrive
            lastLossCount = losses
            for observer in stateObservers { observer() }
        }
        batch.removeAll(keepingCapacity: true)
        service.ring.drain(into: &batch, maxCount: Self.drainLimit)
        let counters: Int = service.ring.clockCount &+ service.ring.activeSensingCount &+ service.ring.dropped
        guard !batch.isEmpty || counters != lastCounters else { return }
        lastCounters = counters
        for handler in clients.values { handler(batch) }
    }
}

/// A display link capped at 30 Hz that calls `tick` on the main actor (MIDI-002 spec Clarifications).
@MainActor
final class MIDIDrainTicker: NSObject {
    private var link: CADisplayLink?
    private let tick: @MainActor () -> Void

    init(tick: @escaping @MainActor () -> Void) {
        self.tick = tick
    }

    func start() {
        guard link == nil else { return }
        let created = CADisplayLink(target: self, selector: #selector(fire))
        created.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        created.add(to: .main, forMode: .common)
        link = created
    }

    /// Invalidates the link (it retains its target until then).
    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func fire() { tick() }
}
