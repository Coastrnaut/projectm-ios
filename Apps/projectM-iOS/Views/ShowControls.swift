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
// * UIX-002: the row's "Scenes" button opens the quick scene switcher; ⌘K toggles it from the keyboard.
//   While it is open the arrow and Page keys belong to its search field, so they are not registered
//   here. After a close without a choice VoiceOver focus returns to the Scenes button.
import ShowControl
import SwiftUI

struct ShowCueRow: View {
    let coordinator: AppCoordinator
    /// UIX-002-R11: VoiceOver focus returns here after the switcher closes without a choice.
    @AccessibilityFocusState private var scenesFocused: Bool

    var body: some View {
        let show = coordinator.show
        HStack(spacing: 12) {
            Button { coordinator.showPreviousCue() } label: {
                Image(systemName: "chevron.backward.circle.fill").font(.title2)
            }
            .disabled(!show.list.canGoPrevious)
            .accessibilityLabel("Previous cue")
            .accessibilityIdentifier("showPreviousCue")
            status
            Button { coordinator.showNextCue() } label: {
                Image(systemName: "chevron.forward.circle.fill").font(.title2)
            }
            .disabled(!show.list.canGoNext)
            .accessibilityLabel("Next cue")
            .accessibilityIdentifier("showNextCue")
            Button { coordinator.openSceneSwitcher() } label: {   // UIX-002-R1
                Image(systemName: "magnifyingglass.circle.fill").font(.title2)
            }
            .accessibilityLabel("Scenes")
            .accessibilityHint("Search the show's scenes")
            .accessibilityIdentifier("showSceneSwitcher")
            .accessibilityFocused($scenesFocused)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showCueRow")
        .onChange(of: coordinator.sceneSwitcher.focusReturnRevision) { scenesFocused = true }
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
