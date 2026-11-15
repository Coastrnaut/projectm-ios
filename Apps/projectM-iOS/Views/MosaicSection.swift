// MosaicSection.swift — FX-012-R8: Settings → Mosaic (specs/299-fx-012-mosaic-pixelation, contracts/mosaic.md C4;
// ADR-0110).
//
// A toggle and, while on, a "Block size" slider (1…64 pixels, readout "8 px") with ACC-005's `.accessibleParameter`
// (spoken "8"; one pixel per swipe) and a Square/Hexagon choice. The footer names the visuals. Each row is its own small
// view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 spec of the slider (range from `Mosaic`, the single source).
@MainActor
enum MosaicParameterSpecs {
    static let size = AccessibleParameterSpec(id: "mosaicSizeSlider", label: "Block size",
                                              range: Double(Mosaic.sizeRange.lowerBound)...Double(Mosaic.sizeRange.upperBound),
                                              step: 1, unit: .number(decimals: 0))
}

struct MosaicSection: View {
    @Bindable var setting: MosaicSetting

    static let header = "Mosaic"
    static let footer = "Turns the picture into flat-coloured squares or hexagons on the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. Block size is in pixels of the picture; 1 px is the original picture."

    /// ACC-005: the real setting's write path (the view and tests use the same function).
    static func sizeTarget(_ setting: MosaicSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.blockSizeValue }, set: { (value: Double) -> Void in setting.blockSizeValue = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("mosaicToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        MosaicSizeRow(value: $setting.blockSizeValue, target: Self.sizeTarget(setting),
                      text: MosaicSetting.sizeText(setting.blockSize))
        MosaicShapeRow(shape: $setting.shape)
    }
}

/// The block size slider with its title and readout.
private struct MosaicSizeRow: View {
    @Binding var value: Double
    let target: ParameterTarget
    let text: String

    var body: some View {
        let spec: AccessibleParameterSpec = MosaicParameterSpecs.size
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
            Slider(value: $value, in: spec.range, step: 1)
                .accessibleParameter(spec, target: target)
        }
    }
}

/// Square or Hexagon.
private struct MosaicShapeRow: View {
    @Binding var shape: MosaicShape

    var body: some View {
        Picker("Shape", selection: $shape) {
            Text("Square").tag(MosaicShape.square)
            Text("Hexagon").tag(MosaicShape.hexagon)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("mosaicShapePicker")
    }
}
