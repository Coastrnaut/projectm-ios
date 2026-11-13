// PerformanceOverlay.swift — frame rate and audio state over the visualization (task T103; FR-048).
// Shown only when the setting is on (off by default). Updates once a second, matching the
// renderer's 1-second metrics window. VIS-001: the metrics are the shown visual's (projectM's
// renderer or the circular spectrum).
import CaptureKit
import CaptureUI
import Rendering
import SwiftUI

struct PerformanceOverlay: View {
    let metrics: () -> RenderMetrics
    let manager: CaptureManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let metrics = metrics()
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f fps", metrics.framesPerSecond))
                    .accessibilityIdentifier("overlayFPS")
                Text(String(format: "frame %.1f ms (max %.1f)", metrics.meanFrameTimeMs, metrics.maxFrameTimeMs))
                Text("audio: \(UIStrings.state(manager.state))")
                    .accessibilityIdentifier("overlayAudioState")
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
