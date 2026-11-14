// SceneHistoryControls.swift — Undo and Redo for scene edits (SCN-010-R10; research SCN-010-D7).
//
// * `SceneUndoRedoButtons`: Settings' navigation bar. Each button names its step for VoiceOver
//   ("Undo Bars 16"), is disabled when there is nothing to undo or redo, and answers ⌘Z / ⇧⌘Z.
// * `SceneHistoryKeyCommands`: hidden ⌘Z / ⇧⌘Z on the visualizer while Settings is closed (like the
//   show's cue keys); they do not show the controls.
// * No shake to undo: the history does not use the system undo manager.
import SwiftUI

struct SceneUndoRedoButtons: View {
    let history: SceneHistoryCoordinator

    var body: some View {
        HStack(spacing: 4) {
            Button { history.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!history.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel(history.undoAccessibilityLabel)
                .accessibilityIdentifier("sceneUndo")
                .accessibilityShowsLargeContentViewer()   // ACC-006: a fixed-size bar glyph at AX sizes
            Button { history.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!history.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel(history.redoAccessibilityLabel)
                .accessibilityIdentifier("sceneRedo")
                .accessibilityShowsLargeContentViewer()
        }
    }
}

struct SceneHistoryKeyCommands: View {
    let coordinator: AppCoordinator

    var body: some View {
        ZStack {
            Button("") { coordinator.undoSceneEdit() }.keyboardShortcut("z", modifiers: .command)
            Button("") { coordinator.redoSceneEdit() }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
