// SourceStatusIndicator.swift — the compact source-and-state indicator (task T094; FR-013, FR-042,
// FR-070). Mode label (contracts/ui-states.md) plus the audio state, e.g. "In-App Playback · Active
// audio", with a test signal's name between them while one plays (AUD-016); always visible in the visualizer, inside the controls or on its own when they are hidden.
// AUD-012: "Switching source…" while a source switch waits for the new source's audio.
// ACC-003-R2, R9: a symbol per state; an opaque, bordered background with Increase Contrast.
import AudioCore
import CaptureKit
import CaptureUI
import SwiftUI
import UIKit

/// The compact source-and-state indicator (FR-042), e.g. "In-App Playback · Active audio".
struct SourceStatusIndicator: View {
    let coordinator: AppCoordinator

    var text: String { coordinator.sourceStatusText }

    /// The indicator text; also what VoiceOver announces when the audio state changes (FR-070; posted
    /// through ACC-011's status-event router, `AppCoordinator.announceSourceStatus()`).
    /// With a test signal playing it names the signal: "In-App Playback · Test tone 1 kHz · Active
    /// audio" (AUD-016-R16).
    /// AUD-012-R7: while a switch waits for the new source's audio, "Switching source…".
    static func text(mode: AudioSourceMode?, state: AudioState, signal: String? = nil, switching: Bool = false) -> String {
        if switching { return UIStrings.switchingSource }
        return UIStrings.sourceStatus(mode: mode, state: state, signal: signal)
    }

    /// AUD-014-R18: what VoiceOver hears when In-App Playback goes on hold for a reason the user
    /// did not choose: the indicator's text, then the explanation. Nil in every other case.
    static func holdAnnouncement(mode: AudioSourceMode?, state: AudioState, reason: StopReason?, signal: String? = nil) -> String? {
        UIStrings.playbackHoldAnnouncement(status: text(mode: mode, state: state, signal: signal), mode: mode, reason: reason)
    }

    /// ACC-003-R2: the symbol whose outline tells the audio state (or a source switch) apart.
    static func cue(state: AudioState, switching: Bool) -> StatusCue {
        switching ? StatusCueCatalog.switching : StatusCueCatalog.source(state)
    }

    var body: some View {
        // ACC-003: the symbol is inline in the identified static text; VoiceOver reads the words only.
        let cue: StatusCue = Self.cue(state: coordinator.manager.state, switching: coordinator.manager.switchingTo != nil)
        StatusCueLabel.text(cue, words: text)
            .accessibilityIdentifier("sourceIndicator")
            .accessibilityLabel(text)
            .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .statusBadgeBackground(Capsule(), material: .ultraThinMaterial)   // ACC-003-R9
    }
}
