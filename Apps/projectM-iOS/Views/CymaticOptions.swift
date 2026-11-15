// CymaticOptions.swift — VIS-019-R10, R13: the cymatic lines' Settings row (Bands: All/Low/Mid/High) and a short
// description, shown under the Visual list when Cymatic Lines is chosen. Its own view so SettingsView's body (and its
// shared help text) stays untouched.
import SwiftUI
import VisualGenerators

struct CymaticOptions: View {
    @Bindable var settings: AppSettings

    static let help = "Cymatic Lines draws the still lines of a vibrating plate: the loudest sound within the chosen Bands picks the figure, so a steady tone keeps one figure and a different pitch draws another; louder sound brightens the lines. In silence it glides back to a plain cross within about a second (two with Reduce Motion, which also halves how fast the figures blend)."

    var body: some View {
        Picker("Bands", selection: $settings.cymaticBands) {
            ForEach(CymaticBandRange.allCases, id: \.self) { (range: CymaticBandRange) in
                Text(range.title).tag(range)
            }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Bands")
        .accessibilityIdentifier("cymaticBandsPicker")
        Text(Self.help)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("cymaticHelp")
    }
}
