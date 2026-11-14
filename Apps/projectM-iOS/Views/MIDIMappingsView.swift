// MIDIMappingsView.swift — the MIDI Mappings screen (MIDI-003-R10, R11; contracts/midi-learn.md L2, L4).
// Opened from the MIDI section in Settings: a status line (with Cancel while learning), one row per learnable
// parameter with its control, Learn and Delete, and a one-step Undo. Small views so each body stays under CI's
// type-check budget. No animation; announcements come from the coordinator through the shared announcer.
import ParameterGraph
import PerformanceControl
import SwiftUI

struct MIDIMappingsView: View {
    var mappings: MIDIMappingCoordinator

    var body: some View {
        List {
            MIDIMappingsStatusSection(mappings: mappings)
            MIDIMappingsRowsSection(mappings: mappings)
        }
        .navigationTitle("MIDI Mappings")
        .toolbar { MIDIMappingsToolbar(mappings: mappings) }
        .onAppear { mappings.open() }
        .onDisappear { mappings.close() }
    }
}

private struct MIDIMappingsToolbar: ToolbarContent {
    var mappings: MIDIMappingCoordinator

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Undo") { mappings.undo() }
                .disabled(!mappings.canUndo)
                .accessibilityIdentifier("midiMappingsUndo")
        }
    }
}

private struct MIDIMappingsStatusSection: View {
    var mappings: MIDIMappingCoordinator

    var body: some View {
        Section {
            Text(mappings.statusText)
                .accessibilityLabel("MIDI learn status")
                .accessibilityValue(mappings.statusText)
                .accessibilityIdentifier("midiMappingsStatus")
            if mappings.isLearning {
                Button("Cancel") { mappings.cancelLearning() }
                    .accessibilityIdentifier("midiMappingsCancel")
            }
            #if DEBUG
            if UITestFakeMIDI.isRequested { UITestFakeMIDIInputPanel() }
            #endif
        } footer: {
            Text("Learn waits up to 30 seconds for a knob or fader (a control change). A control drives one setting. Mappings name only the channel and controller number, never the device.")
        }
    }
}

private struct MIDIMappingsRowsSection: View {
    var mappings: MIDIMappingCoordinator

    var body: some View {
        Section("Mappings") {
            ForEach(mappings.rows) { (row: MIDIMappingRow) in
                MIDIMappingRowView(row: row, canLearn: mappings.canLearn,
                                   learn: { () -> Void in mappings.startLearning(row.parameter) },
                                   delete: { () -> Void in mappings.deleteMapping(row.parameter) })
            }
        }
    }
}

private struct MIDIMappingRowView: View {
    let row: MIDIMappingRow
    let canLearn: Bool
    let learn: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            LabeledContent(row.name, value: row.control ?? "Not mapped")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityIdentifier("midiMapping." + row.id)
            Button(row.isLearning ? "Learning" : "Learn", action: learn)
                .buttonStyle(.borderless)
                .disabled(!canLearn || row.isLearning)
                .accessibilityLabel("Learn " + row.name)
                .accessibilityIdentifier("midiLearn." + row.id)
            if row.control != nil {
                Button("Delete", role: .destructive, action: delete)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete mapping for " + row.name)
                    .accessibilityIdentifier("midiDelete." + row.id)
            }
        }
    }
}
