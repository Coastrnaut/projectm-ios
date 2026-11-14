// QuantizeChangesSection.swift — MOD-017: the quantize mode in Settings and the queued indication
// (specs/206-mod-017-quantized-changes; R1, R9; contract Q2 identifiers `quantize.mode`, `quantize.queued.<id>`).
import ParameterGraph
import PerformanceControl
import SwiftUI

/// Settings › Quantize changes: Off, Beat, Bar or Cue.
struct QuantizeChangesSection: View {
    @Bindable var quantizer: ParameterQuantizer

    var body: some View {
        Section {
            Picker("Quantize changes", selection: $quantizer.mode) {
                ForEach(QuantizeMode.allCases, id: \.self) { (mode: QuantizeMode) in
                    Text(ParameterQuantizer.title(mode)).tag(mode)
                }
            }
            .accessibilityIdentifier("quantize.mode")
        } footer: {
            Text(Self.footer)
        }
    }

    static let footer: String = "On/off and choice settings changed in the inspector, the shelf or a macro wait for the next beat, bar (4 beats) or cue step, then apply once. Without a tempo, or without cues, they apply at once."
}

/// "Queued for the next beat" under a control while its change waits; nothing otherwise.
struct QueuedChangeLabel: View {
    let quantizer: ParameterQuantizer
    let id: ParameterID

    var body: some View {
        if let text = quantizer.queuedText(for: id) {
            Label(text, systemImage: "metronome")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quantize.queued." + id.rawValue)
        }
    }
}
