// ShowControls.swift — the show in the visualizer (SHOW-001-R13, R15; Clarifications).
//
// * `ShowCueRow`: in the controls (hidden with them), when the show has at least one cue: Previous
//   cue, the position and label ("Cue 2 of 5 · Intro"), Next cue. A button that would do nothing is
//   disabled. VoiceOver reads the row's value ("Cue 2 of 5, Intro") and the buttons' labels (FR-070).
// * `ShowKeyCommands`: zero-size buttons outside the auto-hiding controls carrying the hardware
//   keyboard shortcuts, so a keyboard or presentation clicker steps the show whether or not the
//   controls are shown: Right Arrow and Page Down → Next cue, Left Arrow and Page Up → Previous cue,
//   no modifiers. B stays SHOW-014's. A presented sheet takes the keyboard (as for B).
// * `ShowNotice`: the step's notice (missing scene, layers left out) for about 4 s.
// * SHOW-002-R9: while a timed advance counts down, the status shows "Next in 0:42" (", held" while held) under the
//   cue, and VoiceOver reads it in the row's value ("Cue 2 of 5, Intro, next cue in 42 seconds").
// * SHOW-003-R7: while a cue step waits for the beat or bar, "Cue queued for the next beat" shows under the cue.
// * SHOW-005-R8: the row's Hold toggle (pause.circle) freezes timed advances; VoiceOver "Hold timed advances", value
//   On/Off. Next and Previous stay available while it is on.
// * UIX-002: the row's "Scenes" button opens the quick scene switcher; ⌘K toggles it from the keyboard.
//   While it is open the arrow and Page keys belong to its search field, so they are not registered
//   here. After a close without a choice VoiceOver focus returns to the Scenes button.
// * SHOW-006-R1: the row's Rehearse toggle (eye.circle) shows the device-only cue rehearsal panel; VoiceOver
//   "Rehearse next cue", value On/Off.
// * SHOW-007-R8: under the buttons, the show timeline transport (`ShowTimelineRow`) when a cue is timed.
import ShowControl
import SwiftUI

struct ShowCueRow: View {
    let coordinator: AppCoordinator
    /// ACC-009-R2: false while the one-handed cluster carries Previous cue and Next cue (the status, Hold, Rehearse and
    /// Scenes stay).
    var showsArrows = true
    /// UIX-002-R11: VoiceOver focus returns here after the switcher closes without a choice.
    @AccessibilityFocusState private var scenesFocused: Bool

    var body: some View {
        let revision: Int = coordinator.sceneSwitcher.focusReturnRevision
        return row
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("showCueRow")
            .onChange(of: revision) { () -> Void in scenesFocused = true }
    }

    private var row: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if showsArrows { previousButton }   // ACC-009: the one-handed cluster takes the arrows
                status
                if showsArrows { nextButton }
                trailingButtons
            }
            if coordinator.showTransport.isAvailable {   // SHOW-007-R8: only with a timed cue
                ShowTimelineRow(transport: coordinator.showTransport, touched: { coordinator.showControls() })
            }
        }
    }

    /// Hold (SHOW-005), Rehearse (SHOW-006) and Scenes (UIX-002), in the row's own spacing.
    private var trailingButtons: some View {
        HStack(spacing: 12) {
            holdButton
            rehearseButton
            scenesButton
        }
    }

    private var previousButton: some View {
        Button { coordinator.showPreviousCue() } label: {
            Image(systemName: "chevron.backward.circle.fill").font(.title2)
        }
        .disabled(!coordinator.show.list.canGoPrevious)
        .accessibilityLabel("Previous cue")
        .accessibilityIdentifier("showPreviousCue")
    }

    private var nextButton: some View {
        Button { coordinator.showNextCue() } label: {
            Image(systemName: "chevron.forward.circle.fill").font(.title2)
        }
        .disabled(!coordinator.show.list.canGoNext)
        .accessibilityLabel("Next cue")
        .accessibilityIdentifier("showNextCue")
    }

    private var scenesButton: some View {
        Button { coordinator.openSceneSwitcher() } label: {   // UIX-002-R1
            Image(systemName: "magnifyingglass.circle.fill").font(.title2)
        }
        .accessibilityLabel("Scenes")
        .accessibilityHint("Search the show's scenes")
        .accessibilityIdentifier("showSceneSwitcher")
        .accessibilityFocused($scenesFocused)
    }

    /// SHOW-005-R8: the performer's Hold (session only).
    private var holdButton: some View {
        let held: Bool = coordinator.showAutoAdvance.isOperatorHeld
        let icon: String = held ? "pause.circle.fill" : "pause.circle"
        return Button { coordinator.toggleShowHold() } label: {
            Image(systemName: icon).font(.title2)
        }
        .tint(held ? .orange : nil)
        .accessibilityLabel("Hold timed advances")
        .accessibilityValue(held ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("showHold")
    }

    /// SHOW-006-R1: rehearsal is session only.
    private var rehearseButton: some View {
        let on: Bool = coordinator.cueRehearsal.isOn
        return Button { coordinator.toggleCueRehearsal() } label: {
            Image(systemName: on ? "eye.circle.fill" : "eye.circle").font(.title2)
        }
        .tint(on ? .yellow : nil)
        .accessibilityLabel("Rehearse next cue")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("showRehearse")
    }

    /// The position and label, with SHOW-002's countdown under it while one runs. The status text stays the
    /// VoiceOver element (its value carries the countdown); the countdown line itself is hidden from VoiceOver.
    private var status: some View {
        let show: ShowCoordinator = coordinator.show
        let advance: ShowAutoAdvanceCoordinator = coordinator.showAutoAdvance
        var value: String = show.accessibilityValue
        if let spoken = advance.spokenCountdown { value += ", \(spoken)" }
        return VStack(spacing: 0) {
            Text(show.statusText)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel("Show")
                .accessibilityValue(value)
                .accessibilityIdentifier("showCueStatus")
            if let quantizer = show.cueQuantizer { QueuedCueLabel(quantizer: quantizer) }   // SHOW-003-R7
            if let countdown = advance.countdownText {
                Text(countdown)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ShowKeyCommands: View {
    let coordinator: AppCoordinator

    var body: some View {
        ZStack {
            if !coordinator.sceneSwitcher.isOpen {   // UIX-002 contract C2: the search field owns the arrows
                key(.rightArrow) { coordinator.keyNextCue() }
                key(.pageDown) { coordinator.keyNextCue() }
                key(.leftArrow) { coordinator.keyPreviousCue() }
                key(.pageUp) { coordinator.keyPreviousCue() }
            }
            Button("") { coordinator.toggleSceneSwitcher() }.keyboardShortcut("k", modifiers: .command)   // UIX-002-R1
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func key(_ equivalent: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button("", action: action).keyboardShortcut(equivalent, modifiers: [])
    }
}

struct ShowNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlaySurface(Capsule())   // ACC-008-R2
            .accessibilityIdentifier("showNotice")
    }
}
