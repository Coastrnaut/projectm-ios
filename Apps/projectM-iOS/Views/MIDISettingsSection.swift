// MIDISettingsSection.swift — the MIDI section of Settings (MIDI-001-R8, R9; contracts/midi-discovery.md C4).
// A small view of its own so SettingsView's body stays small (CI's Xcode 26 type-check budget).
// No animation; Dynamic Type and VoiceOver come from the standard List section.
import PerformanceControl
import SwiftUI

struct MIDISettingsSection: View {
    var midi: MIDIDiscoveryCoordinator

    var body: some View {
        Section {
            Toggle("Listen for MIDI devices", isOn: Binding(get: { midi.isEnabled }, set: { midi.setEnabled($0) }))
                .accessibilityIdentifier("midiListenToggle")
            Text(midi.statusText)
                .foregroundStyle(.secondary)
                .accessibilityLabel("MIDI status")
                .accessibilityValue(midi.statusText)
                .accessibilityIdentifier("midiStatus")
            #if DEBUG
            if UITestFakeMIDI.isRequested { UITestFakeMIDIPanel(rows: midi.rows) }   // above the rows: it never moves
            #endif
            ForEach(midi.rows) { (row: MIDIEndpointRow) in
                MIDIEndpointRowView(row: row)
            }
        } header: {
            Text("MIDI")
        } footer: {
            Text("Shows MIDI devices connected to this device and MIDI apps running on it. projectM only looks while this is on and the app is open, never uses the network, and keeps no device names.")
        }
    }
}

private struct MIDIEndpointRowView: View {
    let row: MIDIEndpointRow

    var body: some View {
        LabeledContent(row.title, value: row.detail)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityIdentifier("midiEndpoint." + row.id)
    }
}
