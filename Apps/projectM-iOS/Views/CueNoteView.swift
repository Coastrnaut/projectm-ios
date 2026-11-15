// CueNoteView.swift — Settings → Show → a cue's Note sheet (SHOW-012-R5; spec Clarifications).
//
// A private operator note: a TextEditor, an "n / 500" counter (the warning colour and Save disabled over the limit; nothing
// is cut while typing), Cancel, Save and, on a cue that has a note, Remove Note. Save goes through
// `ShowCoordinator.setOperatorNote` (refused while the scene is locked; applies nothing). The note is operator-only: this
// view lives in the device's Settings and is never shown on an external display, a recording or the HUD (SHOW-012-R9).
import ShowControl
import SwiftUI

struct CueNoteView: View {
    let show: ShowCoordinator
    let cueID: UUID
    let dismiss: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(show: ShowCoordinator, cueID: UUID, dismiss: @escaping () -> Void) {
        self.show = show
        self.cueID = cueID
        self.dismiss = dismiss
        let stored: String? = show.list.cues.first { (c: ShowCue) -> Bool in c.id == cueID }?.operatorNote
        _text = State(initialValue: stored ?? "")
    }

    private var cue: ShowCue? { show.list.cues.first { (c: ShowCue) -> Bool in c.id == cueID } }
    private var count: Int { ShowCueNote.cleaned(text).count }
    private var tooLong: Bool { count > ShowCueNote.maximumCharacters }

    var body: some View {
        NavigationStack {
            Form {
                editorSection
                if cue?.operatorNote != nil { removeSection }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .onAppear { focused = true }
        }
        .accessibilityIdentifier("cueNoteSheet")
    }

    private var editorSection: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 140)
                .focused($focused)
                .accessibilityLabel("Note")
                .accessibilityIdentifier("cueNoteEditor")
        } header: {
            Text(cue?.label ?? "Cue")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                counter
                Text("Only you see this note, here in Settings. It is never shown on an external display, in recordings or in the HUD.")
            }
        }
    }

    private var counter: some View {
        let shown: String = "\(count) / \(ShowCueNote.maximumCharacters)"
        let spoken: String = "\(count) of \(ShowCueNote.maximumCharacters) characters"
        return Text(shown)
            .monospacedDigit()
            .foregroundStyle(tooLong ? Color.red : Color.secondary)
            .accessibilityLabel(tooLong ? spoken + ", too long" : spoken)
            .accessibilityIdentifier("cueNoteCount")
    }

    private var removeSection: some View {
        Section {
            Button("Remove Note", role: .destructive) {
                if show.setOperatorNote(cueID, to: nil) { dismiss() }
            }
            .accessibilityIdentifier("cueNoteRemove")
        }
    }

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.accessibilityIdentifier("cueNoteCancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                if show.setOperatorNote(cueID, to: text) { dismiss() }
            }
            .disabled(tooLong)
            .accessibilityIdentifier("cueNoteSave")
        }
    }
}
