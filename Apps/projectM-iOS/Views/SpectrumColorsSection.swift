// SpectrumColorsSection.swift — ACC-003-R13 (specs/110-acc-003-color-blind-friendly-controls; contract
// status-cues.md C5): the native spectra's opt-in colour-blind-safe palette. A view of its own so
// SettingsView's body stays small (CI's Xcode 26 type-check budget). Shown for the native spectra only.
import SwiftUI

struct SpectrumColorsSection: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            Toggle("Color-blind-safe colors", isOn: $settings.colorBlindSafePalette)
                .accessibilityIdentifier("colorBlindSafePaletteToggle")
        } footer: {
            Text("Draws the bars from blue-gray to yellow, each brighter than the one before, instead of the rainbow.")
        }
    }
}
