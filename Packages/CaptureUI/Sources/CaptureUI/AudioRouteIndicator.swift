// AudioRouteIndicator.swift — the compact audio route indicator (AUD-007-T10; AUD-007-R4-R6):
// "Output: AirPods Pro" while In-App Playback runs, "Input: iPhone Microphone" in Microphone mode.
// One accessibility element, labelled "Audio output: …" / "Audio input: …"; the icon is decorative.
#if canImport(SwiftUI)
import CaptureKit
import SwiftUI

public struct AudioRouteIndicator: View {
    let route: AudioRoute
    let context: AudioRouteContext

    public init(route: AudioRoute, context: AudioRouteContext) {
        self.route = route
        self.context = context
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: UIStrings.routeSymbol(route, context: context))
                .accessibilityHidden(true)
            Text(UIStrings.routeIndicator(route, context: context))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UIStrings.routeAccessibilityLabel(route, context: context))
        .accessibilityIdentifier("routeIndicator")
    }
}
#endif
