// PerformanceOverlay.swift — frame rate and audio state over the visualization (task T103; FR-048).
// Shown only when the setting is on (off by default). Updates once a second, matching the
// renderer's 1-second metrics window. VIS-001: the metrics are the shown visual's (projectM's
// renderer or the circular spectrum). PERF-014-R14: a "render:" line with the shown visual's render
// health while anything was recorded (state, last reason, counts).
import CaptureKit
import CaptureUI
import Rendering
import SwiftUI

struct PerformanceOverlay: View {
    let metrics: () -> RenderMetrics
    let manager: CaptureManager
    /// PERF-014: nil while the shown visual's record is pristine.
    var renderHealth: () -> String? = { nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let metrics = metrics()
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f fps", metrics.framesPerSecond))
                    .accessibilityIdentifier("overlayFPS")
                Text(String(format: "frame %.1f ms (max %.1f)", metrics.meanFrameTimeMs, metrics.maxFrameTimeMs))
                Text("audio: \(UIStrings.state(manager.state))")
                    .accessibilityIdentifier("overlayAudioState")
                if let render = renderHealth() {
                    Text("render: \(render)")
                        .accessibilityIdentifier("overlayRender")
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("performanceOverlay")
        }
        .allowsHitTesting(false)
    }
}
