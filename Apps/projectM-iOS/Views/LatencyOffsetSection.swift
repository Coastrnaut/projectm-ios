// LatencyOffsetSection.swift — AUD-013-R10, R12: Settings → Visual Delay.
//
// A source picker (it starts on the active source, or In-App Playback with none), one 5 ms-step
// slider from 0 to 250 ms for the picked source with a readout, "Estimate from Output" and "Reset"
// for the picked source, and a footer saying the visuals can only be delayed. VoiceOver reads
// "Delay for source", and "Visual delay" with the readout as the value (FR-070). Strings come from
// `LatencyOffsetSetting.text(for:)` and plain constants (typed steps, no inline string arithmetic in
// modifiers).
// ACC-005: VoiceOver reads "180 milliseconds" and swipes move the picked source's stored delay by 5 ms.
import AudioCore
import SwiftUI

struct LatencyOffsetSection: View {
    @Bindable var setting: LatencyOffsetSetting
    @State private var picked: AudioSourceMode?

    private static let header = "Visual Delay"
    private static let pickerTitle = "Delay for source"
    private static let sliderTitle = "Visual delay"
    private static let estimateTitle = "Estimate from Output"
    private static let resetTitle = "Reset"
    private static let footer = "Delays projectM and the native visuals so they line up with what you hear, for example on Bluetooth headphones. Visuals can only be delayed, never shown earlier than the sound. Estimate from Output uses the delay the current audio output reports; Microphone is set to 0 ms because its sound is heard before it is analyzed."

    static func title(for mode: AudioSourceMode) -> String {
        switch mode {
        case .microphone: return "Microphone"
        case .inAppPlayback: return "In-App Playback"
        case .systemAppCapture: return "System Audio"
        }
    }

    /// ACC-005: the real per-source setting (saved; applied when `mode` is the active source).
    static func target(_ setting: LatencyOffsetSetting, mode: AudioSourceMode) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.milliseconds(for: mode) },
                        set: { (value: Double) -> Void in setting.setMilliseconds(value, for: mode) })
    }

    var body: some View {
        let mode: AudioSourceMode = picked ?? setting.activeMode ?? .inAppPlayback
        let value: Double = setting.milliseconds(for: mode)
        let valueText: String = LatencyOffsetSetting.text(for: value)
        let range: ClosedRange<Double> = LatencyOffsetSetting.range
        let spec: AccessibleParameterSpec = AccessibleParameterCatalog.latencyOffset
        let target: ParameterTarget = Self.target(setting, mode: mode)
        let modeBinding = Binding<AudioSourceMode>(
            get: { () -> AudioSourceMode in mode },
            set: { (newValue: AudioSourceMode) -> Void in picked = newValue })
        let valueBinding = Binding<Double>(
            get: { () -> Double in target.get() },
            set: { (newValue: Double) -> Void in target.set(newValue) })
        Section {
            Picker(Self.pickerTitle, selection: modeBinding) {
                ForEach(AudioSourceMode.allCases, id: \.self) { (option: AudioSourceMode) in
                    Text(Self.title(for: option)).tag(option)
                }
            }
            .accessibilityIdentifier("latencyOffsetSource")
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.sliderTitle)
                    Spacer()
                    Text(valueText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("latencyOffsetValue")
                }
                .accessibilityElement(children: .contain)
                Slider(value: valueBinding, in: range, step: spec.step)
                    .accessibleParameter(spec, target: target)
            }
            Button(Self.estimateTitle) { setting.estimate(for: mode) }
                .accessibilityIdentifier("latencyOffsetEstimate")
            Button(Self.resetTitle) { setting.reset(mode) }
                .accessibilityIdentifier("latencyOffsetReset")
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }
}
