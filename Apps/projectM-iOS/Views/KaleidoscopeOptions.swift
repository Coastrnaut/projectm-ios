// KaleidoscopeOptions.swift — VIS-014-R4, R9: the kaleidoscope's Settings row (Wedges, 2…24), shown under the Visual
// list when Kaleidoscope is chosen. Its own view so SettingsView's body stays small.
import SwiftUI
import VisualGenerators

struct KaleidoscopeOptions: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Stepper(value: $settings.kaleidoscopeWedges, in: KaleidoscopeFold.wedgeRange) {
            Text("Wedges: \(settings.kaleidoscopeWedges)")
        }
        .accessibilityLabel("Wedges")
        .accessibilityValue("\(settings.kaleidoscopeWedges)")
        .accessibilityIdentifier("kaleidoscopeWedgesStepper")
    }
}
