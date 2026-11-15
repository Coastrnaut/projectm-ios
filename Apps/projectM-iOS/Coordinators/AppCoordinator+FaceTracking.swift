// AppCoordinator+FaceTracking.swift — CAM-009: the face tracking coordinator and what the visualizer shows
// (specs/270-cam-009-face-landmark-emitters, research CAM-009-D3, D8).
//
// The coordinator is made once, with the analyzer for this run and the system camera permission. The Camera visual's
// provider offers its pictures to the analyzer (the gate decides whether any is analysed); a native spectrum reads
// the values for its `audio.face.*` bindings and triggers.
import Foundation

extension AppCoordinator {
    func makeFaceTracking(defaults: UserDefaults) -> FaceTrackingCoordinator {
        let coordinator = FaceTrackingCoordinator(defaults: defaults, analyzer: FaceTrackingCoordinator.makeAnalyzer(),
                                                  cameraPermission: { () -> Bool in FaceTrackingCoordinator.systemCameraPermission() })
        coordinator.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .parameter) }
        return coordinator
    }

    /// CAM-009-R13: the camera badge adds "Face tracking" while the camera runs and faces are analysed.
    var cameraFaceTrackingShown: Bool { cameraIndicator.isShown && faceTracking.isTracking }

    /// CAM-009-R13: the performance overlay's line while the Camera visual is shown: on or off, never a value.
    var faceTrackingOverlayLines: [String] {
        guard showsCameraVisual else { return [] }
        return [faceTracking.isTracking ? "Face tracking on" : "Face tracking off"]
    }
}
