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
import ShowControl
import SwiftUI

struct ShowCueRow: View {
    let coordinator: AppCoordinator

    var body: some View {
        let show = coordinator.show
        HStack(spacing: 12) {
            Button { coordinator.showPreviousCue() } label: {
                Image(systemName: "chevron.backward.circle.fill").font(.title2)
            }
            .disabled(!show.list.canGoPrevious)
            .accessibilityLabel("Previous cue")
            .accessibilityIdentifier("showPreviousCue")
            Text(show.statusText)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Show")
                .accessibilityValue(show.accessibilityValue)
                .accessibilityIdentifier("showCueStatus")
            Button { coordinator.showNextCue() } label: {
                Image(systemName: "chevron.forward.circle.fill").font(.title2)
            }
            .disabled(!show.list.canGoNext)
            .accessibilityLabel("Next cue")
            .accessibilityIdentifier("showNextCue")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("showCueRow")
    }
}

struct ShowKeyCommands: View {
    let coordinator: AppCoordinator

    var body: some View {
        ZStack {
            key(.rightArrow) { coordinator.keyNextCue() }
            key(.pageDown) { coordinator.keyNextCue() }
            key(.leftArrow) { coordinator.keyPreviousCue() }
            key(.pageUp) { coordinator.keyPreviousCue() }
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
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier("showNotice")
    }
}
