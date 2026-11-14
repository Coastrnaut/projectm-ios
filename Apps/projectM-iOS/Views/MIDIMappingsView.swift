// MIDIMappingsView.swift — the MIDI Mappings screen (MIDI-003-R10, R11; contracts/midi-learn.md L2, L4).
// Opened from the MIDI section in Settings: a status line (with Cancel while learning), one row per learnable
// parameter with its control, Learn and Delete, and a one-step Undo. MIDI-004-R7: under each mapped parameter a
// "Curve" row shows the curve summary and opens `MIDIMappingOptionsView`. Small views so each body stays under CI's
// type-check budget. No animation; announcements come from the coordinator through the shared announcer.
// MIDI-006-R8: a trigger section, one row per trigger target with its note, Learn and Delete. MIDI-008-R7: titled
// "Transport", with Play/Pause, Play and Pause first; a row's source may be a note, a CC button or MIDI Start/Stop.
// MIDI-007-R9: a "Scene triggers" section, one row per scene mapping with Delete, and the "Program number selects
// cue" picker. Scenes are assigned from Settings › Show (Assign MIDI…).
// MIDI-012-R10: a "Profiles" section at the end (`MIDIProfilesSection`); Undo also covers Apply.
import ParameterGraph
import PerformanceControl
import SwiftUI

struct MIDIMappingsView: View {
    var mappings: MIDIMappingCoordinator

    var body: some View {
        List {
            MIDIMappingsStatusSection(mappings: mappings)
            MIDIMappingsRowsSection(mappings: mappings)
            MIDINoteTriggersSection(mappings: mappings)   // MIDI-006-R8
            MIDISceneTriggersSection(mappings: mappings)   // MIDI-007-R9
            if let profiles = mappings.profiles { MIDIProfilesSection(profiles: profiles) }   // MIDI-012-R10 (last: earlier rows keep their places)
        }
        .navigationTitle("MIDI Mappings")
        .midiProfilesPresentation(mappings.profiles)   // MIDI-012
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
                if let summary = row.curveSummary {
                    MIDIMappingCurveRow(mappings: mappings, row: row, summary: summary)
                }
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

/// MIDI-004-R7: "Curve  Ease in, inverted" → the mapping's options screen.
private struct MIDIMappingCurveRow: View {
    var mappings: MIDIMappingCoordinator
    let row: MIDIMappingRow
    let summary: String

    var body: some View {
        NavigationLink {
            MIDIMappingOptionsView(mappings: mappings, parameter: row.parameter, name: row.name)
        } label: {
            LabeledContent("Curve", value: summary)
        }
        .accessibilityLabel(row.name + " curve")
        .accessibilityValue(row.curveUnreadable ? summary + ". " + MIDIMappingCoordinator.unreadableCurveText : summary)
        .accessibilityIdentifier("midiCurve." + row.id)
    }
}

/// MIDI-006-R8 and MIDI-008-R7: Play/Pause, Play, Pause, Next cue, Previous cue, Black out, Black out while held.
private struct MIDINoteTriggersSection: View {
    var mappings: MIDIMappingCoordinator

    var body: some View {
        Section {
            ForEach(mappings.noteRows) { (row: MIDINoteRow) in
                MIDINoteRowView(row: row, canLearn: mappings.canLearn,
                                learn: { () -> Void in mappings.startLearningNote(row.target) },
                                delete: { () -> Void in mappings.deleteNoteMapping(row.target) })
            }
        } header: {
            Text("Transport")
        } footer: {
            Text(MIDIMappingCoordinator.noteFooterText)
        }
    }
}

private struct MIDINoteRowView: View {
    let row: MIDINoteRow
    let canLearn: Bool
    let learn: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            LabeledContent(row.name, value: row.control ?? "Not mapped")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityIdentifier("midiNote." + row.id)
            Button(row.isLearning ? "Learning" : "Learn", action: learn)
                .buttonStyle(.borderless)
                .disabled(!canLearn || row.isLearning)
                .accessibilityLabel("Learn " + row.name)
                .accessibilityIdentifier("midiNoteLearn." + row.id)
            if row.control != nil {
                Button("Delete", role: .destructive, action: delete)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete note mapping for " + row.name)
                    .accessibilityIdentifier("midiNoteDelete." + row.id)
            }
        }
    }
}

/// MIDI-007-R9: the scene mappings and the position mode.
private struct MIDISceneTriggersSection: View {
    var mappings: MIDIMappingCoordinator

    var body: some View {
        Section {
            ForEach(mappings.sceneRows) { (row: MIDISceneRow) in
                MIDISceneRowView(row: row, delete: { () -> Void in mappings.deleteSceneMapping(row.sceneID) })
            }
            MIDIProgramCueModePicker(mappings: mappings)
        } header: {
            Text("Scene triggers")
        } footer: {
            Text(MIDIMappingCoordinator.sceneFooterText)
        }
    }
}

private struct MIDISceneRowView: View {
    let row: MIDISceneRow
    let delete: () -> Void

    var body: some View {
        HStack {
            LabeledContent(row.name, value: row.control)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityIdentifier("midiScene." + row.id)
            Button("Delete", role: .destructive, action: delete)
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete scene mapping for " + row.name)
                .accessibilityIdentifier("midiSceneDelete." + row.id)
        }
    }
}

/// Off, Any channel, Channel 1–16 (tags -2, -1, 0–15).
private struct MIDIProgramCueModePicker: View {
    var mappings: MIDIMappingCoordinator

    private static let channels: [Int] = Array(0...15)

    private var selection: Binding<Int> {
        Binding<Int>(get: { () -> Int in Self.tag(mappings.sceneBindings.programCueMode) },
                     set: { (tag: Int) -> Void in mappings.setProgramCueMode(Self.mode(tag)) })
    }

    static func tag(_ mode: MIDIProgramCueMode) -> Int {
        switch mode {
        case .off: -2
        case .anyChannel: -1
        case let .channel(channel): Int(channel)
        }
    }

    static func mode(_ tag: Int) -> MIDIProgramCueMode {
        if tag == -1 { return .anyChannel }
        guard tag >= 0, tag <= 15 else { return .off }
        return .channel(UInt8(tag))
    }

    var body: some View {
        Picker("Program number selects cue", selection: selection) {
            Text("Off").tag(-2)
            Text("Any channel").tag(-1)
            ForEach(Self.channels, id: \.self) { (channel: Int) in
                Text("Channel " + String(channel + 1)).tag(channel)
            }
        }
        .accessibilityIdentifier("midiProgramCueMode")
    }
}
