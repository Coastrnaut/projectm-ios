// CoreMIDIFeedbackOutput.swift — the system MIDI output for feedback (MIDI-009-R9; specs/269-midi-009-midi-feedback,
// contract F5, research MIDI-009-D6; ADR-0080).
//
// * Its own client ("projectM feedback") and one output port from `MIDIOutputPortCreate`, created on the first send
//   and kept for the process (Apple advises against disposing CoreMIDI objects on iOS).
// * Each send builds one MIDI 1.0 event list (`MIDIEventListInit(…, ._1_0)`, one `MIDIEventListAdd` per message) in a
//   buffer allocated once, then `MIDISendEventList` to each wanted destination.
// * Destination IDs resolve by the MIDI-001 rule (`MIDIEndpointList.make` drops network-attributed endpoints, then
//   `MIDIEndpointIdentity.assign`), so a network destination can never be addressed. Network MIDI is never referenced
//   (ADR-0038). Main actor only in the app; nothing is logged.
#if canImport(CoreMIDI)
import CoreMIDI

public final class CoreMIDIFeedbackOutput: MIDIFeedbackOutput {
    private static let bufferSize: Int = 4096
    /// Far below what one list in `bufferSize` holds (each packet takes at most 24 bytes for one word).
    private static let maximumMessages: Int = 128

    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private let buffer: UnsafeMutableRawPointer

    public init() {
        buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 8)
    }

    deinit { buffer.deallocate() }

    public func send(_ messages: [MIDIFeedbackMessage], to destinations: Set<MIDIEndpointID>) {
        guard !messages.isEmpty, !destinations.isEmpty, openPort() else { return }
        let targets: [MIDIEndpointRef] = resolve(destinations)
        guard !targets.isEmpty else { return }
        let list: UnsafeMutablePointer<MIDIEventList> = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)
        var packet: UnsafeMutablePointer<MIDIEventPacket> = MIDIEventListInit(list, ._1_0)
        // At most 16 one-word messages per tick (MIDI-009-R6) fit the buffer many times over; `prefix` keeps any list
        // within it regardless.
        for message in messages.prefix(Self.maximumMessages) {
            var word: UInt32 = MIDIFeedbackUMP.word(message)
            packet = MIDIEventListAdd(list, Self.bufferSize, packet, 0, 1, &word)
        }
        for target in targets { _ = MIDISendEventList(port, target, list) }
    }

    private func openPort() -> Bool {
        if port != 0 { return true }
        if client == 0 {
            var created: MIDIClientRef = 0
            let status: OSStatus = MIDIClientCreateWithBlock("projectM feedback" as CFString, &created, nil)
            guard status == noErr, created != 0 else { return false }
            client = created
        }
        var created: MIDIPortRef = 0
        let status: OSStatus = MIDIOutputPortCreate(client, "projectM feedback" as CFString, &created)
        guard status == noErr, created != 0 else { return false }
        port = created
        return true
    }

    /// The destination references whose MIDI-001 IDs are wanted (same enumeration and ID rule as discovery).
    private func resolve(_ wanted: Set<MIDIEndpointID>) -> [MIDIEndpointRef] {
        var records: [MIDIEndpointRecord] = []
        var references: [MIDIEndpointRef] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint: MIDIEndpointRef = MIDIGetSource(index)
            if endpoint != 0 {
                records.append(CoreMIDIEndpointProvider.record(endpoint, direction: .source))
                references.append(0)
            }
        }
        for index in 0..<MIDIGetNumberOfDestinations() {
            let endpoint: MIDIEndpointRef = MIDIGetDestination(index)
            if endpoint != 0 {
                records.append(CoreMIDIEndpointProvider.record(endpoint, direction: .destination))
                references.append(endpoint)
            }
        }
        var listed: [MIDIEndpointRecord] = []
        var listedReferences: [MIDIEndpointRef] = []
        for (record, reference) in zip(records, references) where record.transport != .network {
            listed.append(record)
            listedReferences.append(reference)
        }
        let ids: [MIDIEndpointID] = MIDIEndpointIdentity.assign(listed)
        var result: [MIDIEndpointRef] = []
        for (index, id) in ids.enumerated() where listedReferences[index] != 0 && wanted.contains(id) {
            if !listed[index].isOffline { result.append(listedReferences[index]) }
        }
        return result
    }
}
#endif
