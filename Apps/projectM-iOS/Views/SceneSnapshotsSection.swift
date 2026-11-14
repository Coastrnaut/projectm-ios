// SceneSnapshotsSection.swift — Settings › Snapshots (roadmap SCN-008, specs/169-scn-008-scene-snapshots; R9):
// Save Snapshot, then one row per snapshot of the current scene with a Recall button; Rename and Delete by
// swipe and context menu; VoiceOver actions Recall, Rename, Delete. Delete asks first. The last action's
// message shows under the list (the coordinator also announces it on the library lane). DEBUG builds show the
// media-load probe that SceneSnapshotUITests reads.
import SwiftUI

struct SceneSnapshotsSection: View {
    let snapshots: SceneSnapshotCoordinator
    @State private var renaming: SceneSnapshotRow?
    @State private var newName = ""
    @State private var deleting: SceneSnapshotRow?

    var body: some View {
        Section {
            saveButton
            ForEach(snapshots.rows) { (row: SceneSnapshotRow) in
                SceneSnapshotRowView(row: row, recall: { () -> Void in snapshots.recall(at: row.index) },
                                     rename: { () -> Void in startRename(row) }, delete: { () -> Void in deleting = row })
            }
        } header: {
            Text("Snapshots")
        } footer: {
            footer
        }
        .onAppear { snapshots.reload() }
        .alert("Rename Snapshot", isPresented: renameShown) {
            TextField("Name", text: $newName)
                .accessibilityIdentifier("snapshotNameField")
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { finishRename() }
        }
        .confirmationDialog(deleteTitle, isPresented: deleteShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { finishDelete() }
                .accessibilityIdentifier("snapshotDeleteConfirm")
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }

    private var saveButton: some View {
        Button("Save Snapshot") { snapshots.save() }
            .disabled(!snapshots.canSave)
            .accessibilityIdentifier("snapshotSave")
            .accessibilityHint("Saves the glow and spectrum values in the current scene.")
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A snapshot keeps the glow and spectrum values of the current scene. Recall sets them again without changing the visual, the preset or any photo, video or logo. Up to 16 per scene.")
            if let status = snapshots.status {
                Text(status).accessibilityIdentifier("snapshotStatus")
            }
            #if DEBUG
            Text(MediaLoadSpy.shared.summary + " | " + (snapshots.status ?? ""))
                .font(.caption2)
                .accessibilityIdentifier("snapshotMediaProbe")
            #endif
        }
    }

    private var renameShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in renaming != nil }, set: { (shown: Bool) -> Void in if !shown { renaming = nil } })
    }

    private var deleteShown: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in deleting != nil }, set: { (shown: Bool) -> Void in if !shown { deleting = nil } })
    }

    private var deleteTitle: String { "Delete \"\(deleting?.name ?? "")\"?" }

    private func startRename(_ row: SceneSnapshotRow) {
        newName = row.name
        renaming = row
    }

    private func finishRename() {
        if let row = renaming { snapshots.rename(at: row.index, to: newName) }
        renaming = nil
    }

    private func finishDelete() {
        if let row = deleting { snapshots.delete(at: row.index) }
        deleting = nil
    }
}

/// One snapshot: name, value count and Recall; Rename and Delete by swipe, context menu and VoiceOver actions.
private struct SceneSnapshotRowView: View {
    let row: SceneSnapshotRow
    let recall: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text(row.summary).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.name + ", " + row.summary)
            .accessibilityIdentifier("snapshotRow.\(row.index)")
            .accessibilityAction(named: "Recall") { if row.isUsable { recall() } }
            .accessibilityAction(named: "Rename", rename)
            .accessibilityAction(named: "Delete", delete)
            Spacer(minLength: 8)
            Button("Recall", action: recall)
                .buttonStyle(.bordered)
                .accessibilityLabel("Recall " + row.name)
                .disabled(!row.isUsable)
                .accessibilityIdentifier("snapshotRecall.\(row.index)")
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive, action: delete)
            Button("Rename", action: rename)
        }
        .contextMenu {
            Button("Recall", action: recall).disabled(!row.isUsable)
            Button("Rename…", action: rename)
            Button("Delete…", role: .destructive, action: delete)
        }
    }
}
