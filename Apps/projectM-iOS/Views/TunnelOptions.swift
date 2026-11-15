// TunnelOptions.swift — VIS-015-R9, R12: the tunnel's Settings row (Pace: rings per beat), shown under the Visual list
// when Tunnel is chosen. Its own view so SettingsView's body stays small. Segments read "½ ring", "1 ring", "2 rings"
// (per beat); the visual's accessibility value spells the pace out.
import SwiftUI
import VisualGenerators

struct TunnelOptions: View {
    @Bindable var settings: AppSettings

    /// The segment's text.
    static func segmentTitle(_ pace: TunnelPace) -> String {
        switch pace {
        case .half: "½ ring"
        case .beat: "1 ring"
        case .double: "2 rings"
        }
    }

    var body: some View {
        Picker("Rings per beat", selection: $settings.tunnelPace) {
            ForEach(TunnelPace.allCases, id: \.self) { (pace: TunnelPace) in Text(Self.segmentTitle(pace)).tag(pace) }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Rings per beat")
        .accessibilityIdentifier("tunnelPacePicker")
    }
}
