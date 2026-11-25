// TempoControls.swift — the tap tempo group in the visualizer controls (SHOW-011-R12, R13, R17;
// contracts/tempo-source.md "App").
//
// The readout, the Tap button and, only while a manual tempo is set, Reset tempo. ANL-006: the
// readout shows the BPM over a state word ("120 BPM"/"Stable", "≈120 BPM"/"Uncertain",
// "— BPM"/"Searching", "120 BPM"/"Manual"), with no dimming (ACC-004's contrast audit) and no
// animation. VoiceOver reads it as one element ("Tempo, About 120 BPM, uncertain"); the Tap
// button's value is the progress ("Tap 2 of 4") or the same words. Text styles scale
// with Dynamic Type; `compact` shows the buttons as icons (the one-row layout, FR-087).
import PerformanceControl
import SwiftUI

struct TempoControls: View {
    let coordinator: AppCoordinator
    var compact = false
    /// ACC-009-R2: false while the one-handed cluster carries Tap tempo (the readout and Reset stay).
    var showsTap = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // QA-011 D3 (2026-11-24): only the shown texts are observed (`display`), not `snapshot` or `readout`, which
        // change on nearly every analysis poll; the card was rebuilt 4 times a second with the same words.
        let display: TempoDisplay = coordinator.tempo.display
        let number: String = display.number
        let word: String = display.word
        let spoken: String = display.spoken
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(number)
                    .font(.subheadline.monospacedDigit())
                Text(word)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // ACC-006-R1: one line shrunk to fit at standard sizes; at accessibility sizes the readout
            // keeps its full size and may wrap (its row stacks, so it has the width).
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo")
            .accessibilityValue(spoken)
            .accessibilityAddTraits(.isStaticText)   // ACC-004: a readout, not a control (hit-region audit)
            .accessibilityIdentifier("tempoReadout")

            if showsTap { tapButton(display.tapValue) }

            if display.isManual {
                Button { coordinator.resetTempo() } label: {
                    if compact {
                        Image(systemName: "arrow.counterclockwise").frame(minWidth: 36, minHeight: 36)
                    } else {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Reset tempo")
                .accessibilityIdentifier("resetTempo")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tempoControls")
    }

    private func tapButton(_ value: String) -> some View {
        Button { coordinator.tapTempo() } label: {
            if compact {
                Image(systemName: "hand.tap").frame(minWidth: 36, minHeight: 36)
            } else {
                Label("Tap", systemImage: "hand.tap")
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Tap tempo")
        .accessibilityValue(value)
        .accessibilityHint("Tap in time with the music, four times, to set the tempo")
        .accessibilityIdentifier("tapTempo")
    }
}
