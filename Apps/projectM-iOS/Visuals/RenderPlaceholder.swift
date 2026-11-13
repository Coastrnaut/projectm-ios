// RenderPlaceholder.swift — the safe placeholder for a visual that can show nothing (PERF-014-R10;
// research PERF-014-D7; Clarifications Q2).
//
// Black with a small grey "Visual unavailable" note, over the visual while its render health state is
// `placeholder`. It fades in and out linearly over 0.5 s, so each switch is one monotonic luminance
// change (a fade to black is the safest FX-019 transition; 0.5 s is slower than the Reduce-flashing
// rise limit). Only a reset (the user changes or resumes the visual, the app returns) can remove it.
import SwiftUI

enum RenderPlaceholder {
    static let fadeSeconds = 0.5
    static let note = "Visual unavailable"

    /// The overlay's opacity `elapsed` seconds into a fade-in (linear, clamped to 0…1).
    static func opacity(elapsed: Double) -> Double {
        guard elapsed.isFinite else { return elapsed > 0 ? 1 : 0 }
        return min(max(elapsed / fadeSeconds, 0), 1)
    }
}

struct RenderPlaceholderView: View {
    let shown: Bool

    var body: some View {
        ZStack {
            Color.black
            Text(RenderPlaceholder.note)
                .font(.footnote)
                .foregroundStyle(Color(white: 0.55))
        }
        .ignoresSafeArea()
        .opacity(shown ? 1 : 0)
        // ACC-001-R4: a safety fade, kept with Reduce Motion on.
        .animation(MotionPolicy.safetyFade(.linear(duration: RenderPlaceholder.fadeSeconds)), value: shown)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RenderPlaceholder.note)
        .accessibilityIdentifier("renderPlaceholder")
        .accessibilityHidden(!shown)
    }
}
