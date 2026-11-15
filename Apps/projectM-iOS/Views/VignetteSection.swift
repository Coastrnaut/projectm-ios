// VignetteSection.swift — FX-015-R8: Settings → Vignette (specs/305-fx-015-vignette, contracts/vignette.md C4;
// ADR-0116).
//
// A toggle and, while on, "Intensity" (0…100%, readout "50%"), "Softness" (10…90%), "Center X" and "Center Y" (0…1 of
// the width and height, readout "0.50") sliders with ACC-005's `.accessibleParameter` (spoken "50 percent", "0.50";
// 1%, 5% and 0.05 per swipe). The footer names the visuals. Each row is its own small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 specs of the four sliders (ranges from `Vignette`, the single source).
@MainActor
enum VignetteParameterSpecs {
    static let intensity = AccessibleParameterSpec(id: "vignetteIntensitySlider", label: "Intensity", range: Vignette.intensityRange,
                                                   step: Vignette.intensityStep, unit: .percent(decimals: 0))
    static let softness = AccessibleParameterSpec(id: "vignetteSoftnessSlider", label: "Softness", range: Vignette.softnessRange,
                                                  step: Vignette.softnessStep, unit: .percent(decimals: 0))
    static let centerX = AccessibleParameterSpec(id: "vignetteCenterXSlider", label: "Center X", range: Vignette.centerRange,
                                                 step: Vignette.centerStep, unit: .number(decimals: 2))
    static let centerY = AccessibleParameterSpec(id: "vignetteCenterYSlider", label: "Center Y", range: Vignette.centerRange,
                                                 step: Vignette.centerStep, unit: .number(decimals: 2))
}

struct VignetteSection: View {
    @Bindable var setting: VignetteSetting

    static let header = "Vignette"
    static let footer = "Darkens the edges and corners of the picture smoothly while its middle stays unchanged, on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Softness sets how wide the transition is; Center X runs from the left edge (0) to the right (1), Center Y from the top to the bottom. At 0% intensity the picture is unchanged."

    /// ACC-005: the real setting's write paths (the view and tests use the same functions).
    static func intensityTarget(_ setting: VignetteSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.intensity }, set: { (value: Double) -> Void in setting.intensity = value })
    }

    static func softnessTarget(_ setting: VignetteSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.softness }, set: { (value: Double) -> Void in setting.softness = value })
    }

    static func centerXTarget(_ setting: VignetteSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.centerX }, set: { (value: Double) -> Void in setting.centerX = value })
    }

    static func centerYTarget(_ setting: VignetteSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.centerY }, set: { (value: Double) -> Void in setting.centerY = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("vignetteToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        VignetteSliderRow(spec: VignetteParameterSpecs.intensity, value: $setting.intensity,
                          target: Self.intensityTarget(setting), text: VignetteSetting.percentText(setting.intensity))
        VignetteSliderRow(spec: VignetteParameterSpecs.softness, value: $setting.softness,
                          target: Self.softnessTarget(setting), text: VignetteSetting.percentText(setting.softness))
        VignetteSliderRow(spec: VignetteParameterSpecs.centerX, value: $setting.centerX,
                          target: Self.centerXTarget(setting), text: VignetteSetting.fractionText(setting.centerX))
        VignetteSliderRow(spec: VignetteParameterSpecs.centerY, value: $setting.centerY,
                          target: Self.centerYTarget(setting), text: VignetteSetting.fractionText(setting.centerY))
    }
}

/// A slider with its title and readout.
private struct VignetteSliderRow: View {
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
