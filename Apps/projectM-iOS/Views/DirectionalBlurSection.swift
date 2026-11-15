// DirectionalBlurSection.swift — FX-007-R9: Settings → Directional blur (specs/295-fx-007-directional-blur,
// contracts/directional-blur.md C4; ADR-0106).
//
// A toggle and, while on, a "Radius" slider (0…2% of the shorter side, readout "0.5%") and an "Angle" slider (0…180°,
// readout "45°") with ACC-005's `.accessibleParameter` (spoken "0.5 percent", "45 degrees"; 0.1% and 15° per swipe).
// The footer names the visuals. Each row is its own small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 specs of the two sliders (ranges from `DirectionalBlur`, the single source).
@MainActor
enum DirectionalBlurParameterSpecs {
    static let radius = AccessibleParameterSpec(id: "directionalBlurRadiusSlider", label: "Radius",
                                                range: DirectionalBlur.radiusRange, step: DirectionalBlur.radiusStep,
                                                unit: .percent(decimals: 1))
    static let angle = AccessibleParameterSpec(id: "directionalBlurAngleSlider", label: "Angle", range: DirectionalBlur.angleRange,
                                               step: DirectionalBlur.angleStep, unit: .degrees)
}

struct DirectionalBlurSection: View {
    @Bindable var setting: DirectionalBlurSetting

    static let header = "Directional blur"
    static let footer = "Smears the picture along one direction, like a motion streak, on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Angle 0° is horizontal and 90° vertical; Radius sets how far the streak reaches on each side."

    /// ACC-005: the real setting's write paths (the view and tests use the same functions).
    static func radiusTarget(_ setting: DirectionalBlurSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.radius }, set: { (value: Double) -> Void in setting.radius = value })
    }

    static func angleTarget(_ setting: DirectionalBlurSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.angleDegrees }, set: { (value: Double) -> Void in setting.angleDegrees = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("directionalBlurToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        DirectionalBlurSliderRow(spec: DirectionalBlurParameterSpecs.radius, value: $setting.radius,
                                 target: Self.radiusTarget(setting), text: DirectionalBlurSetting.radiusText(setting.radius))
        DirectionalBlurSliderRow(spec: DirectionalBlurParameterSpecs.angle, value: $setting.angleDegrees,
                                 target: Self.angleTarget(setting), text: DirectionalBlurSetting.angleText(setting.angleDegrees))
    }
}

/// A slider with its title and readout.
private struct DirectionalBlurSliderRow: View {
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
