// PaletteGradientStops.swift — SHD-005-R4, R7 (specs/236-shd-005-gradient-editor, contract G4): the gradient editor
// inside the palette editor. For a gradient-style user palette: an Interpolation picker (Smooth, sRGB, Step) and,
// per stop, a heading "Stop i of n, <colour name>" with a Position and an Alpha slider (ACC-005 `.accessibleParameter`,
// 1 % steps, spoken as percent). A position is clamped between its neighbours by the library. Every edit is a library
// edit saved at once (UIX-011), not a scene edit. Bodies are split into small properties (type-check budget).
import SceneFormat
import SwiftUI

struct PaletteGradientStopsSection: View {
    let palettes: PaletteCoordinator
    let id: String
    let palette: ColorPalette

    var body: some View {
        Section {
            interpolationPicker
            ForEach(Array(palette.colors.indices), id: \.self) { (index: Int) in
                PaletteStopRow(palettes: palettes, id: id, index: index, palette: palette)
            }
        } header: {
            Text("Gradient Stops")
        } footer: {
            Text("Move a stop between its neighbours and set how opaque it is. Lower alpha fades the colour toward the background.")
        }
    }

    private var interpolationPicker: some View {
        Picker("Interpolation", selection: interpolationBinding) {
            ForEach(PaletteInterpolation.allCases, id: \.self) { (mode: PaletteInterpolation) in Text(mode.title).tag(mode) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("paletteInterpolationPicker")
    }

    private var interpolationBinding: Binding<PaletteInterpolation> {
        let palettes: PaletteCoordinator = self.palettes
        let id: String = self.id
        let current: PaletteInterpolation = palette.interpolation
        return Binding(get: { () -> PaletteInterpolation in current },
                       set: { (mode: PaletteInterpolation) -> Void in palettes.setInterpolation(id, mode) })
    }
}

/// One stop: its heading and its Position and Alpha sliders.
struct PaletteStopRow: View {
    let palettes: PaletteCoordinator
    let id: String
    let index: Int
    let palette: ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
            PaletteStopSlider(palettes: palettes, id: id, index: index, field: .position)
            PaletteStopSlider(palettes: palettes, id: id, index: index, field: .alpha)
        }
    }

    private var heading: some View {
        HStack(spacing: 8) {
            palette.colors[index].swiftUIColor
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(title).font(.subheadline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityIdentifier("paletteStop\(index + 1).heading")
    }

    private var title: String {
        let name: String = palette.colors[index].name
        return "Stop \(index + 1) of \(palette.colors.count), \(name)"
    }
}

enum PaletteStopField: String {
    case position, alpha

    var title: String { self == .position ? "Position" : "Alpha" }
}

/// A stop's Position or Alpha: a read-out over an ACC-005 slider.
struct PaletteStopSlider: View {
    let palettes: PaletteCoordinator
    let id: String
    let index: Int
    let field: PaletteStopField

    static let step = 0.01

    private var spec: AccessibleParameterSpec {
        AccessibleParameterSpec(id: "paletteStop\(index + 1).\(field.rawValue)", label: "Stop \(index + 1) \(field.title)",
                                range: 0...1, step: Self.step, unit: .percent(decimals: 0))
    }

    /// The stored value as a fraction 0…1.
    static func value(_ palette: ColorPalette?, index: Int, field: PaletteStopField) -> Double {
        guard let palette else { return 0 }
        switch field {
        case .position:
            let positions: [Int] = palette.stopPositions
            return positions.indices.contains(index) ? Double(positions[index]) / Double(ColorPalette.maximumPosition) : 0
        case .alpha:
            let alphas: [Int] = palette.stopAlphas
            return alphas.indices.contains(index) ? Double(alphas[index]) / Double(ColorPalette.maximumAlpha) : 1
        }
    }

    private var target: ParameterTarget {
        let palettes: PaletteCoordinator = self.palettes
        let id: String = self.id
        let index: Int = self.index
        let field: PaletteStopField = self.field
        return ParameterTarget(get: { () -> Double in
            Self.value(palettes.library.palette(id), index: index, field: field)
        }, set: { (value: Double) -> Void in
            if field == .position {
                palettes.setStopPosition(id, at: index, to: value)
            } else {
                palettes.setStopAlpha(id, at: index, to: value)
            }
        })
    }

    private var binding: Binding<Double> {
        let target: ParameterTarget = self.target
        return Binding<Double>(get: { () -> Double in target.get() }, set: { (v: Double) -> Void in target.set(v) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            readout
            Slider(value: binding, in: 0...1, step: Self.step)
                .accessibleParameter(spec, target: target)
        }
    }

    private var readout: some View {
        HStack {
            Text(field.title)
            Spacer(minLength: 8)
            Text(SpokenValueFormatter.text(target.get(), unit: .percent(decimals: 0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .accessibilityHidden(true)
    }
}
