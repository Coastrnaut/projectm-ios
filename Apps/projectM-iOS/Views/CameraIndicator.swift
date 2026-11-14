// CameraIndicator.swift — the in-app "Camera on" badge and its Stop camera button (CAM-012-R1 to R3,
// R9; spec 037, contracts/camera-privacy-status.md).
//
// * `CameraIndicator` is derived only from the camera feed state that the provider reports (research
//   CAM-012-D1): shown while the feed is starting or running, never from the visual choice, so it
//   disappears whenever the camera stops for any reason and returns only when it runs again.
// * ACC-003-R4: the badge's symbol differs for starting and live (and with Differentiate Without
//   Colour, "Starting" / "Live" follows the label); an opaque background with Increase Contrast.
// * `CameraIndicatorBadge` sits at the top of the visualizer, independent of the controls (it is never
//   auto-hidden). Its button calls the coordinator's `stopCamera()`.
import CameraLayer
import SwiftUI

/// Whether the in-app camera indicator is shown, and what VoiceOver reads (CAM-012-R1, R9).
struct CameraIndicator: Equatable {
    static let label = "Camera on"
    /// CAM-002-R8: the badge names the front camera.
    static let frontLabel = "Front camera on"
    static let stopTitle = "Stop camera"
    static let stoppedAnnouncement = "Camera off"
    static let hidden = CameraIndicator(state: .idle)

    let isShown: Bool
    /// Pictures are arriving (ACC-003-R4: the live symbol).
    let isRunning: Bool
    let accessibilityValue: String
    /// "Camera on", or "Front camera on" for the front camera (CAM-002-R8).
    let label: String

    init(state: CameraFeedState, position: CameraPosition = .back) {
        isShown = state == .starting || state == .running
        isRunning = state == .running
        accessibilityValue = state == .running ? "Live" : "Starting"
        label = position == .front ? Self.frontLabel : Self.label
    }
}

/// The badge: camera symbol, "Camera on" and a Stop camera button (CAM-012-R3).
struct CameraIndicatorBadge: View {
    let indicator: CameraIndicator
    let onStop: () -> Void
    @Environment(\.statusAppearance) private var appearance

    var body: some View {
        // ACC-003-R4: starting and live differ in shape; with Differentiate Without Colour also in words.
        let cue: StatusCue = StatusCueCatalog.camera(running: indicator.isRunning, label: indicator.label,
                                                     differentiateWithoutColor: appearance.differentiateWithoutColor)
        HStack(spacing: 8) {
            StatusCueLabel(cue: cue)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(indicator.label)
                .accessibilityValue(indicator.accessibilityValue)
                .accessibilityIdentifier("cameraIndicatorStatus")
            Button(action: onStop) {
                Label(CameraIndicator.stopTitle, systemImage: "stop.fill")
                    .font(.footnote.bold())
            }
            // ACC-008-R5: white on a dark red fill (6:1); red text on a red-tinted bordered fill was about 3:1.
            .buttonStyle(.borderedProminent)
            .tint(OverlayContrast.criticalFill)
            .controlSize(.small)
            .accessibilityLabel(CameraIndicator.stopTitle)
            .accessibilityIdentifier("stopCamera")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .statusBadgeBackground(Capsule())   // ACC-003-R9
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cameraIndicator")
    }
}
