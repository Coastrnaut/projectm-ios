// SignedDistanceOptions.swift — VIS-017-R8, R11: the SDF shapes' Settings row (Quality: Low/Medium/High), shown under the
// Visual list when SDF Shapes is chosen. Its own view so SettingsView's body stays small.
import SwiftUI
import VisualGenerators

struct SignedDistanceOptions: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Picker("Quality", selection: $settings.signedDistanceQuality) {
            ForEach(SignedDistanceQuality.allCases, id: \.self) { (quality: SignedDistanceQuality) in
                Text(quality.title).tag(quality)
            }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Quality")
        .accessibilityIdentifier("signedDistanceQualityPicker")
    }
}
