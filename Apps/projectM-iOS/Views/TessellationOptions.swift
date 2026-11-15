// TessellationOptions.swift — VIS-018-R10, R13: the tessellation's Settings rows (Tiling, Tiles, Symmetry, Mirror,
// Palette), shown under the Visual list when Tessellation is chosen. Its own view, split into small properties, so
// SettingsView's body and the type-check budget stay small.
import SwiftUI
import VisualGenerators

struct TessellationOptions: View {
    @Bindable var settings: AppSettings

    var body: some View {
        tilingPicker
        tilesStepper
        symmetryPicker
        mirrorToggle
        palettePicker
    }

    private var tilingPicker: some View {
        Picker("Tiling", selection: $settings.tessellation.tiling) {
            ForEach(TessellationTiling.allCases, id: \.self) { (tiling: TessellationTiling) in
                Text(tiling.title).tag(tiling)
            }
        }
        .accessibilityIdentifier("tessellationTilingPicker")
    }

    private var tilesStepper: some View {
        Stepper(value: $settings.tessellation.tiles, in: TessellationSettings.tileRange) {
            Text("Tiles: \(settings.tessellation.tiles)")
        }
        .accessibilityLabel("Tiles")
        .accessibilityValue("\(settings.tessellation.tiles)")
        .accessibilityIdentifier("tessellationTilesStepper")
    }

    private var symmetryPicker: some View {
        Picker("Symmetry", selection: $settings.tessellation.symmetry) {
            ForEach(TessellationSettings.symmetries, id: \.self) { (order: Int) in
                Text(order == 1 ? "Off" : "\(order)").tag(order)
            }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Symmetry")
        .accessibilityIdentifier("tessellationSymmetryPicker")
    }

    private var mirrorToggle: some View {
        Toggle("Mirror", isOn: $settings.tessellation.mirror)
            .accessibilityIdentifier("tessellationMirrorToggle")
    }

    private var palettePicker: some View {
        Picker("Palette", selection: $settings.tessellation.palette) {
            ForEach(TessellationPalette.allCases, id: \.self) { (palette: TessellationPalette) in
                Text(palette.title).tag(palette)
            }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Palette")
        .accessibilityIdentifier("tessellationPalettePicker")
        .disabled(settings.colorBlindSafePalette)   // ACC-003-R13 wins
    }
}
