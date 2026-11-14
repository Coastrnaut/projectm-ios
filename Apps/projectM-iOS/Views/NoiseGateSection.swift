// NoiseGateSection.swift — AUD-011-R7, R10: Settings → Audio Analysis → Noise gate.
//
// A toggle (off by default) and a 1 dB-step threshold slider from −80 to −20 dBFS with a readout,
// disabled while the gate is off. VoiceOver reads "Noise gate", and "Gate threshold" with the readout
// as the value (FR-070). The footer says it applies to the microphone only and what it does not
// change. Strings come from `NoiseGateSetting.text(for:)` and plain constants (no inline string
// arithmetic in modifiers).
import SwiftUI

struct NoiseGateSection: View {
    @Bindable var noiseGate: NoiseGateSetting

    private static let toggleTitle = "Noise gate"
    private static let sliderTitle = "Gate threshold"
    private static let footer = "Microphone only. Keeps the native visuals and tempo detection still while the sound stays below the threshold, such as room noise. It doesn't change what you hear, what projectM receives or recordings."

    var body: some View {
        let valueText: String = NoiseGateSetting.text(for: noiseGate.thresholdDecibels)
        let range: ClosedRange<Double> = NoiseGateSetting.range
        let enabled: Bool = noiseGate.isEnabled
        Section {
            Toggle(Self.toggleTitle, isOn: $noiseGate.isEnabled)
                .accessibilityIdentifier("noiseGateToggle")
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.sliderTitle)
                    Spacer()
                    Text(valueText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("noiseGateThresholdValue")
                }
                .accessibilityElement(children: .contain)
                Slider(value: $noiseGate.thresholdDecibels, in: range, step: 1)
                    .accessibilityLabel(Self.sliderTitle)
                    .accessibilityValue(valueText)
                    .accessibilityIdentifier("noiseGateThresholdSlider")
            }
            .disabled(!enabled)
        } footer: {
            Text(Self.footer)
        }
    }
}
