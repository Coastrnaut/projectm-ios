// PresetBrowserView.swift — the preset browser sheet (task T090; FR-043, FR-044, FR-088, FR-070).
// Alphabetical list with a star per preset, a favorites filter with FR-088's empty-state text, and
// it closes when a preset is chosen.
import Rendering
import SwiftUI

struct PresetBrowserView: View {
    @Bindable var presets: PresetCoordinator
    let onChoose: (Preset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $presets.favoritesOnly) {
                    Text("All").tag(false)
                    Text("Favorites").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("favoritesFilter")
                if let empty = presets.emptyStateText {
                    Text(empty)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("favoritesEmpty")
                }
                ForEach(presets.browserItems) { preset in
                    row(preset)
                }
            }
            .navigationTitle("Presets")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("presetBrowser")
    }

    private func row(_ preset: Preset) -> some View {
        let favorite = presets.isFavorite(preset)
        return HStack {
            Button {
                onChoose(preset)
                dismiss()
            } label: {
                HStack {
                    Text(preset.name).foregroundStyle(.primary)
                    Spacer()
                    if preset == presets.current {
                        Image(systemName: "checkmark").accessibilityLabel("Current preset")
                    }
                }
            }
            .accessibilityIdentifier("preset:\(preset.name)")
            Button {
                presets.toggleFavorite(preset)
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityIdentifier("star:\(preset.name)")
        }
    }
}
