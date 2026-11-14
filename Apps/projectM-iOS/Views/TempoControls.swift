// TempoControls.swift — the tap tempo group in the visualizer controls (SHOW-011-R12, R13, R17;
// contracts/tempo-source.md "App").
//
// The readout, the Tap button and, only while a manual tempo is set, Reset tempo. ANL-006: the
// readout shows the BPM over a state word ("120 BPM"/"Stable", "≈120 BPM"/"Uncertain",
// "—"/"Searching", "120 BPM"/"Manual"), with no dimming (ACC-004's contrast audit) and no
// animation. VoiceOver reads it as one element ("Tempo, About 120 BPM, uncertain"); the Tap
// button's value is the progress ("Tap 2 of 4") or the same words. Text styles scale
// with Dynamic Type; `compact` shows the buttons as icons (the one-row layout, FR-087).
import PerformanceControl
import SwiftUI

struct TempoControls: View {
    let coordinator: AppCoordinator
    var compact = false

    var body: some View {
        let tempo = coordinator.tempo
        let snapshot = tempo.snapshot
        let readout: TempoReadout = tempo.readout
        let number: String = TempoCoordinator.readoutText(readout)
        let word: String = TempoCoordinator.stateText(readout)
        let spoken: String = TempoCoordinator.accessibilityValue(readout)
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(number)
                    .font(.subheadline.monospacedDigit())
                Text(word)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo")
            .accessibilityValue(spoken)
            .accessibilityAddTraits(.isStaticText)   // ACC-004: a readout, not a control (hit-region audit)
            .accessibilityIdentifier("tempoReadout")

            Button { coordinator.tapTempo() } label: {
                if compact {
                    Image(systemName: "hand.tap").frame(minWidth: 36, minHeight: 36)
                } else {
                    Label("Tap", systemImage: "hand.tap")
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Tap tempo")
            .accessibilityValue(tempo.tapValue)
            .accessibilityHint("Tap in time with the music, four times, to set the tempo")
            .accessibilityIdentifier("tapTempo")

            if snapshot.origin == .manual {
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
}
