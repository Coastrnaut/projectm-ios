// UITestFakeMIDI.swift — a stand-in MIDI system for MIDIDiscoveryUITests (MIDI-001-R15; research
// MIDI-001-D8). DEBUG builds only, and only with `-uitestFakeMIDI`. Release builds contain none of this.
//
// The simulator has no MIDI hardware, so the coordinator gets a scripted provider holding one virtual
// output ("Fake Synth", an app's endpoint); the panel's buttons plug and unplug "Fake Keys", a device
// with one input and one output and fixed unique numbers, so a replug keeps its IDs. Discovery, the
// coalescing delay and the list are the app's real code.
// MIDI-011: the input runs over a scripted source system with endpoint handles (a new handle per plug), so the
// app's input reattaches Fake Keys through its own subscriptions, as after a real replug.
#if DEBUG
import Foundation
import PerformanceControl
import SwiftUI

enum UITestFakeMIDI {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestFakeMIDI") }

    static let synthID: Int32 = 0x5000_0001
    static let keysInputID: Int32 = 0x5000_0010
    static let keysOutputID: Int32 = 0x5000_0011

    static let synth = MIDIEndpointRecord(uniqueID: synthID, direction: .destination, displayName: "Fake Synth", isVirtual: true)

    static let provider = ScriptedMIDIEndpointProvider(records: [synth])

    static let keys: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: keysInputID, direction: .source, displayName: "Fake Keys",
                           endpointName: "Port 1", entityName: "Fake Keys", deviceName: "Fake Keys"),
        MIDIEndpointRecord(uniqueID: keysOutputID, direction: .destination, displayName: "Fake Keys",
                           endpointName: "Port 1", entityName: "Fake Keys", deviceName: "Fake Keys"),
    ]

    /// MIDI-011: the stand-in system behind the input, with endpoint handles: every plug of Fake Keys gets a new
    /// handle, and the input reconnects it through its own subscriptions (one live connection per endpoint).
    static let sourceSystem = ScriptedMIDISourceSystem(records: [synth])

    /// MIDI-002: the stand-in input; it delivers only while a client receives and Fake Keys (an input) is connected,
    /// once per live connection, like a real port.
    static let inputProvider = ScriptedMIDISourceInputProvider(system: sourceSystem)

    /// MIDI-002: the input over the stand-in when the launch arguments ask for it.
    static func inputServiceIfRequested() -> MIDIInputService? {
        isRequested ? MIDIInputService(provider: inputProvider) : nil
    }

    /// Control change, channel 1, controller 7, value 100.
    static func sendControlChange() {
        send([0xB0, 0x07, 0x64], timestamp: DispatchTime.now().uptimeNanoseconds)
    }

    /// Note on, channel 1, note 60 (C4), velocity 100.
    static func sendNote() {
        send([0x90, 0x3C, 0x64], timestamp: DispatchTime.now().uptimeNanoseconds)
    }

    /// MIDI-007: program change, channel 1, program 5.
    static func sendProgramChange() {
        send([0xC0, 0x05], timestamp: DispatchTime.now().uptimeNanoseconds)
    }

    /// MIDI-008: a CC button press and release, channel 1, controller 20: 127 then 0 (one packet list).
    static func sendControlButton() {
        send([0xB0, 0x14, 0x7F, 0xB0, 0x14, 0x00], timestamp: DispatchTime.now().uptimeNanoseconds)
    }

    /// Fake Keys' input sends these bytes now.
    private static func send(_ bytes: [UInt8], timestamp: UInt64) {
        inputProvider.send(bytes, from: keysInputID, timestamp: timestamp)
    }

    /// Discovery over the stand-in when the launch arguments ask for it.
    static func discoveryIfRequested() -> MIDIEndpointDiscovery? {
        isRequested ? MIDIEndpointDiscovery(provider: provider) : nil
    }

    static func plugKeys() {
        let present: Bool = provider.currentEndpoints().contains { (record: MIDIEndpointRecord) -> Bool in record.uniqueID == keysInputID }
        if !present {
            sourceSystem.plug(keys)   // MIDI-011: new handles, as after a real replug
            provider.plug(keys)
        }
    }

    static func unplugKeys() {
        sourceSystem.unplug(uniqueIDs: [keysInputID, keysOutputID])
        provider.unplug(uniqueIDs: [keysInputID, keysOutputID])
    }
}

struct UITestFakeMIDIPanel: View {
    /// The rows the section shows below, as one readout that stays on screen while the list grows
    /// (`midiFakeRows`, the rows' labels joined by " | ").
    let rows: [MIDIEndpointRow]

    /// Separate rows: two buttons in one List row both fire on a tap of the row.
    var body: some View {
        Text(rows.map { (row: MIDIEndpointRow) -> String in row.accessibilityLabel }.joined(separator: " | "))
            .font(.caption2)
            .accessibilityIdentifier("midiFakeRows")
        Button("Plug Fake Keys") { UITestFakeMIDI.plugKeys() }
            .accessibilityIdentifier("midiFakePlug")
        Button("Unplug Fake Keys") { UITestFakeMIDI.unplugKeys() }
            .accessibilityIdentifier("midiFakeUnplug")
    }
}
#endif

#if DEBUG
/// MIDI-002: buttons on the MIDI Monitor that inject a control change and a note through the stand-in input.
struct UITestFakeMIDIInputPanel: View {
    var body: some View {
        Button("Send CC") { UITestFakeMIDI.sendControlChange() }
            .accessibilityIdentifier("midiFakeSendCC")
        Button("Send Note") { UITestFakeMIDI.sendNote() }
            .accessibilityIdentifier("midiFakeSendNote")
        Button("Send Program") { UITestFakeMIDI.sendProgramChange() }   // MIDI-007
            .accessibilityIdentifier("midiFakeSendProgram")
        Button("Send CC Button") { UITestFakeMIDI.sendControlButton() }   // MIDI-008
            .accessibilityIdentifier("midiFakeSendCCButton")
    }
}
#endif

#if DEBUG
/// MIDI-013: "Hold Note" (note on 60, channel 1, no release) and a readout of the held trigger keys ("1 held"), polled
/// because the router state is not observed.
struct UITestFakeMIDIPanicProbe: View {
    let mappings: MIDIMappingCoordinator

    var body: some View {
        Button("Hold Note") { UITestFakeMIDI.sendNote() }
            .accessibilityIdentifier("midiFakeHoldNote")
        TimelineView(.periodic(from: .now, by: 0.2)) { (_: TimelineViewDefaultContext) in
            Text(String(mappings.heldKeyCount) + " held")
                .font(.caption2)
                .accessibilityIdentifier("midiHeldProbe")
        }
    }
}
#endif
