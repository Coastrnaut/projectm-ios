// EchoSection.swift — FX-010-R12: Settings → Echo (specs/297-fx-010-echo-feedback, contracts/echo-feedback.md C6;
// ADR-0108).
//
// A toggle and, while on, an "Echoes" slider (1…4, readout "3"), a "Delay" slider (10…500 ms, readout "100 ms") and a
// "Fade" slider (0.10…0.90, readout "0.60"), each with ACC-005's `.accessibleParameter` (spoken "3", "100
// milliseconds", "0.60"; 1, 10 ms and 0.05 per swipe). The footer names the visuals and the caps. Each row is its own
// small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 specs of the three sliders (ranges from `EchoFeedback` and `EchoSetting`, the single sources).
@MainActor
enum EchoParameterSpecs {
    static let count = AccessibleParameterSpec(id: "echoCountSlider", label: "Echoes", range: EchoSetting.countSliderRange,
                                               step: 1, unit: .number(decimals: 0))
    static let delay = AccessibleParameterSpec(id: "echoDelaySlider", label: "Delay",
                                               range: (EchoFeedback.delayRange.lowerBound * 1000)...(EchoFeedback.delayRange.upperBound * 1000),
                                               step: EchoFeedback.delayStep * 1000, unit: .milliseconds)
    static let decay = AccessibleParameterSpec(id: "echoDecaySlider", label: "Fade", range: EchoFeedback.decayRange,
                                               step: EchoFeedback.decayStep, unit: .number(decimals: 2))
}

struct EchoSection: View {
    @Bindable var setting: EchoSetting

    static let header = "Echo"
    static let footer = "Leaves up to 4 fading copies of moving things behind them on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Delay sets how far apart in time the copies are; Fade sets how much weaker each copy is than the one before. Copies are never brighter than the picture, and Reduce flashing and the sensory safety profile make them fainter."

    /// ACC-005: the real setting's write paths (the view and tests use the same functions).
    static func countTarget(_ setting: EchoSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.countValue }, set: { (value: Double) -> Void in setting.countValue = value })
    }

    static func delayTarget(_ setting: EchoSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.delayMilliseconds },
                        set: { (value: Double) -> Void in setting.delayMilliseconds = value })
    }

    static func decayTarget(_ setting: EchoSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.decay }, set: { (value: Double) -> Void in setting.decay = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("echoToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        EchoSliderRow(spec: EchoParameterSpecs.count, value: $setting.countValue, sliderStep: 1,
                      target: Self.countTarget(setting), text: EchoSetting.countText(setting.count))
        EchoSliderRow(spec: EchoParameterSpecs.delay, value: $setting.delayMilliseconds, sliderStep: EchoFeedback.delayStep * 1000,
                      target: Self.delayTarget(setting), text: EchoSetting.delayText(setting.delaySeconds))
        EchoSliderRow(spec: EchoParameterSpecs.decay, value: $setting.decay, sliderStep: EchoFeedback.decayStep,
                      target: Self.decayTarget(setting), text: EchoSetting.decayText(setting.decay))
    }
}

/// A stepped slider with its title and readout.
private struct EchoSliderRow: View {
    let spec: AccessibleParameterSpec
    @Binding var value: Double
    let sliderStep: Double
    let target: ParameterTarget
    let text: String

    var body: some View {
        let valueID: String = spec.id + "Value"
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spec.label)
                Spacer()
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(valueID)
            }
            .accessibilityElement(children: .contain)
            Slider(value: $value, in: spec.range, step: sliderStep)
                .accessibleParameter(spec, target: target)
        }
    }
}
