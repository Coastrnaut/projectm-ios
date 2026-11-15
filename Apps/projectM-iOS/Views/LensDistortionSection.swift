// LensDistortionSection.swift — FX-016-R8: Settings → Lens distortion (specs/306-fx-016-lens-distortion,
// contracts/lens-distortion.md C4; ADR-0117).
//
// A toggle and, while on, a "Strength" slider (−100…+100%, readout "+30%") with ACC-005's `.accessibleParameter`
// (spoken "30 percent", "-30 percent"; 1% per swipe) and a "Zoom to fill" toggle. The footer names the visuals and says
// what the sign and the zoom do. Each row is its own small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 spec of the slider (range from `LensDistortion`, the single source).
@MainActor
enum LensDistortionParameterSpecs {
    static let strength = AccessibleParameterSpec(id: "lensDistortionStrengthSlider", label: "Strength",
                                                  range: LensDistortion.strengthRange, step: LensDistortion.strengthStep,
                                                  unit: .percent(decimals: 0))
}

struct LensDistortionSection: View {
    @Bindable var setting: LensDistortionSetting

    static let header = "Lens distortion"
    static let footer = "Bends the picture like a lens on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Positive strength bulges it outward (barrel), negative pinches it inward (pincushion); at 0% the picture is unchanged. Zoom to fill enlarges a bulged picture so its corners stay filled; without it the corners turn black. It does not change a pinched picture."

    /// ACC-005: the real setting's write path (the view and tests use the same function).
    static func strengthTarget(_ setting: LensDistortionSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.strength }, set: { (value: Double) -> Void in setting.strength = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("lensDistortionToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        LensDistortionSliderRow(spec: LensDistortionParameterSpecs.strength, value: $setting.strength,
                                target: Self.strengthTarget(setting), text: LensDistortionSetting.strengthText(setting.strength))
        Toggle("Zoom to fill", isOn: $setting.zoomToFill)
            .accessibilityIdentifier("lensDistortionZoomToggle")
    }
}

/// A slider with its title and readout.
private struct LensDistortionSliderRow: View {
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
