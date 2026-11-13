// ShowEditorView.swift — Settings → Show (SHOW-001-R14; US2): the cue list with each cue's number,
// label and a "Scene missing" flag; Add Current Scene (a snapshot of the shown look, labelled after
// the visual); drag to reorder; swipe or Edit to delete; Rename…; Go to Cue. Editing never changes the
// output (SHOW-001-R6); Go to Cue shows the cue's scene. A standard List, so Dynamic Type, VoiceOver
// ("Cue 2 of 5, Intro, active") and Full Keyboard Access apply (FR-070).
import ShowControl
import SwiftUI

struct ShowEditorView: View {
    let show: ShowCoordinator
    let addCurrentScene: () -> Void
    @State private var renaming: ShowCue?
    @State private var renameText = ""

    var body: some View {
        List {
            if let message = show.editorMessage {
                Section {
                    Text(message).accessibilityIdentifier("showEditorMessage")
                    Button("OK") { show.dismissEditorMessage() }
                }
            }
            Section {
                Button {
                    addCurrentScene()
                } label: {
                    Label("Add Current Scene", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(show.list.cues.count >= ShowCueList.maximumCues)
                .accessibilityIdentifier("showAddCurrentScene")
            } footer: {
                Text("Adds a cue that keeps the visual and its settings as they are now. Next and Previous in the controls, or the arrow keys, step through the cues.")
            }
            Section(show.list.cues.isEmpty ? "No cues" : "Cues") {
                ForEach(Array(show.list.cues.enumerated()), id: \.element.id) { (index: Int, cue: ShowCue) in
                    row(cue, number: index + 1)
                }
                .onMove { (offsets: IndexSet, destination: Int) in show.move(fromOffsets: offsets, toOffset: destination) }
                .onDelete { (offsets: IndexSet) in
                    for id in offsets.map({ (i: Int) -> UUID in show.list.cues[i].id }) { show.remove(id) }
                }
            }
        }
        .navigationTitle("Show")
        .toolbar { if !show.list.cues.isEmpty { EditButton() } }
        .alert("Rename Cue", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Label", text: $renameText).accessibilityIdentifier("showRenameField")
            Button("Rename") {
                if let cue = renaming { show.rename(cue.id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("1 to \(ShowCueList.maximumLabelLength) characters.")
        }
        .accessibilityIdentifier("showEditor")
    }

    private func row(_ cue: ShowCue, number: Int) -> some View {
        let active = show.list.activeCue?.id == cue.id
        let missing = show.isSceneMissing(cue)
        return HStack {
            Text("\(number)").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(cue.label)
                if missing {
                    Label("Scene missing", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if active { Image(systemName: "play.fill").foregroundStyle(.tint).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cue.label)
        .accessibilityValue("Cue \(number) of \(show.list.cues.count)" + (active ? ", active" : "") + (missing ? ", scene missing" : ""))
        .accessibilityIdentifier("showCue\(number)")
        .contextMenu {
            Button("Go to Cue") { show.go(to: cue.id) }
            Button("Rename…") { renameText = cue.label; renaming = cue }
            Button("Delete", role: .destructive) { show.remove(cue.id) }
        }
        .swipeActions(edge: .leading) {
            Button("Go") { show.go(to: cue.id) }.tint(.accentColor)
        }
        .accessibilityAction(named: "Go to Cue") { show.go(to: cue.id) }
        .accessibilityAction(named: "Rename") { renameText = cue.label; renaming = cue }
    }
}
