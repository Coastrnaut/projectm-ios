// ChromaticSplitSection.swift — FX-006-R8: Settings → Chromatic split (specs/293-fx-006-chromatic-split,
// contracts/chromatic-split.md C4; ADR-0104).
//
// A toggle and, while on, an "Amount" slider (0…2% of the shorter side, readout "0.5%"), an "Angle" slider (0…360°,
// readout "45°", hidden while Radial is on) with ACC-005's `.accessibleParameter` (spoken "0.5 percent", "45 degrees";
// 0.1% and 15° per swipe) and a "Radial" switch. The footer names the visuals and the edge rule. Each row is its own
// small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 specs of the two sliders (ranges from `ChromaticSplit`, the single source).
@MainActor
enum ChromaticSplitParameterSpecs {
    static let amount = AccessibleParameterSpec(id: "chromaticAmountSlider", label: "Amount", range: ChromaticSplit.amountRange,
                                                step: ChromaticSplit.amountStep, unit: .percent(decimals: 1))
    static let angle = AccessibleParameterSpec(id: "chromaticAngleSlider", label: "Angle", range: ChromaticSplit.angleRange,
                                               step: ChromaticSplit.angleStep, unit: .degrees)
}

struct ChromaticSplitSection: View {
    @Bindable var setting: ChromaticSplitSetting

    static let header = "Chromatic split"
    static let footer = "Moves the red and blue parts of the picture apart for a lens-fringe look, on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Radial grows the split from the centre. The split fades out toward the edges of the picture, so nothing from outside the frame appears."

    /// ACC-005: the real setting's write paths (the view and tests use the same functions).
    static func amountTarget(_ setting: ChromaticSplitSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.amount }, set: { (value: Double) -> Void in setting.amount = value })
    }

    static func angleTarget(_ setting: ChromaticSplitSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.angleDegrees }, set: { (value: Double) -> Void in setting.angleDegrees = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("chromaticToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        ChromaticSliderRow(spec: ChromaticSplitParameterSpecs.amount, value: $setting.amount, target: Self.amountTarget(setting),
                           text: ChromaticSplitSetting.amountText(setting.amount))
        Toggle("Radial", isOn: $setting.isRadial)
            .accessibilityIdentifier("chromaticRadialToggle")
        if !setting.isRadial {
            ChromaticSliderRow(spec: ChromaticSplitParameterSpecs.angle, value: $setting.angleDegrees,
                               target: Self.angleTarget(setting), text: ChromaticSplitSetting.angleText(setting.angleDegrees))
        }
    }
}

/// A slider with its title and readout.
private struct ChromaticSliderRow: View {
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
