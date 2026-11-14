// ColorGradeSection.swift — FX-003-R9: Settings → Color (specs/123-fx-003-color-grading, contracts/color-grade.md).
//
// Five sliders (temperature, lift, gamma, gain, saturation) with readouts, ACC-005's `.accessibleParameter`
// (VoiceOver label, spoken value, one step per swipe), a footer naming the graded visuals, and "Reset to neutral"
// (disabled at neutral). Each row is its own small view; strings come from `ColorGradeSetting`'s typed readouts.
import Compositor
import SwiftUI

/// ACC-005 specs of the five sliders (ranges and steps from `ColorGrade`, the MOD-001 single source).
@MainActor
enum ColorGradeParameterSpecs {
    static let temperature = AccessibleParameterSpec(id: "colorTemperatureSlider", label: "Temperature",
                                                     range: ColorGrade.temperatureRange, step: ColorGrade.temperatureStep * 5,
                                                     unit: .number(decimals: 2))
    static let lift = AccessibleParameterSpec(id: "colorLiftSlider", label: "Lift", range: ColorGrade.liftRange,
                                              step: ColorGrade.liftStep, unit: .number(decimals: 3))
    static let gamma = AccessibleParameterSpec(id: "colorGammaSlider", label: "Gamma", range: ColorGrade.gammaRange,
                                               step: ColorGrade.gammaStep * 5, unit: .number(decimals: 2))
    static let gain = AccessibleParameterSpec(id: "colorGainSlider", label: "Gain", range: ColorGrade.gainRange,
                                              step: ColorGrade.gainStep * 5, unit: .multiplier)
    static let saturation = AccessibleParameterSpec(id: "colorSaturationSlider", label: "Saturation",
                                                    range: ColorGrade.saturationRange, step: ColorGrade.saturationStep * 5,
                                                    unit: .percent(decimals: 0))
    static var all: [AccessibleParameterSpec] { [temperature, lift, gamma, gain, saturation] }
}

struct ColorGradeSection: View {
    @Bindable var setting: ColorGradeSetting

    static let header = "Color"
    static let footer = "Grades the Camera, Photo, Video and Text visuals on screen, on an external display, in recordings and in still captures. The spectrum visuals and projectM aren't graded. The flash limiter judges the graded picture."
    static let resetTitle = "Reset to neutral"

    /// ACC-005: the real setting's write path, one per slider (the view and tests use the same functions).
    static func target(_ setting: ColorGradeSetting, _ field: ReferenceWritableKeyPath<ColorGradeSetting, Double>) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting[keyPath: field] },
                        set: { (value: Double) -> Void in setting[keyPath: field] = value })
    }

    var body: some View {
        Section {
            ColorGradeRow(spec: ColorGradeParameterSpecs.temperature, value: $setting.temperature,
                          text: ColorGradeSetting.temperatureText(setting.temperature), target: Self.target(setting, \.temperature))
            ColorGradeRow(spec: ColorGradeParameterSpecs.lift, value: $setting.lift,
                          text: ColorGradeSetting.liftText(setting.lift), target: Self.target(setting, \.lift))
            ColorGradeRow(spec: ColorGradeParameterSpecs.gamma, value: $setting.gamma,
                          text: ColorGradeSetting.gammaText(setting.gamma), target: Self.target(setting, \.gamma))
            ColorGradeRow(spec: ColorGradeParameterSpecs.gain, value: $setting.gain,
                          text: ColorGradeSetting.gainText(setting.gain), target: Self.target(setting, \.gain))
            ColorGradeRow(spec: ColorGradeParameterSpecs.saturation, value: $setting.saturation,
                          text: ColorGradeSetting.saturationText(setting.saturation), target: Self.target(setting, \.saturation))
            ColorGradeResetButton(setting: setting)
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }
}

/// One slider with its title and readout.
private struct ColorGradeRow: View {
    let spec: AccessibleParameterSpec
    @Binding var value: Double
    let text: String
    let target: ParameterTarget

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
            Slider(value: $value, in: spec.range)
                .accessibleParameter(spec, target: target)
        }
    }
}

private struct ColorGradeResetButton: View {
    let setting: ColorGradeSetting

    var body: some View {
        let neutral: Bool = setting.isNeutral
        Button(ColorGradeSection.resetTitle) { setting.resetToNeutral() }
            .disabled(neutral)
            .accessibilityIdentifier("colorResetButton")
    }
}
