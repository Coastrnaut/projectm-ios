// SourceStatusIndicator.swift — the compact source-and-state indicator (task T094; FR-013, FR-042,
// FR-070). Mode label (contracts/ui-states.md) plus the audio state, e.g. "In-App Playback · Active
// audio"; always visible in the visualizer, inside the controls or on its own when they are hidden.
import CaptureUI
import SwiftUI

/// The compact source-and-state indicator (FR-042), e.g. "In-App Playback · Active audio".
struct SourceStatusIndicator: View {
    let coordinator: AppCoordinator

    var text: String {
        let manager = coordinator.manager
        let mode = manager.activeMode.map(UIStrings.label) ?? "No source"
        return "\(mode) · \(UIStrings.state(manager.state))"
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityIdentifier("sourceIndicator")
            .accessibilityLabel(text)
    }
}
