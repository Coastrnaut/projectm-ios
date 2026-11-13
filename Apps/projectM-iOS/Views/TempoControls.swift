// TempoControls.swift — the tap tempo group in the visualizer controls (SHOW-011-R12, R13, R17;
// contracts/tempo-source.md "App").
//
// The readout ("120 BPM" over "Manual"/"Detected", or "—"), the Tap button and, only while a
// manual tempo is set, Reset tempo. VoiceOver reads the readout as one element ("Tempo, 120 BPM,
// manual"); the Tap button's value is the progress ("Tap 2 of 4") or the tempo. Text styles scale
// with Dynamic Type; `compact` shows the buttons as icons (the one-row layout, FR-087).
import PerformanceControl
import SwiftUI

struct TempoControls: View {
    let coordinator: AppCoordinator
    var compact = false

    var body: some View {
        let tempo = coordinator.tempo
        let snapshot = tempo.snapshot
        let origin = TempoCoordinator.originText(snapshot)
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(TempoCoordinator.readoutText(snapshot))
                    .font(.subheadline.monospacedDigit())
                if !origin.isEmpty {
                    Text(origin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo")
            .accessibilityValue(TempoCoordinator.accessibilityValue(snapshot))
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
