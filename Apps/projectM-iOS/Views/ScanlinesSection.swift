// ScanlinesSection.swift — FX-018-R8: Settings → Scanlines (specs/312-fx-018-scanline-texture, contracts/scanlines.md C4;
// ADR-0123).
//
// A toggle and, while on, "Spacing" (2…16 pixels, readout "3 px"), "Thickness" (1…spacing − 1 pixels; shows 1 and is
// disabled at spacing 2) and "Intensity" (0…100%, readout "50%") sliders with ACC-005's `.accessibleParameter` (spoken
// "3 pixels", "50 percent"; one pixel or 1% per swipe), and a Horizontal/Vertical choice. The footer names the visuals.
// Each row is its own small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 specs of the three sliders (ranges from `Scanlines`, the single source; Thickness takes its range from the
/// spacing through `withRange`).
@MainActor
enum ScanlinesParameterSpecs {
    static let spacing = AccessibleParameterSpec(id: "scanlinesSpacingSlider", label: "Spacing",
                                                 range: Double(Scanlines.spacingRange.lowerBound)...Double(Scanlines.spacingRange.upperBound),
                                                 step: 1, unit: .pixels)
    static let thickness = AccessibleParameterSpec(id: "scanlinesThicknessSlider", label: "Thickness",
                                                   range: Double(Scanlines.thicknessRange.lowerBound)...Double(Scanlines.thicknessRange.upperBound),
                                                   step: 1, unit: .pixels)
    static let intensity = AccessibleParameterSpec(id: "scanlinesIntensitySlider", label: "Intensity", range: Scanlines.intensityRange,
                                                   step: Scanlines.intensityStep, unit: .percent(decimals: 0))
}

struct ScanlinesSection: View {
    @Bindable var setting: ScanlinesSetting

    static let header = "Scanlines"
    static let footer = "Darkens thin lines at an even pitch, like an old CRT screen, on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Spacing and Thickness are in pixels of the picture and the first line starts at its top (left) edge; the pattern never moves. At 0% intensity the picture is unchanged."

    /// ACC-005: the real setting's write paths (the view and tests use the same functions).
    static func spacingTarget(_ setting: ScanlinesSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.spacingValue }, set: { (value: Double) -> Void in setting.spacingValue = value })
    }

    static func thicknessTarget(_ setting: ScanlinesSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.thicknessValue }, set: { (value: Double) -> Void in setting.thicknessValue = value })
    }

    static func intensityTarget(_ setting: ScanlinesSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.intensity }, set: { (value: Double) -> Void in setting.intensity = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("scanlinesToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        ScanlinesSliderRow(spec: ScanlinesParameterSpecs.spacing, value: $setting.spacingValue, step: 1,
                           target: Self.spacingTarget(setting), text: ScanlinesSetting.pixelText(setting.spacing))
        ScanlinesSliderRow(spec: ScanlinesParameterSpecs.thickness.withRange(setting.thicknessRange), value: $setting.thicknessValue,
                           step: 1, target: Self.thicknessTarget(setting), text: ScanlinesSetting.pixelText(setting.thickness))
            .disabled(!setting.isThicknessAdjustable)
        ScanlinesSliderRow(spec: ScanlinesParameterSpecs.intensity, value: $setting.intensity, step: nil,
                           target: Self.intensityTarget(setting), text: ScanlinesSetting.percentText(setting.intensity))
        ScanlinesOrientationRow(isVertical: $setting.isVertical)
    }
}

/// A slider with its title and readout.
private struct ScanlinesSliderRow: View {
    let spec: AccessibleParameterSpec
    @Binding var value: Double
    let step: Double?
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
            slider
                .accessibleParameter(spec, target: target)
        }
    }

    @ViewBuilder private var slider: some View {
        if let step {
            Slider(value: $value, in: spec.range, step: step)
        } else {
            Slider(value: $value, in: spec.range)
        }
    }
}

/// Horizontal or Vertical lines.
private struct ScanlinesOrientationRow: View {
    @Binding var isVertical: Bool

    var body: some View {
        Picker("Orientation", selection: $isVertical) {
            Text("Horizontal").tag(false)
            Text("Vertical").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("scanlinesOrientationPicker")
    }
}
