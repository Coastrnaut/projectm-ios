// RadialBlurSection.swift — FX-008-R8: Settings → Radial blur (specs/296-fx-008-radial-blur,
// contracts/radial-blur.md C4; ADR-0107).
//
// A toggle and, while on, a "Strength" slider (0…25%, readout "10%"), and "Focus X" and "Focus Y" sliders (0…100% of
// the width and height, 0 = left/top, readout "50%"), with ACC-005's `.accessibleParameter` (spoken "10 percent";
// 1% and 5% per swipe). The footer names the visuals. Each row is its own small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 specs of the three sliders (ranges from `RadialBlur`, the single source).
@MainActor
enum RadialBlurParameterSpecs {
    static let strength = AccessibleParameterSpec(id: "radialBlurStrengthSlider", label: "Strength", range: RadialBlur.strengthRange,
                                                  step: RadialBlur.strengthStep, unit: .percent(decimals: 0))
    static let focusX = AccessibleParameterSpec(id: "radialBlurFocusXSlider", label: "Focus X", range: RadialBlur.focusRange,
                                                step: RadialBlur.focusStep, unit: .percent(decimals: 0))
    static let focusY = AccessibleParameterSpec(id: "radialBlurFocusYSlider", label: "Focus Y", range: RadialBlur.focusRange,
                                                step: RadialBlur.focusStep, unit: .percent(decimals: 0))
}

struct RadialBlurSection: View {
    @Bindable var setting: RadialBlurSetting

    static let header = "Radial blur"
    static let footer = "Blurs the picture outward from a focus point, like a zoom during a long exposure, on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. The focus point stays sharp; the blur grows with the distance from it. Focus X runs from the left edge (0%) to the right (100%), Focus Y from the top to the bottom."

    /// ACC-005: the real setting's write paths (the view and tests use the same functions).
    static func strengthTarget(_ setting: RadialBlurSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.strength }, set: { (value: Double) -> Void in setting.strength = value })
    }

    static func focusXTarget(_ setting: RadialBlurSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.focusX }, set: { (value: Double) -> Void in setting.focusX = value })
    }

    static func focusYTarget(_ setting: RadialBlurSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.focusY }, set: { (value: Double) -> Void in setting.focusY = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("radialBlurToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        RadialBlurSliderRow(spec: RadialBlurParameterSpecs.strength, value: $setting.strength,
                            target: Self.strengthTarget(setting), text: RadialBlurSetting.percentText(setting.strength))
        RadialBlurSliderRow(spec: RadialBlurParameterSpecs.focusX, value: $setting.focusX,
                            target: Self.focusXTarget(setting), text: RadialBlurSetting.percentText(setting.focusX))
        RadialBlurSliderRow(spec: RadialBlurParameterSpecs.focusY, value: $setting.focusY,
                            target: Self.focusYTarget(setting), text: RadialBlurSetting.percentText(setting.focusY))
    }
}

/// A slider with its title and readout.
private struct RadialBlurSliderRow: View {
    let spec: AccessibleParameterSpec
    @Binding var value: Double
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
            Slider(value: $value, in: spec.range)
                .accessibleParameter(spec, target: target)
        }
    }
}
