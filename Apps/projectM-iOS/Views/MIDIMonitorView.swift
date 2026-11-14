// MIDIMonitorView.swift — the MIDI Monitor screen (MIDI-002-R6, R9, R10, R15; contracts/midi-input.md C4).
// Opened from the MIDI section in Settings; receiving runs only while this screen is shown (open on appear,
// close on disappear). Small views so each body stays under CI's type-check budget. No animation, no
// announcements for live traffic: each row has one combined VoiceOver label.
import PerformanceControl
import SwiftUI

struct MIDIMonitorView: View {
    var monitor: MIDIMonitorCoordinator

    var body: some View {
        List {
            MIDIMonitorStatusSection(monitor: monitor)
            MIDIMonitorEntriesSection(entries: monitor.entries)
        }
        .navigationTitle("MIDI Monitor")
        .toolbar { MIDIMonitorToolbar(monitor: monitor) }
        .onAppear { monitor.open() }
        .onDisappear { monitor.close() }
    }
}

private struct MIDIMonitorToolbar: ToolbarContent {
    var monitor: MIDIMonitorCoordinator

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(monitor.isPaused ? "Resume" : "Pause") { monitor.togglePause() }
                .accessibilityIdentifier("midiMonitorPause")
            Button("Clear") { monitor.clear() }
                .accessibilityIdentifier("midiMonitorClear")
        }
    }
}

private struct MIDIMonitorStatusSection: View {
    var monitor: MIDIMonitorCoordinator

    var body: some View {
        Section {
            Text(monitor.statusText)
                .accessibilityLabel("MIDI monitor status")
                .accessibilityValue(monitor.statusText)
                .accessibilityIdentifier("midiMonitorStatus")
            Text(monitor.summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("midiMonitorSummary")
            #if DEBUG
            if UITestFakeMIDI.isRequested { UITestFakeMIDIInputPanel() }
            #endif
        } footer: {
            Text("Shows the newest 64 messages while this screen is open. Nothing is saved, and devices are not identified.")
        }
    }
}

private struct MIDIMonitorEntriesSection: View {
    let entries: [MIDIMonitorEntry]

    var body: some View {
        Section("Messages") {
            ForEach(entries) { (entry: MIDIMonitorEntry) in
                MIDIMonitorRow(entry: entry)
            }
        }
    }
}

private struct MIDIMonitorRow: View {
    let entry: MIDIMonitorEntry

    private var detail: String {
        let parts: [String] = [entry.text.channel, entry.text.number, entry.text.value].filter { (part: String) -> Bool in
            !part.isEmpty
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text(entry.text.type)
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.time)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
        .accessibilityIdentifier("midiMonitorEntry." + String(entry.id))
    }
}
