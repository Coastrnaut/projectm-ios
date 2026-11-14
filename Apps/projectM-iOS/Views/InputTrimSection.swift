// InputTrimSection.swift — AUD-008-R8, R9: Settings → Audio Analysis → Input trim.
//
// A 1 dB-step slider from −12 to +24 dB with a signed readout and "Reset to 0 dB". VoiceOver reads the
// label "Input trim" and the readout as the value (FR-070). The footer states what the trim does not
// change. Strings come from `InputTrimSetting.text(for:)` and plain constants (no inline string
// arithmetic in modifiers).
// ACC-005: VoiceOver reads "plus 6 decibels" and swipes move the stored trim by 1 dB (`target`).
import SwiftUI

struct InputTrimSection: View {
    @Bindable var inputTrim: InputTrimSetting

    private static let title = "Input trim"
    private static let resetTitle = "Reset to 0 dB"
    private static let footer = "Changes how strongly the native visuals and tempo detection react to the audio. It doesn't change what you hear, what projectM receives or recordings."

    /// ACC-005: the real setting (saved, mirrored into the analysis control).
    static func target(_ inputTrim: InputTrimSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in inputTrim.decibels },
                        set: { (value: Double) -> Void in inputTrim.decibels = value })
    }

    var body: some View {
        let valueText: String = InputTrimSetting.text(for: inputTrim.decibels)
        let range: ClosedRange<Double> = InputTrimSetting.range
        let spec: AccessibleParameterSpec = AccessibleParameterCatalog.inputTrim
        Section {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.title)
                    Spacer()
                    Text(valueText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("inputTrimValue")
                }
                .accessibilityElement(children: .contain)
                Slider(value: $inputTrim.decibels, in: range, step: spec.step)
                    .accessibleParameter(spec, target: Self.target(inputTrim))
            }
            Button(Self.resetTitle) { inputTrim.reset() }
                .disabled(inputTrim.decibels == 0)
                .accessibilityIdentifier("inputTrimReset")
        } header: {
            Text("Audio Analysis")
        } footer: {
            Text(Self.footer)
        }
    }
}
