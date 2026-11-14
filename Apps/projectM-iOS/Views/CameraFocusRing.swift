// CameraFocusRing.swift — focusing the camera where the user double-taps (CAM-005-R1, R5 to R7, R10;
// research CAM-005-D4, D5; contracts/focus-point.md C4).
//
// * `CameraFocusGesture` adds a double-tap (window coordinates) to the visualization's tap area only
//   while the Camera visual is shown. It is recognised alongside the single tap, so the single tap
//   keeps toggling the controls at once, with no wait for a second tap (R10); a double-tap's two
//   single taps toggle the controls twice, leaving them as they were. It also adds the VoiceOver
//   action "Focus at centre" while the camera can focus on a point (R7).
// * `CameraFocusFeedback` holds the ring (1 s at the touch) and the short explanation for a camera
//   that cannot focus on a point (2.5 s). `CameraFocusLayer` draws both above the visual, without
//   taking touches; the ring's fade goes through MotionPolicy (instant with Reduce Motion, R6).
// * Announcements go through the shared announcer on the camera lane. Nothing is stored (R9); the
//   touch location is used once.
// * `CameraFocusNote` is the one-line explanation in Settings › Camera.
import CameraLayer
import Observation
import SwiftUI

/// The ring and explanation after a focus tap (main thread; session state only).
@MainActor
@Observable
final class CameraFocusFeedback {
    /// Where the ring is (window coordinates) and a serial so a second tap restarts it.
    struct Ring: Equatable {
        let location: CGPoint
        let serial: Int
    }

    static let ringSeconds: Double = 1.0
    static let messageSeconds: Double = 2.5
    static let unsupportedText = "This camera can't focus on a point."
    static let centreText = "Focusing at centre"

    private(set) var ring: Ring?
    private(set) var message: String?
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private let schedule: @MainActor (Double, @escaping @MainActor () -> Void) -> Void

    init(schedule: @escaping @MainActor (Double, @escaping @MainActor () -> Void) -> Void = AccessibilityAnnouncer.sleepThen) {
        self.schedule = schedule
    }

    /// Shows the ring at `location` for `ringSeconds`.
    func showRing(at location: CGPoint) {
        serial += 1
        let current: Int = serial
        ring = Ring(location: location, serial: current)
        schedule(Self.ringSeconds) { [weak self] () -> Void in
            guard let self, self.ring?.serial == current else { return }
            self.ring = nil
        }
    }

    /// Shows `text` for `messageSeconds` (R5).
    func explain(_ text: String) {
        serial += 1
        let current: Int = serial
        message = text
        schedule(Self.messageSeconds) { [weak self] () -> Void in
            guard let self, self.serial == current else { return }
            self.message = nil
        }
    }

    func clear() {
        serial += 1
        ring = nil
        message = nil
    }
}

extension AppCoordinator {
    /// CAM-005-R1: the double-tap exists only while the Camera visual is on screen.
    var cameraFocusGestureEnabled: Bool { showsCameraVisual }

    /// CAM-005-R7: the VoiceOver action is offered only while the camera can focus on a point now.
    var cameraFocusActionAvailable: Bool { showsCameraVisual && cameraFocus.isAdjustable }

    /// CAM-005-R1, R2, R5, R6: a double-tap at `point` (window coordinates).
    func focusCamera(atWindowPoint point: CGPoint) {
        guard let host = cameraVisual else { return }
        let outcome: CameraFocusTapOutcome = host.focus(atWindowPoint: point)
        switch outcome {
        case .focused:
            cameraFocusFeedback.showRing(at: point)
        case .unsupported:
            explainCameraFocusLimit()
        case .outsidePicture, .notRunning:
            break   // Fit's bars, no picture yet, or the camera is not running: nothing happens
        }
    }

    /// CAM-005-R7: the VoiceOver action: focus at the centre of the picture on screen.
    func focusCameraAtCentre() {
        guard let host = cameraVisual else { return }
        switch host.focusAtCentre() {
        case .focused:
            let frame: CGRect = host.view.window == nil ? host.view.bounds : host.view.convert(host.view.bounds, to: nil)
            cameraFocusFeedback.showRing(at: CGPoint(x: frame.midX, y: frame.midY))
            announcer.announce(CameraFocusFeedback.centreText, kind: .camera)
        case .unsupported:
            explainCameraFocusLimit()
        case .outsidePicture, .notRunning:
            break
        }
    }

    private func explainCameraFocusLimit() {
        cameraFocusFeedback.explain(CameraFocusFeedback.unsupportedText)
        announcer.announce(CameraFocusFeedback.unsupportedText, kind: .camera)
    }

    /// DEBUG probe (`-uitestDiagnostics`): "x,y,mode" of the focus read back from the camera.
    var cameraFocusProbe: String {
        let state: CameraFocusState = cameraFocus
        let x: String = String(format: "%.3f", state.point.x)
        let y: String = String(format: "%.3f", state.point.y)
        return x + "," + y + "," + state.mode.rawValue
    }
}

/// The double-tap and the VoiceOver action on the visualization's tap area (CAM-005-R1, R7, R10).
/// Applied after the single tap, simultaneously with it (no delay for the controls toggle).
struct CameraFocusGesture: ViewModifier {
    let coordinator: AppCoordinator

    private var doubleTap: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .global).onEnded { (value: SpatialTapGesture.Value) -> Void in
            coordinator.focusCamera(atWindowPoint: value.location)
        }
    }

    func body(content: Content) -> some View {
        if coordinator.cameraFocusGestureEnabled {
            content
                .simultaneousGesture(doubleTap)
                .modifier(CameraFocusAction(coordinator: coordinator))
        } else {
            content
        }
    }
}

private struct CameraFocusAction: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        if coordinator.cameraFocusActionAvailable {
            content.accessibilityAction(named: Text("Focus at centre")) { () -> Void in coordinator.focusCameraAtCentre() }
        } else {
            content
        }
    }
}

/// The ring and the explanation above the visual (CAM-005-R5, R6); never takes touches.
struct CameraFocusLayer: View {
    let coordinator: AppCoordinator

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let origin: CGPoint = proxy.frame(in: .global).origin
            ZStack {
                ringView(origin: origin)
                messageView
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder private func ringView(origin: CGPoint) -> some View {
        let feedback: CameraFocusFeedback = coordinator.cameraFocusFeedback
        ZStack {
            if let ring = feedback.ring {
                Circle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: 64, height: 64)
                    .position(x: ring.location.x - origin.x, y: ring.location.y - origin.y)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("cameraFocusRing")
            }
        }
        .reduceMotionAware(.easeOut(duration: 0.2), value: feedback.ring, policy: coordinator.motion)   // R6
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
            Text(coordinator.cameraFocusProbe)
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("cameraFocusProbe")
                .accessibilityValue(coordinator.cameraFocusProbe)
        }
        #endif
    }

    @ViewBuilder private var messageView: some View {
        if let message = coordinator.cameraFocusFeedback.message {
            Text(message)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlaySurface(Capsule())   // ACC-008-R2
                .accessibilityIdentifier("cameraFocusMessage")
        }
    }
}

/// Settings › Camera: how to focus, or why this camera cannot (CAM-005-R5).
struct CameraFocusNote: View {
    let canFocus: Bool

    static func text(canFocus: Bool) -> String {
        canFocus ? "Double-tap the picture to focus there." : CameraFocusFeedback.unsupportedText
    }

    var body: some View {
        Text(Self.text(canFocus: canFocus))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("cameraFocusNote")
    }
}
