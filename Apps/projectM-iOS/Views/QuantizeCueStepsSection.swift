// QuantizeCueStepsSection.swift — SHOW-003: the cue step quantize mode in Settings and the queued indication
// (specs/214-show-003-beat-quantized-cues; R1, R7; identifiers `quantizeCues.mode`, `showCueQueued`).
import PerformanceControl
import SwiftUI

/// Settings › Quantize cue steps: Off, Beat or Bar.
struct QuantizeCueStepsSection: View {
    @Bindable var quantizer: ShowCueQuantizer

    var body: some View {
        Section {
            Picker("Quantize cue steps", selection: $quantizer.mode) {
                ForEach(ShowCueQuantizer.modes, id: \.self) { (mode: QuantizeMode) in
                    Text(ShowCueQuantizer.title(mode)).tag(mode)
                }
            }
            .accessibilityIdentifier("quantizeCues.mode")
        } footer: {
            Text(Self.footer)
        }
    }

    static let footer: String = "Next, Previous and Go to a cue wait for the next beat or bar (4 beats), then change once. Press the same control again to cancel. Without a tempo the cue changes at once."
}

/// "Cue queued for the next beat" while a cue step waits; nothing otherwise. VoiceOver hears it when it is queued.
struct QueuedCueLabel: View {
    let quantizer: ShowCueQuantizer

    var body: some View {
        if let text = quantizer.queuedText {
            Label(text, systemImage: "metronome")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("showCueQueued")
        }
    }
}
