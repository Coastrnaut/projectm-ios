// PixelSortSection.swift — FX-011-R9: Settings → Pixel sort (specs/310-fx-011-pixel-sorting, contracts/pixel-sort.md
// C5; ADR-0121).
//
// A toggle and, while on, a "Threshold" slider (0…100%, readout "50%") with ACC-005's `.accessibleParameter` (spoken
// "50 percent"; 1% per swipe), a Span picker (4…64 px) and a Direction picker. The footer names the visuals and says
// what the controls do. Each row is its own small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 spec of the slider (range from `PixelSort`, the single source).
@MainActor
enum PixelSortParameterSpecs {
    static let threshold = AccessibleParameterSpec(id: "pixelSortThresholdSlider", label: "Threshold",
                                                   range: PixelSort.thresholdRange, step: PixelSort.thresholdStep,
                                                   unit: .percent(decimals: 0))
}

struct PixelSortSection: View {
    @Bindable var setting: PixelSortSetting

    static let header = "Pixel sort"
    static let footer = "Sorts bright runs of each row or column from dark to bright on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Pixels darker than the threshold stay where they are; a lower threshold sorts more of the picture. Span is the longest run sorted at once: longer spans make longer streaks. Very large displays may use a shorter span to stay within the frame budget. The effect can shimmer on busy content."

    /// ACC-005: the real setting's write path (the view and tests use the same function).
    static func thresholdTarget(_ setting: PixelSortSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.threshold }, set: { (value: Double) -> Void in setting.threshold = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("pixelSortToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        PixelSortSliderRow(spec: PixelSortParameterSpecs.threshold, value: $setting.threshold,
                           target: Self.thresholdTarget(setting), text: PixelSortSetting.thresholdText(setting.threshold))
        PixelSortSpanRow(span: $setting.span)
        PixelSortDirectionRow(direction: $setting.direction)
    }
}

/// A slider with its title and readout.
private struct PixelSortSliderRow: View {
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

/// 4, 8, 16, 32 or 64 px.
private struct PixelSortSpanRow: View {
    @Binding var span: Int

    var body: some View {
        Picker("Span", selection: $span) {
            ForEach(PixelSort.spans, id: \.self) { (s: Int) in
                Text(String(s) + " px").tag(s)
            }
        }
        .accessibilityIdentifier("pixelSortSpanPicker")
    }
}

/// Horizontal or vertical.
private struct PixelSortDirectionRow: View {
    @Binding var direction: PixelSort.Direction

    var body: some View {
        Picker("Direction", selection: $direction) {
            Text("Horizontal").tag(PixelSort.Direction.horizontal)
            Text("Vertical").tag(PixelSort.Direction.vertical)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("pixelSortDirectionPicker")
    }
}
