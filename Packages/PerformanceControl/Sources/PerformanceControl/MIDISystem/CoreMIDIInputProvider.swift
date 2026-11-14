// CoreMIDIInputProvider.swift — the system MIDI input (MIDI-002-R1-R3, R5, R7; contract C3; research
// MIDI-002-D1, D3, D4; ADR-0038 Decision 7).
//
// * Its own client (`MIDIClientCreateWithBlock`, with a notify block since MIDI-011) and one input port from
//   `MIDIInputPortCreateWithProtocol(…, ._1_0, …)`, created on the first open and kept for the process
//   (Apple advises against disposing CoreMIDI objects on iOS, as MIDI-001's provider does).
// * `connect(sources:)` (main thread) hands the wanted MIDI-001 IDs to `MIDISourceSubscriptions` (MIDI-011): it
//   enumerates like `CoreMIDIEndpointProvider`, drops network-attributed ones, keys connections by stable ID with the
//   current reference, connects each present source once with a nil `connRefCon` and disconnects the rest. The
//   client's notify block (MIDI-011) marks removed sources and schedules one coalesced reconcile per burst, so a
//   replug is reattached even when discovery's list never changed. The receive block therefore cannot tell sources apart, and nothing
//   about a source reaches an event (MIDI-002-R7).
// * The receive block (CoreMIDI's thread, one call at a time) walks the `MIDIEventList` in place, converts the
//   packet's host time to nanoseconds with a timebase read once at init (0 → now), and decodes the UMP words
//   straight into the ring: no allocation, lock, logging or dispatch per message. While closed it returns at
//   once. Nothing received is logged.
#if canImport(CoreMIDI)
import CoreMIDI
import Darwin
import Synchronization

public final class CoreMIDIInputProvider: MIDIInputProvider {
    /// What the receive block touches: only its own thread mutates `decoder`; `isOpen` gates delivery.
    final class Receiver: @unchecked Sendable {
        let ring: MIDIEventRing
        let isOpen = Atomic<Bool>(false)
        var decoder = MIDIUMPDecoder()
        let numer: UInt64
        let denom: UInt64
        let numPacketsOffset: Int
        let packetOffset: Int
        let wordsOffset: Int
        let wordCountOffset: Int
        let timeStampOffset: Int

        init(ring: MIDIEventRing) {
            self.ring = ring
            var info = mach_timebase_info_data_t()
            _ = mach_timebase_info(&info)
            numer = UInt64(max(info.numer, 1))
            denom = UInt64(max(info.denom, 1))
            numPacketsOffset = MemoryLayout<MIDIEventList>.offset(of: \MIDIEventList.numPackets) ?? 4
            packetOffset = MemoryLayout<MIDIEventList>.offset(of: \MIDIEventList.packet) ?? 8
            wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words) ?? 12
            wordCountOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.wordCount) ?? 8
            timeStampOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.timeStamp) ?? 0
        }

        /// Real-time: reads the list in place; no allocation, no locks.
        func receive(_ list: UnsafePointer<MIDIEventList>) {
            guard isOpen.load(ordering: .acquiring) else { return }
            let base: UnsafeRawPointer = UnsafeRawPointer(list)
            let packets: Int = Int(base.loadUnaligned(fromByteOffset: numPacketsOffset, as: UInt32.self))
            var packet: UnsafeRawPointer = base + packetOffset
            var sink: MIDIEventRing = ring
            for _ in 0..<packets {
                let wordCount: Int = min(Int(packet.loadUnaligned(fromByteOffset: wordCountOffset, as: UInt32.self)), 64)
                let ticks: UInt64 = packet.loadUnaligned(fromByteOffset: timeStampOffset, as: UInt64.self)
                let hostTicks: UInt64 = ticks == 0 ? mach_absolute_time() : ticks
                let nanoseconds: UInt64 = (hostTicks / denom) * numer + (hostTicks % denom) * numer / denom
                let words: UnsafePointer<UInt32> = (packet + wordsOffset).assumingMemoryBound(to: UInt32.self)
                decoder.decode(UnsafeBufferPointer(start: words, count: wordCount), timestamp: nanoseconds, into: &sink)
                packet = packet + wordsOffset + wordCount * MemoryLayout<UInt32>.size   // MIDIEventPacketNext
            }
        }
    }

    private struct State {
        var client: MIDIClientRef = 0
        var port: MIDIPortRef = 0
        var receiver: Receiver?
    }

    private let lockedState = Mutex(State())
    private let system: CoreMIDISourceSystem
    /// MIDI-011: connections keyed by stable ID, reconciled on setup notifications (coalesced).
    let subscriptions: MIDISourceSubscriptions

    public init() {
        let system = CoreMIDISourceSystem()
        self.system = system
        self.subscriptions = MIDISourceSubscriptions(system: system)
    }

    public func open(into ring: MIDIEventRing) -> MIDIProviderStartResult {
        lockedState.withLock { (s: inout State) -> MIDIProviderStartResult in
            if let receiver = s.receiver, s.port != 0 {
                precondition(receiver.ring === ring, "one ring per provider")
                receiver.isOpen.store(true, ordering: .releasing)
                return .started
            }
            if s.client == 0 {
                var client: MIDIClientRef = 0
                let subscriptions: MIDISourceSubscriptions = self.subscriptions
                // MIDI-011-R4: the input follows setup changes itself (one coalesced reconcile per burst).
                let status: OSStatus = MIDIClientCreateWithBlock("projectM input" as CFString, &client) {
                    (notification: UnsafePointer<MIDINotification>) -> Void in
                    Self.handle(notification, subscriptions: subscriptions)
                }
                guard status == noErr, client != 0 else { return .unavailable(code: status) }
                s.client = client
            }
            let receiver = Receiver(ring: ring)
            var port: MIDIPortRef = 0
            let status: OSStatus = MIDIInputPortCreateWithProtocol(s.client, "projectM input" as CFString, ._1_0, &port) {
                (list: UnsafePointer<MIDIEventList>, _: UnsafeMutableRawPointer?) -> Void in
                receiver.receive(list)
            }
            guard status == noErr, port != 0 else { return .unavailable(code: status) }
            s.port = port
            s.receiver = receiver
            system.setPort(port)
            receiver.isOpen.store(true, ordering: .releasing)
            return .started
        }
    }

    /// CoreMIDI's notification thread: a removed source is marked (its connection is gone even if its reference
    /// returns); any setup change schedules one coalesced reconcile. No allocation-heavy work here.
    private static func handle(_ notification: UnsafePointer<MIDINotification>, subscriptions: MIDISourceSubscriptions) {
        switch notification.pointee.messageID {
        case .msgObjectRemoved:
            let removal: MIDIObjectAddRemoveNotification = UnsafeRawPointer(notification)
                .load(as: MIDIObjectAddRemoveNotification.self)
            if removal.childType == .source {
                subscriptions.sourceRemoved(handle: removal.child)
            } else {
                subscriptions.setupChanged()
            }
        case .msgSetupChanged, .msgObjectAdded, .msgPropertyChanged:
            subscriptions.setupChanged()
        default:
            break
        }
    }

    public func connect(sources: Set<MIDIEndpointID>) {
        let open: Bool = lockedState.withLock { (s: inout State) -> Bool in s.port != 0 }
        guard open else { return }
        subscriptions.update(wanted: sources)
    }

    public func close() {
        lockedState.withLock { (s: inout State) -> Void in
            s.receiver?.isOpen.store(false, ordering: .releasing)
        }
        subscriptions.close()
    }

    public var sourceLossCount: Int { subscriptions.lossCount }
}

/// CoreMIDI behind `MIDISourceSystem` (MIDI-011-D1): enumeration as discovery reads it, connections on the input port
/// with a nil `connRefCon` (the receive block cannot tell sources apart; MIDI-002-R7).
final class CoreMIDISourceSystem: MIDISourceSystem {
    private let port = Atomic<UInt32>(0)

    func setPort(_ ref: MIDIPortRef) { port.store(ref, ordering: .releasing) }

    func snapshot() -> [MIDISourceSnapshot] {
        var items: [MIDISourceSnapshot] = []
        let sources: Int = MIDIGetNumberOfSources()
        let destinations: Int = MIDIGetNumberOfDestinations()
        items.reserveCapacity(sources + destinations)
        for index in 0..<sources {
            let endpoint: MIDIEndpointRef = MIDIGetSource(index)
            if endpoint != 0 {
                items.append(MIDISourceSnapshot(handle: endpoint, record: CoreMIDIEndpointProvider.record(endpoint, direction: .source)))
            }
        }
        for index in 0..<destinations {
            let endpoint: MIDIEndpointRef = MIDIGetDestination(index)
            if endpoint != 0 {
                items.append(MIDISourceSnapshot(handle: 0, record: CoreMIDIEndpointProvider.record(endpoint, direction: .destination)))
            }
        }
        return items
    }

    func connect(_ handle: UInt32) -> Bool {
        let ref: MIDIPortRef = port.load(ordering: .acquiring)
        guard ref != 0 else { return false }
        return MIDIPortConnectSource(ref, handle, nil) == noErr
    }

    func disconnect(_ handle: UInt32) {
        let ref: MIDIPortRef = port.load(ordering: .acquiring)
        guard ref != 0 else { return }
        _ = MIDIPortDisconnectSource(ref, handle)
    }
}
#endif
