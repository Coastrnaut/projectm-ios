// CoreMIDIInputProvider.swift — the system MIDI input (MIDI-002-R1-R3, R5, R7; contract C3; research
// MIDI-002-D1, D3, D4; ADR-0038 Decision 7).
//
// * Its own client (`MIDIClientCreateWithBlock`, no notify block) and one input port from
//   `MIDIInputPortCreateWithProtocol(…, ._1_0, …)`, created on the first open and kept for the process
//   (Apple advises against disposing CoreMIDI objects on iOS, as MIDI-001's provider does).
// * `connect(sources:)` (main thread) re-enumerates endpoints exactly like `CoreMIDIEndpointProvider`,
//   drops network-attributed ones, assigns MIDI-001 IDs and connects the requested sources with a nil
//   `connRefCon`, disconnecting the rest. The receive block therefore cannot tell sources apart, and nothing
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
        var connected: [MIDIEndpointRef] = []
    }

    private let lockedState = Mutex(State())

    public init() {}

    public func open(into ring: MIDIEventRing) -> MIDIProviderStartResult {
        lockedState.withLock { (s: inout State) -> MIDIProviderStartResult in
            if let receiver = s.receiver, s.port != 0 {
                precondition(receiver.ring === ring, "one ring per provider")
                receiver.isOpen.store(true, ordering: .releasing)
                return .started
            }
            if s.client == 0 {
                var client: MIDIClientRef = 0
                let status: OSStatus = MIDIClientCreateWithBlock("projectM input" as CFString, &client, nil)
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
            receiver.isOpen.store(true, ordering: .releasing)
            return .started
        }
    }

    public func connect(sources: Set<MIDIEndpointID>) {
        let wanted: [MIDIEndpointRef] = Self.sourceRefs(for: sources)
        lockedState.withLock { (s: inout State) -> Void in
            guard s.port != 0 else { return }
            for endpoint in s.connected where !wanted.contains(endpoint) {
                _ = MIDIPortDisconnectSource(s.port, endpoint)
            }
            var now: [MIDIEndpointRef] = []
            for endpoint in wanted {
                if s.connected.contains(endpoint) || MIDIPortConnectSource(s.port, endpoint, nil) == noErr {
                    now.append(endpoint)
                }
            }
            s.connected = now
        }
    }

    public func close() {
        lockedState.withLock { (s: inout State) -> Void in
            s.receiver?.isOpen.store(false, ordering: .releasing)
            for endpoint in s.connected { _ = MIDIPortDisconnectSource(s.port, endpoint) }
            s.connected = []
        }
    }

    /// The system sources whose MIDI-001 ID is requested (IDs assigned over the same snapshot as discovery).
    static func sourceRefs(for ids: Set<MIDIEndpointID>) -> [MIDIEndpointRef] {
        guard !ids.isEmpty else { return [] }
        var refs: [MIDIEndpointRef] = []
        var records: [MIDIEndpointRecord] = []
        let sources: Int = MIDIGetNumberOfSources()
        let destinations: Int = MIDIGetNumberOfDestinations()
        for index in 0..<sources {
            let endpoint: MIDIEndpointRef = MIDIGetSource(index)
            if endpoint != 0 {
                refs.append(endpoint)
                records.append(CoreMIDIEndpointProvider.record(endpoint, direction: .source))
            }
        }
        for index in 0..<destinations {
            let endpoint: MIDIEndpointRef = MIDIGetDestination(index)
            if endpoint != 0 {
                refs.append(0)
                records.append(CoreMIDIEndpointProvider.record(endpoint, direction: .destination))
            }
        }
        var listedRefs: [MIDIEndpointRef] = []
        var listed: [MIDIEndpointRecord] = []
        for (index, record) in records.enumerated() where record.transport != .network {
            listedRefs.append(refs[index])
            listed.append(record)
        }
        let assigned: [MIDIEndpointID] = MIDIEndpointIdentity.assign(listed)
        var wanted: [MIDIEndpointRef] = []
        for (index, id) in assigned.enumerated() where listedRefs[index] != 0 && ids.contains(id) {
            wanted.append(listedRefs[index])
        }
        return wanted
    }
}
#endif
