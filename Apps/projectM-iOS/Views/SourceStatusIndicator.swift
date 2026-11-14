// SourceStatusIndicator.swift — the compact source-and-state indicator (task T094; FR-013, FR-042,
// FR-070). Mode label (contracts/ui-states.md) plus the audio state, e.g. "In-App Playback · Active
// audio", with a test signal's name between them while one plays (AUD-016); always visible in the visualizer, inside the controls or on its own when they are hidden.
// AUD-012: "Switching source…" while a source switch waits for the new source's audio.
import AudioCore
import CaptureKit
import CaptureUI
import SwiftUI
import UIKit

/// The compact source-and-state indicator (FR-042), e.g. "In-App Playback · Active audio".
struct SourceStatusIndicator: View {
    let coordinator: AppCoordinator

    var text: String { coordinator.sourceStatusText }

    /// The indicator text; also what VoiceOver announces when the audio state changes (FR-070).
    /// With a test signal playing it names the signal: "In-App Playback · Test tone 1 kHz · Active
    /// audio" (AUD-016-R16).
    /// AUD-012-R7: while a switch waits for the new source's audio, "Switching source…".
    static func text(mode: AudioSourceMode?, state: AudioState, signal: String? = nil, switching: Bool = false) -> String {
        if switching { return UIStrings.switchingSource }
        return UIStrings.sourceStatus(mode: mode, state: state, signal: signal)
    }

    /// FR-070: announces an audio-state change to VoiceOver users, as the indicator shows it.
    static func announce(mode: AudioSourceMode?, state: AudioState, signal: String? = nil, switching: Bool = false) {
        UIAccessibility.post(notification: .announcement, argument: text(mode: mode, state: state, signal: signal, switching: switching))
    }

    /// AUD-014-R18: what VoiceOver hears when In-App Playback goes on hold for a reason the user
    /// did not choose: the indicator's text, then the explanation. Nil in every other case.
    static func holdAnnouncement(mode: AudioSourceMode?, state: AudioState, reason: StopReason?, signal: String? = nil) -> String? {
        UIStrings.playbackHoldAnnouncement(status: text(mode: mode, state: state, signal: signal), mode: mode, reason: reason)
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
