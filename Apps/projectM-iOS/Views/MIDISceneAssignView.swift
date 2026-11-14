// MIDISceneAssignView.swift — MIDI-007-R8: the "Assign MIDI…" sheet for one scene, opened from a cue in Settings ›
// Show. It starts learning at once (the next program change or key press maps the scene), shows the scene's current
// control, the shared learn status line, Learn again, Cancel while learning and Remove. Closing it ends learning
// (MIDI-003's screen lifecycle). Announcements come from the coordinator on the `.midi` lane.
import SwiftUI

struct MIDISceneAssignView: View {
    var mappings: MIDIMappingCoordinator
    let sceneID: String
    let sceneName: String
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                MIDISceneAssignStatusSection(mappings: mappings, sceneID: sceneID, sceneName: sceneName)
                #if DEBUG
                if UITestFakeMIDI.isRequested { Section { UITestFakeMIDIInputPanel() } }
                #endif
            }
            .navigationTitle("Assign MIDI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss).accessibilityIdentifier("midiSceneAssignDone")
                }
            }
        }
        .accessibilityIdentifier("midiSceneAssign")
        .onAppear {
            mappings.open()
            mappings.startLearningScene(sceneID)
        }
        .onDisappear { mappings.close() }
    }
}

private struct MIDISceneAssignStatusSection: View {
    var mappings: MIDIMappingCoordinator
    let sceneID: String
    let sceneName: String

    static let idleText: String = "Tap Learn, then send a program change or press a key on your MIDI device."

    private var isLearningThis: Bool { mappings.learningSceneID == sceneID }

    private var status: String {
        if isLearningThis { return mappings.statusText }
        if !mappings.canLearn { return MIDIMappingCoordinator.offText }
        return mappings.lastMessage ?? Self.idleText
    }

    var body: some View {
        Section {
            LabeledContent(sceneName, value: mappings.sceneControl(for: sceneID) ?? "Not mapped")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(sceneName)
                .accessibilityValue(mappings.sceneControl(for: sceneID) ?? "Not mapped")
                .accessibilityIdentifier("midiSceneAssignControl")
            Text(status)
                .accessibilityLabel("MIDI learn status")
                .accessibilityValue(status)
                .accessibilityIdentifier("midiSceneAssignStatus")
            actions
        } footer: {
            Text("Learn waits up to 30 seconds. A program or key selects one scene; assigning it here moves it from any other scene or note trigger.")
        }
    }

    @ViewBuilder private var actions: some View {
        if isLearningThis {
            Button("Cancel") { mappings.cancelLearning() }
                .accessibilityIdentifier("midiSceneAssignCancel")
        } else {
            Button("Learn") { mappings.startLearningScene(sceneID) }
                .disabled(!mappings.canLearn)
                .accessibilityLabel("Learn MIDI for " + sceneName)
                .accessibilityIdentifier("midiSceneAssignLearn")
        }
        if mappings.sceneControl(for: sceneID) != nil {
            Button("Remove", role: .destructive) { mappings.deleteSceneMapping(sceneID) }
                .accessibilityLabel("Remove MIDI from " + sceneName)
                .accessibilityIdentifier("midiSceneAssignRemove")
        }
    }
}
