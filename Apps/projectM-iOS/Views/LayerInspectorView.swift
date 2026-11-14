// LayerInspectorView.swift — Settings › Layers (CMP-015-R1, R3, R8, R10; contracts/layer-inspector.md
// L1, L4).
//
// * The current scene's layers top first (`layerRow.<instance>`), each opening its detail; drawn layers
//   have Solo and Mute (transient, never saved or undoable; announced through the shared announcer by
//   LayerInspectorCoordinator). Groups (none in live scenes today) are listed read-only.
// * Undo and Redo in the navigation bar (SCN-010). At accessibility text sizes the buttons move under
//   the layer's name.
// Bodies stay small (Xcode 26 type-check budget).
import SwiftUI

struct LayerInspectorView: View {
    let layers: LayerInspectorCoordinator
    let history: SceneHistoryCoordinator
    /// The current scene's rows, top first (AppCoordinator.layerInspectorRows; read at each update).
    let rows: @MainActor () -> [LayerInspectorRow]
    let groups: @MainActor () -> [LayerInspectorGroupRow]

    var body: some View {
        List {
            layersSection(rows())
            groupsSection(groups())
        }
        .navigationTitle("Layers")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SceneUndoRedoButtons(history: history) } }
        .accessibilityIdentifier("layerInspector")
    }

    private func layersSection(_ rows: [LayerInspectorRow]) -> some View {
        Section {
            if rows.isEmpty {
                Text("This visual has no layers.").accessibilityIdentifier("layerInspectorEmpty")
            } else {
                ForEach(rows) { (row: LayerInspectorRow) in
                    LayerInspectorRowView(row: row, layers: layers, history: history)
                }
            }
        } header: {
            Text("Top to bottom")
        } footer: {
            Text("Choose a layer to see and change its settings. Solo and Mute help you check layers; they are never saved.")
        }
    }

    @ViewBuilder private func groupsSection(_ groups: [LayerInspectorGroupRow]) -> some View {
        if !groups.isEmpty { groupsList(groups) }
    }

    private func groupsList(_ groups: [LayerInspectorGroupRow]) -> some View {
        Section("Groups") {
            ForEach(groups) { (group: LayerInspectorGroupRow) in
                LabeledContent(group.name, value: Self.groupSummary(group))
                    .accessibilityIdentifier("layerGroup.\(group.id)")
            }
        }
    }

    static func groupSummary(_ group: LayerInspectorGroupRow) -> String {
        let state: String = group.isEnabled ? "On" : "Off"
        let opacity: String = String(format: "%.0f%%", group.opacity * 100)
        return "\(state), \(opacity), \(group.memberCount) layers"
    }
}

struct LayerInspectorRowView: View {
    let row: LayerInspectorRow
    let layers: LayerInspectorCoordinator
    let history: SceneHistoryCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                link
                if row.isEditable { buttons }
            }
        } else {
            HStack(spacing: 12) {
                link
                if row.isEditable { buttons }
            }
        }
    }

    private var link: some View {
        NavigationLink {
            LayerDetailView(row: row, layers: layers, history: history)
        } label: {
            label
        }
        .accessibilityLabel(row.title)
        .accessibilityValue(row.accessibilityValue)
        .accessibilityIdentifier("layerRow.\(row.instance)")
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            Text(row.isEditable ? "Layer \(row.position)" : "Layer \(row.position), read only")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            soloButton
            muteButton
        }
    }

    private var soloButton: some View {
        let on: Bool = layers.isSoloed(row.kind)
        return Button { layers.toggleSolo(kind: row.kind, title: row.title) } label: {
            Image(systemName: on ? "s.circle.fill" : "s.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Solo \(row.title)")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityIdentifier("layerSolo.\(row.instance)")
    }

    private var muteButton: some View {
        let on: Bool = layers.isMuted(row.kind)
        return Button { layers.toggleMute(kind: row.kind, title: row.title) } label: {
            Image(systemName: on ? "speaker.slash.fill" : "speaker.slash")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Mute \(row.title)")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityIdentifier("layerMute.\(row.instance)")
    }
}
