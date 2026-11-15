// EdgeOutlineSection.swift — FX-014-R9: Settings → Edge outline (specs/303-fx-014-edge-outline, contracts/edge-outline.md
// C4; ADR-0114).
//
// A toggle and, while on, a "Threshold" slider (0.02…1, readout "0.20") with ACC-005's `.accessibleParameter` (spoken
// "0.20"; one hundredth per swipe), a Width choice (1, 2 or 3 px), a Mode choice (Overlay, Outline only) and a colour
// well without opacity. The footer names the visuals. Each row is its own small view (type-check budget).
import Compositor
import SwiftUI
import UIKit

/// ACC-005 spec of the slider (range from `EdgeOutline`, the single source).
@MainActor
enum EdgeOutlineParameterSpecs {
    static let threshold = AccessibleParameterSpec(id: "edgeOutlineThresholdSlider", label: "Threshold",
                                                   range: EdgeOutline.thresholdRange, step: 0.01, unit: .number(decimals: 2))
}

struct EdgeOutlineSection: View {
    @Bindable var setting: EdgeOutlineSetting

    static let header = "Edge outline"
    static let footer = "Draws the edges of the picture in a colour on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Threshold sets how strong an edge must be; flat areas are never outlined."

    /// ACC-005: the real setting's write path (the view and tests use the same function).
    static func thresholdTarget(_ setting: EdgeOutlineSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.thresholdValue },
                        set: { (value: Double) -> Void in setting.thresholdValue = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("edgeOutlineToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        EdgeOutlineThresholdRow(value: $setting.thresholdValue, target: Self.thresholdTarget(setting),
                                text: EdgeOutlineSetting.thresholdText(setting.threshold))
        EdgeOutlineWidthRow(width: $setting.width)
        EdgeOutlineModeRow(mode: $setting.mode)
        EdgeOutlineColorRow(setting: setting)
    }
}

/// The threshold slider with its title and readout.
private struct EdgeOutlineThresholdRow: View {
    @Binding var value: Double
    let target: ParameterTarget
    let text: String

    var body: some View {
        let spec: AccessibleParameterSpec = EdgeOutlineParameterSpecs.threshold
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(spec.label)
                Spacer()
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(spec.id + "Value")
            }
            .accessibilityElement(children: .contain)
            Slider(value: $value, in: spec.range, step: 0.01)
                .accessibleParameter(spec, target: target)
        }
    }
}

/// 1, 2 or 3 px.
private struct EdgeOutlineWidthRow: View {
    @Binding var width: Int

    var body: some View {
        Picker("Width", selection: $width) {
            Text("1 px").tag(1)
            Text("2 px").tag(2)
            Text("3 px").tag(3)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("edgeOutlineWidthPicker")
    }
}

/// Overlay or Outline only.
private struct EdgeOutlineModeRow: View {
    @Binding var mode: EdgeOutlineMode

    var body: some View {
        Picker("Mode", selection: $mode) {
            Text("Overlay").tag(EdgeOutlineMode.overlay)
            Text("Outline only").tag(EdgeOutlineMode.outlineOnly)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("edgeOutlineModePicker")
    }
}

/// The outline colour (sRGB, opaque).
private struct EdgeOutlineColorRow: View {
    let setting: EdgeOutlineSetting

    var body: some View {
        ColorPicker("Colour", selection: binding, supportsOpacity: false)
            .accessibilityIdentifier("edgeOutlineColor")
    }

    private var binding: Binding<Color> {
        let target: EdgeOutlineSetting = setting
        return Binding<Color>(get: { () -> Color in Self.color(target.color) },
                              set: { (picked: Color) -> Void in target.color = Self.components(picked) })
    }

    static func color(_ c: EdgeOutlineColor) -> Color {
        Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// The picked colour's sRGB components, clamped to 0…1 (extended sRGB values outside are clipped).
    static func components(_ picked: Color) -> EdgeOutlineColor {
        var r: CGFloat = 1
        var g: CGFloat = 1
        var b: CGFloat = 1
        var a: CGFloat = 1
        _ = UIColor(picked).getRed(&r, green: &g, blue: &b, alpha: &a)
        return EdgeOutlineColor(red: Double(r), green: Double(g), blue: Double(b))
    }
}
