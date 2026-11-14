// ShowEditorView.swift — Settings → Show (SHOW-001-R14; US2): the cue list with each cue's number,
// label and a "Scene missing" flag; Add Current Scene (a snapshot of the shown look, labelled after
// the visual); drag to reorder; swipe or Edit to delete; Rename…; Go to Cue. Editing never changes the
// output (SHOW-001-R6); Go to Cue shows the cue's scene. A standard List, so Dynamic Type, VoiceOver
// ("Cue 2 of 5, Intro, active") and Full Keyboard Access apply (FR-070).
// SCN-003: Duplicate Scene and Rename Scene… per cue (context menu and VoiceOver actions); a row whose
// scene name differs from its label shows "Scene: <name>" and VoiceOver reads ", scene <name>".
// MIDI-007-R8: Assign MIDI… per cue (context menu, a leading "MIDI" swipe action, VoiceOver action) opens
// `MIDISceneAssignView` for the cue's scene when the app passes the MIDI mappings.
// SCN-007-R9: Transition… per cue (context menu, a leading "Transition" swipe action, VoiceOver action) opens
// `CueTransitionView`; a cue with a transition shows "Transition: Crossfade 1.5 s, Ease Out" under its label
// and VoiceOver reads ", transition Crossfade 1.5 seconds, Ease Out".
// SCN-011-R7: Add from Template… opens `SceneTemplateGalleryView` (bundled starter scenes added as copies).
import SceneFormat
import ShowControl
import ShowStorage
import SwiftUI

struct ShowEditorView: View {
    let show: ShowCoordinator
    let addCurrentScene: () -> Void
    /// MIDI-007: the MIDI mappings (nil hides Assign MIDI…, e.g. in previews).
    var midiMappings: MIDIMappingCoordinator? = nil
    @State private var renaming: ShowCue?
    @State private var renameText = ""
    @State private var renamingScene: ShowCue?
    @State private var sceneNameText = ""
    @State private var assigningMIDI: ShowCue?
    @State private var editingTransition: ShowCue?
    /// SCN-011: the template gallery (catalog read when it opens).
    @State private var templateCatalog: SceneTemplateCatalog?

    /// SCN-015: the scene is locked (edits hidden or disabled; Go to Cue and Assign MIDI stay).
    private var locked: Bool { show.isEditLocked }

    var body: some View {
        cueList
        .navigationTitle("Show")
        .toolbar { if !show.list.cues.isEmpty && !locked { EditButton() } }   // SCN-015-R6
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
        .alert("Rename Scene", isPresented: Binding(get: { renamingScene != nil }, set: { if !$0 { renamingScene = nil } })) {
            TextField("Scene name", text: $sceneNameText).accessibilityIdentifier("showSceneNameField")
            Button("Rename") {
                if let cue = renamingScene { show.renameScene(of: cue.id, to: sceneNameText) }
                renamingScene = nil
            }
            Button("Cancel", role: .cancel) { renamingScene = nil }
        } message: {
            Text("Every cue that shows this scene uses the new name. 1 to \(SceneLimits.maximumNameLength) characters.")
        }
        .sheet(isPresented: Binding(get: { assigningMIDI != nil }, set: { if !$0 { assigningMIDI = nil } })) {
            assignSheet
        }
        .sheet(isPresented: Binding(get: { editingTransition != nil }, set: { if !$0 { editingTransition = nil } })) {
            transitionSheet
        }
        .sheet(isPresented: Binding(get: { templateCatalog != nil }, set: { if !$0 { templateCatalog = nil } })) {
            templateSheet
        }
        .accessibilityIdentifier("showEditor")
    }

    /// The editor's list (its own property since SCN-011, 2026-11-14: with the template sheet `body` took 316 ms to
    /// type-check, past the 300 ms budget).
    private var cueList: some View {
        List {
            if let message = show.editorMessage {
                Section {
                    Text(message).accessibilityIdentifier("showEditorMessage")
                    Button("OK") { show.dismissEditorMessage() }
                }
            }
            if locked { Section { SceneLockNote() } }   // SCN-015-R6
            Section {
                Button {
                    addCurrentScene()
                } label: {
                    // ACC-006-R1: icon and title side by side, the title wrapping in its own column. A Label
                    // in a list row wraps its title under the icon at AX5, which the audit reports as clipped
                    // text (2026-11-13). The icon is decorative; the button reads "Add Current Scene".
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "plus.rectangle.on.rectangle").accessibilityHidden(true)
                        Text("Add Current Scene").fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(show.list.cues.count >= ShowCueList.maximumCues || locked)
                .accessibilityIdentifier("showAddCurrentScene")
                addFromTemplateButton   // SCN-011
                if !show.list.cues.isEmpty { sceneFoldersLink }   // SCN-004
            } footer: {
                Text("Adds a cue that keeps the visual and its settings as they are now. Next and Previous in the controls, or the arrow keys, step through the cues.")
            }
            Section(show.list.cues.isEmpty ? "No cues" : "Cues") {
                ForEach(Array(show.list.cues.enumerated()), id: \.element.id) { (index: Int, cue: ShowCue) in
                    row(cue, number: index + 1)
                        .deleteDisabled(locked)   // SCN-015-R6: no swipe-to-delete
                        .moveDisabled(locked)     // and no drag reorder
                }
                .onMove { (offsets: IndexSet, destination: Int) in show.move(fromOffsets: offsets, toOffset: destination) }
                .onDelete { (offsets: IndexSet) in
                    for id in offsets.map({ (i: Int) -> UUID in show.list.cues[i].id }) { show.remove(id) }
                }
            }
        }
    }

    /// MIDI-007-R8: the Assign MIDI sheet for the chosen cue's scene.
    @ViewBuilder private var assignSheet: some View {
        if let cue = assigningMIDI, let midiMappings {
            MIDISceneAssignView(mappings: midiMappings, sceneID: cue.sceneID, sceneName: show.sceneName(of: cue) ?? cue.label,
                                dismiss: { () -> Void in assigningMIDI = nil })
        }
    }

    /// SCN-007: the Transition sheet for the chosen cue.
    @ViewBuilder private var transitionSheet: some View {
        if let cue = editingTransition {
            CueTransitionView(show: show, cueID: cue.id, dismiss: { () -> Void in editingTransition = nil })
        }
    }

    /// SCN-011-R7: Add from Template… opens the gallery of bundled starter scenes (disabled when the show is full).
    private var addFromTemplateButton: some View {
        Button {
            templateCatalog = ShowCoordinator.bundledTemplates()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "square.grid.2x2").accessibilityHidden(true)
                Text("Add from Template…").fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(show.list.cues.count >= ShowCueList.maximumCues || locked)
        .accessibilityIdentifier("showAddFromTemplate")
    }

    /// SCN-011: the template gallery sheet.
    @ViewBuilder private var templateSheet: some View {
        if let catalog = templateCatalog {
            SceneTemplateGalleryView(show: show, catalog: catalog, dismiss: { () -> Void in templateCatalog = nil })
        }
    }

    /// SCN-004: the show's scenes organized in logical folders. ACC-006-R1 (testShowEditorAX3, 2026-11-14):
    /// as its own section below the footer, the row sat at the bottom edge of the screen at AX3, and its
    /// `Label` wrapped the title under the icon; the audit reported clipped text and partly unsupported
    /// Dynamic Type. Now an icon-and-title row (the title wraps in its own column, as Add Current Scene's)
    /// in the first section, next to Add Current Scene. The link reads "Scene Folders".
    private var sceneFoldersLink: some View {
        NavigationLink {
            SceneFoldersView(show: show, folderID: nil)
        } label: {
            IconTitleRow(title: "Scene Folders", systemImage: "folder")
        }
        .accessibilityIdentifier("showSceneFoldersLink")
    }

    // Split into short parts (2026-11-14): as one function this row took 4.4 s to type-check on
    // Xcode 27 (-warn-long-function-bodies), past Xcode 26's limit on CI.
    private func row(_ cue: ShowCue, number: Int) -> some View {
        let active: Bool = show.list.activeCue?.id == cue.id
        let missing: Bool = show.isSceneMissing(cue)
        let sceneName: String? = show.sceneName(of: cue).flatMap { (name: String) -> String? in name == cue.label ? nil : name }
        let content: AnyView = AnyView(rowContent(cue, number: number, active: active, missing: missing, sceneName: sceneName))
        let labelled: AnyView = AnyView(rowAccessibility(content, cue: cue, number: number, active: active, missing: missing,
                                                         sceneName: sceneName))
        let withMenus: AnyView = AnyView(rowMenus(labelled, cue: cue, missing: missing))
        return rowActions(withMenus, cue: cue, number: number)
    }

    private func rowContent(_ cue: ShowCue, number: Int, active: Bool, missing: Bool, sceneName: String?) -> some View {
        HStack {
            Text("\(number)").monospacedDigit().frame(minWidth: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(cue.label)
                if let sceneName {
                    Text("Scene: \(sceneName)").font(.caption)
                }
                if let transition = CueTransitionResolver.summary(cue.transition) {   // SCN-007
                    Text("Transition: \(transition)").font(.caption).foregroundStyle(.secondary)
                }
                if missing {
                    Label("Scene missing", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if active { Image(systemName: "play.fill").foregroundStyle(.tint).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
    }

    private func rowAccessibility(_ content: AnyView, cue: ShowCue, number: Int, active: Bool, missing: Bool,
                                  sceneName: String?) -> some View {
        // Built in typed steps: as one `+` chain of literals and ternaries, Xcode 26 gave up type-checking it (CI, 607c2c2).
        var value: String = "Cue \(number) of \(show.list.cues.count)"
        if active { value += ", active" }
        if missing { value += ", scene missing" }
        if let sceneName { value += ", scene \(sceneName)" }
        if let transition = CueTransitionResolver.summary(cue.transition) {   // SCN-007
            let spoken: String = transition.replacingOccurrences(of: " s,", with: " seconds,")
            value += ", transition \(spoken)"
        }
        let selectedTraits: AccessibilityTraits = active ? .isSelected : []
        return content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cue.label)
            .accessibilityValue(value)
            .accessibilityAddTraits(selectedTraits)   // ACC-004-R2
            .accessibilityIdentifier("showCue\(number)")
    }

    private func rowMenus(_ content: AnyView, cue: ShowCue, missing: Bool) -> some View {
        let full: Bool = show.list.cues.count >= ShowCueList.maximumCues
        return content
            .contextMenu {
                Button("Go to Cue") { show.go(to: cue.id) }
                if !locked { editMenuItems(cue, missing: missing, full: full) }   // SCN-015-R6
                if midiMappings != nil { Button("Assign MIDI…") { assigningMIDI = cue } }   // MIDI-007-R8
            }
            .swipeActions(edge: .leading) {
                Button("Go") { show.go(to: cue.id) }.tint(.accentColor)
                if !locked { editSwipeActions(cue, missing: missing, full: full) }   // SCN-015-R6
                if midiMappings != nil {   // MIDI-007-R8
                    Button("MIDI") { assigningMIDI = cue }
                        .tint(.teal)
                        .accessibilityLabel("Assign MIDI")
                        .accessibilityIdentifier("showAssignMIDI")
                }
            }
    }

    @ViewBuilder private func editMenuItems(_ cue: ShowCue, missing: Bool, full: Bool) -> some View {
        Button("Rename…") { renameText = cue.label; renaming = cue }
        Button("Duplicate Scene") { show.duplicateScene(of: cue.id) }
            .disabled(missing || full)
        Button("Rename Scene…") { startSceneRename(cue) }.disabled(missing)
        Button("Transition…") { editingTransition = cue }   // SCN-007
        Button("Delete", role: .destructive) { show.remove(cue.id) }
    }

    @ViewBuilder private func editSwipeActions(_ cue: ShowCue, missing: Bool, full: Bool) -> some View {
        // SCN-003: also here (the context menu's live blur over the visualizer is slow to settle).
        if !missing {
            Button("Duplicate") { show.duplicateScene(of: cue.id) }
                .tint(.indigo)
                .disabled(full)
                .accessibilityLabel("Duplicate Scene")
                .accessibilityIdentifier("showDuplicateScene")
            Button("Name") { startSceneRename(cue) }
                .tint(.gray)
                .accessibilityLabel("Rename Scene")
                .accessibilityIdentifier("showRenameScene")
        }
        Button("Transition") { editingTransition = cue }   // SCN-007
            .tint(.orange)
            .accessibilityIdentifier("showCueTransition")
    }

    private func rowActions(_ content: AnyView, cue: ShowCue, number: Int) -> some View {
        content
            .accessibilityAction(named: "Go to Cue") { show.go(to: cue.id) }
            .accessibilityAction(named: "Assign MIDI") { if midiMappings != nil { assigningMIDI = cue } }   // MIDI-007-R8
            .accessibilityActions { if !locked { editAccessibilityActions(cue, number: number) } }   // SCN-015-R6
    }

    @ViewBuilder private func editAccessibilityActions(_ cue: ShowCue, number: Int) -> some View {
        Button("Rename") { renameText = cue.label; renaming = cue }
        Button("Duplicate Scene") { show.duplicateScene(of: cue.id) }
        Button("Rename Scene") { startSceneRename(cue) }
        Button("Transition") { editingTransition = cue }   // SCN-007
        // ACC-004-R3: reordering without Edit mode's drag handles.
        Button("Move Up") { move(number - 1, by: -1) }
        Button("Move Down") { move(number - 1, by: 1) }
    }

    /// Moves the cue at `index` one place up (-1) or down (+1); nothing at either end.
    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard target >= 0, target < show.list.cues.count else { return }
        show.move(fromOffsets: IndexSet(integer: index), toOffset: delta > 0 ? target + 1 : target)
    }

    private func startSceneRename(_ cue: ShowCue) {
        sceneNameText = show.sceneName(of: cue) ?? cue.label
        renamingScene = cue
    }
}
