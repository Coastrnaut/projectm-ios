// CameraIndicator.swift — the in-app "Camera on" badge and its Stop camera button (CAM-012-R1 to R3,
// R9; spec 037, contracts/camera-privacy-status.md).
//
// * `CameraIndicator` is derived only from the camera feed state that the provider reports (research
//   CAM-012-D1): shown while the feed is starting or running, never from the visual choice, so it
//   disappears whenever the camera stops for any reason and returns only when it runs again.
// * `CameraIndicatorBadge` sits at the top of the visualizer, independent of the controls (it is never
//   auto-hidden). Its button calls the coordinator's `stopCamera()`.
import CameraLayer
import SwiftUI

/// Whether the in-app camera indicator is shown, and what VoiceOver reads (CAM-012-R1, R9).
struct CameraIndicator: Equatable {
    static let label = "Camera on"
    static let stopTitle = "Stop camera"
    static let stoppedAnnouncement = "Camera off"
    static let hidden = CameraIndicator(state: .idle)

    let isShown: Bool
    let accessibilityValue: String

    init(state: CameraFeedState) {
        isShown = state == .starting || state == .running
        accessibilityValue = state == .running ? "Live" : "Starting"
    }
}

/// The badge: camera symbol, "Camera on" and a Stop camera button (CAM-012-R3).
struct CameraIndicatorBadge: View {
    let indicator: CameraIndicator
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(CameraIndicator.label)
                    .font(.footnote.weight(.semibold))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CameraIndicator.label)
            .accessibilityValue(indicator.accessibilityValue)
            .accessibilityIdentifier("cameraIndicatorStatus")
            Button(action: onStop) {
                Label(CameraIndicator.stopTitle, systemImage: "stop.fill")
                    .font(.footnote.bold())
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .accessibilityLabel(CameraIndicator.stopTitle)
            .accessibilityIdentifier("stopCamera")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cameraIndicator")
    }
}
