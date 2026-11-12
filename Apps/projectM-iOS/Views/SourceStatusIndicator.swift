// SourceStatusIndicator.swift — the compact source-and-state indicator (task T094; FR-013, FR-042,
// FR-070). Mode label (contracts/ui-states.md) plus the audio state, e.g. "In-App Playback · Active
// audio"; always visible in the visualizer, inside the controls or on its own when they are hidden.
import AudioCore
import CaptureKit
import CaptureUI
import SwiftUI
import UIKit

/// The compact source-and-state indicator (FR-042), e.g. "In-App Playback · Active audio".
struct SourceStatusIndicator: View {
    let coordinator: AppCoordinator

    var text: String { Self.text(mode: coordinator.manager.activeMode, state: coordinator.manager.state) }

    /// The indicator text; also what VoiceOver announces when the audio state changes (FR-070).
    static func text(mode: AudioSourceMode?, state: AudioState) -> String {
        "\(mode.map(UIStrings.label) ?? "No source") · \(UIStrings.state(state))"
    }

    /// FR-070: announces an audio-state change to VoiceOver users, as the indicator shows it.
    static func announce(mode: AudioSourceMode?, state: AudioState) {
        UIAccessibility.post(notification: .announcement, argument: text(mode: mode, state: state))
    }

    /// AUD-014-R18: what VoiceOver hears when In-App Playback goes on hold for a reason the user
    /// did not choose: the indicator's text, then the explanation. Nil in every other case.
    static func holdAnnouncement(mode: AudioSourceMode?, state: AudioState, reason: StopReason?) -> String? {
        UIStrings.playbackHoldAnnouncement(status: text(mode: mode, state: state), mode: mode, reason: reason)
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
