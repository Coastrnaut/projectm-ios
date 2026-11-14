// UITestCameraEventPanel.swift — camera event injection for CameraRecoveryUITests (CAM-013-R13;
// contracts/camera-recovery.md C5). DEBUG builds only, and only with `-uitestCameraEvents` next to
// `-uitestCamera <scenario>` (the stand-in camera). Release builds contain none of this.
//
// Each button calls the stand-in's own injection (`interrupt`, `endInterruption`, `fail`,
// `withdrawAccess`): the app's handling is real, the event is simulated. The hidden value
// `cameraRecovery` is the host's recovery probe (state, reason, attempts, pending, counts).
#if DEBUG
import CameraLayer
import SwiftUI

struct UITestCameraEventPanel: View {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestCameraEvents") }

    let coordinator: AppCoordinator

    private var stub: StubCameraFrameProvider? {
        coordinator.cameraVisual?.camera.provider as? StubCameraFrameProvider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                ForEach(CameraStopReason.allCases.filter { (reason: CameraStopReason) -> Bool in reason.isInterruption },
                        id: \.self) { (reason: CameraStopReason) in
                    button(String(reason.rawValue.prefix(5)), id: "camera:interrupt:\(reason.rawValue)") { stub?.interrupt(reason) }
                }
            }
            HStack(spacing: 2) {
                button("end", id: "camera:end") { stub?.endInterruption() }
                button("error", id: "camera:fail:runtimeError") { stub?.fail(.runtimeError) }
                button("reset", id: "camera:fail:mediaServicesReset") { stub?.fail(.mediaServicesReset) }
                button("deny", id: "camera:withdraw") { stub?.withdrawAccess() }
            }
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let probe: String = coordinator.cameraVisual?.recoveryProbe ?? "none"
                Text(probe)
                    .font(.caption2)
                    .opacity(0.01)
                    .accessibilityIdentifier("cameraRecovery")
                    .accessibilityValue(probe)
            }
        }
        .padding(4)
        .background(.black.opacity(0.6))
    }

    /// A short title (the panel fits a phone's width) and the identifier the UI test taps.
    private func button(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .accessibilityIdentifier(id)
            .font(.system(size: 8))
            .buttonStyle(.bordered)
    }
}
#endif
