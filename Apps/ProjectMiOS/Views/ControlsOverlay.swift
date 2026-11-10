// ControlsOverlay.swift — the visualizer controls (task T085; FR-082, FR-087, FR-070).
//
// FR-082 contents: the source-and-state indicator, Stop, Pause/Resume, Previous, Next, Random, the
// preset browser, the current preset name, and Settings. Regular width uses two rows; compact width
// (iPhone portrait, the smallest iPad split view) uses one row of icon buttons with the preset name
// above it, and the preset browser opens as a sheet in both. Every control has an accessibility
// label equal to its meaning (FR-070).
import SwiftUI

struct ControlsOverlay: View {
    let coordinator: AppCoordinator
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // A real container, not a Group: a Group would pass the identifiers below to every button.
        VStack {
            if sizeClass == .compact {
                compact
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("controlsCompact")
            } else {
                regular
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("controlsRegular")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("controls")
    }

    private var presetName: some View {
        Text(coordinator.presets.current?.name ?? "No preset")
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityIdentifier("currentPreset")
    }

    /// One row of icon buttons (FR-087).
    private var compact: some View {
        VStack(spacing: 8) {
            HStack {
                SourceIndicator(coordinator: coordinator)
                Spacer(minLength: 0)
            }
            presetName.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(buttons, id: \.id) { item in
                    Button(action: item.action) {
                        Image(systemName: item.icon).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .accessibilityLabel(item.title)
                    .accessibilityIdentifier(item.id)
                }
            }
            .font(.title3)
        }
    }

    private var regular: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SourceIndicator(coordinator: coordinator)
                Spacer()
                presetName
            }
            HStack(spacing: 10) {
                ForEach(buttons, id: \.id) { item in
                    Button(action: item.action) {
                        Label(item.title, systemImage: item.icon)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(item.id)
                }
            }
        }
    }

    private struct Item {
        let id: String
        let title: String
        let icon: String
        let action: () -> Void
    }

    private var buttons: [Item] {
        [
            Item(id: "stop", title: "Stop", icon: "stop.fill") { coordinator.stop() },
            Item(id: "pauseResume", title: coordinator.userPaused ? "Resume" : "Pause",
                 icon: coordinator.userPaused ? "play.fill" : "pause.fill") { coordinator.togglePause() },
            Item(id: "previous", title: "Previous", icon: "backward.fill") { coordinator.previous() },
            Item(id: "next", title: "Next", icon: "forward.fill") { coordinator.next() },
            Item(id: "random", title: "Random", icon: "shuffle") { coordinator.random() },
            Item(id: "presets", title: "Presets", icon: "list.bullet") {
                coordinator.showPresetBrowser = true
            },
            Item(id: "settings", title: "Settings", icon: "gearshape") { coordinator.showSettings = true },
        ]
    }
}
