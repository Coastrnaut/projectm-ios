// UITestFakeMIDI.swift — a stand-in MIDI system for MIDIDiscoveryUITests (MIDI-001-R15; research
// MIDI-001-D8). DEBUG builds only, and only with `-uitestFakeMIDI`. Release builds contain none of this.
//
// The simulator has no MIDI hardware, so the coordinator gets a scripted provider holding one virtual
// output ("Fake Synth", an app's endpoint); the panel's buttons plug and unplug "Fake Keys", a device
// with one input and one output and fixed unique numbers, so a replug keeps its IDs. Discovery, the
// coalescing delay and the list are the app's real code.
#if DEBUG
import Foundation
import PerformanceControl
import SwiftUI

enum UITestFakeMIDI {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestFakeMIDI") }

    static let synthID: Int32 = 0x5000_0001
    static let keysInputID: Int32 = 0x5000_0010
    static let keysOutputID: Int32 = 0x5000_0011

    static let provider = ScriptedMIDIEndpointProvider(records: [
        MIDIEndpointRecord(uniqueID: synthID, direction: .destination, displayName: "Fake Synth", isVirtual: true),
    ])

    static let keys: [MIDIEndpointRecord] = [
        MIDIEndpointRecord(uniqueID: keysInputID, direction: .source, displayName: "Fake Keys",
                           endpointName: "Port 1", entityName: "Fake Keys", deviceName: "Fake Keys"),
        MIDIEndpointRecord(uniqueID: keysOutputID, direction: .destination, displayName: "Fake Keys",
                           endpointName: "Port 1", entityName: "Fake Keys", deviceName: "Fake Keys"),
    ]

    /// Discovery over the stand-in when the launch arguments ask for it.
    static func discoveryIfRequested() -> MIDIEndpointDiscovery? {
        isRequested ? MIDIEndpointDiscovery(provider: provider) : nil
    }

    static func plugKeys() {
        let present: Bool = provider.currentEndpoints().contains { (record: MIDIEndpointRecord) -> Bool in record.uniqueID == keysInputID }
        if !present { provider.plug(keys) }
    }

    static func unplugKeys() {
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
