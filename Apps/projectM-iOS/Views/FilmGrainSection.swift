// FilmGrainSection.swift — FX-017-R9: Settings → Film grain (specs/311-fx-017-film-grain, contracts/film-grain.md C4;
// ADR-0122).
//
// A toggle and, while on, an "Opacity" slider (0…100%, readout "30%") with ACC-005's `.accessibleParameter` (spoken
// "30 percent"; 1% per swipe), a Size picker (1, 2, 3 px), a Color picker (Monochrome, Color), a Seed stepper (0…9999)
// and a "Vary over time" toggle. The footer names the visuals and says what Reduce Motion and Reduce flashing do. Each
// row is its own small view (type-check budget).
import Compositor
import SwiftUI

/// ACC-005 spec of the slider (range from `FilmGrain`, the single source).
@MainActor
enum FilmGrainParameterSpecs {
    static let opacity = AccessibleParameterSpec(id: "filmGrainOpacitySlider", label: "Opacity",
                                                 range: FilmGrain.opacityRange, step: FilmGrain.opacityStep,
                                                 unit: .percent(decimals: 0))
}

struct FilmGrainSection: View {
    @Bindable var setting: FilmGrainSetting

    static let header = "Film grain"
    static let footer = "Adds an even film grain over the Camera, Photo, Video and Text visuals, on an external display, in recordings and in still captures. The grain never changes the picture's overall brightness, and at 0% the picture is unchanged. The same seed always gives the same grain. Vary over time changes the grain at most 24 times a second; with Reduce Motion or Reduce flashing on, the grain stays still."

    /// ACC-005: the real setting's write path (the view and tests use the same function).
    static func opacityTarget(_ setting: FilmGrainSetting) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in setting.opacity }, set: { (value: Double) -> Void in setting.opacity = value })
    }

    var body: some View {
        Section {
            Toggle(Self.header, isOn: $setting.isEnabled)
                .accessibilityIdentifier("filmGrainToggle")
            if setting.isEnabled { controls }
        } header: {
            Text(Self.header)
        } footer: {
            Text(Self.footer)
        }
    }

    @ViewBuilder private var controls: some View {
        FilmGrainSliderRow(spec: FilmGrainParameterSpecs.opacity, value: $setting.opacity,
                           target: Self.opacityTarget(setting), text: FilmGrainSetting.percentText(setting.opacity))
        FilmGrainSizePicker(size: $setting.size)
        FilmGrainColorPicker(isColor: $setting.isColor)
        FilmGrainSeedStepper(seed: $setting.seed)
        Toggle("Vary over time", isOn: $setting.isAnimated)
            .accessibilityIdentifier("filmGrainAnimated")
    }
}

/// A slider with its title and readout.
private struct FilmGrainSliderRow: View {
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

/// Grain size, 1-3 pixels.
private struct FilmGrainSizePicker: View {
    @Binding var size: Int

    var body: some View {
        Picker("Size", selection: $size) {
            ForEach(Array(FilmGrain.sizeRange), id: \.self) { (value: Int) in
                Text(FilmGrainSetting.sizeText(value)).tag(value)
            }
        }
        .accessibilityIdentifier("filmGrainSize")
    }
}

/// Monochrome or colour grain.
private struct FilmGrainColorPicker: View {
    @Binding var isColor: Bool

    var body: some View {
        Picker("Color", selection: $isColor) {
            Text("Monochrome").tag(false)
            Text("Color").tag(true)
        }
        .accessibilityIdentifier("filmGrainColor")
    }
}

/// The pattern seed.
private struct FilmGrainSeedStepper: View {
    @Binding var seed: Int

    var body: some View {
        let label: String = "Seed " + String(seed)
        Stepper(label, value: $seed, in: FilmGrain.seedRange)
            .accessibilityIdentifier("filmGrainSeed")
    }
}
