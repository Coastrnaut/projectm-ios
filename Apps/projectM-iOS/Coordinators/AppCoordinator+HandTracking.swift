// AppCoordinator+HandTracking.swift — CAM-010: the hand tracking coordinator, the camera's analysis group, the Camera
// visual's modulation and what the visualizer shows (specs/276-cam-010-hand-pose-modulation, research CAM-010-D2, D7).
//
// The Camera visual's provider offers its pictures to one `CameraPictureAnalyzerGroup` of the face and hand analyzers;
// each gate decides whether any picture is analysed. The Camera visual evaluates the scene's bindings for its ring
// with both feature sets; native visuals read them for their own bindings and triggers.
import CameraLayer
import Foundation
import ParameterGraph
import VisualParameters

extension AppCoordinator {
    func makeHandTracking(defaults: UserDefaults) -> HandTrackingCoordinator {
        let coordinator = HandTrackingCoordinator(defaults: defaults, analyzer: HandTrackingCoordinator.makeAnalyzer(),
                                                  cameraPermission: { () -> Bool in FaceTrackingCoordinator.systemCameraPermission() })
        coordinator.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .parameter) }
        return coordinator
    }

    /// CAM-009, CAM-010: the Camera visual's pictures go to the face and hand analyzers (one slot, no second session),
    /// at the heat and power plan's rate; its ring follows the scene's bindings.
    func connectCameraAnalysis(_ host: CameraVisualHost) {
        faceTracking.connect(camera: host)
        handTracking.connect(camera: host)
        host.camera.provider.pictureAnalyzer = CameraPictureAnalyzerGroup([faceTracking.analyzer, handTracking.analyzer])
        host.updatePersonMaskPlan()   // also sets both analysis rates (R10)
        let face: FaceLandmarkAnalyzer = faceTracking.analyzer
        let hand: HandPoseAnalyzer = handTracking.analyzer
        host.modulation.faceValues = { () -> FaceFeatureValues in face.values }
        host.modulation.handValues = { () -> HandFeatureValues in hand.values }
        host.modulation.load(sceneAutosave?.bindings ?? [])   // SCN-002: the scene's routes, as the native visual
        #if DEBUG
        bindCameraRadiusToPinchIfRequested(host)
        #endif
    }

    /// The mirror both analyzers follow (x is measured in the shown picture).
    func mirrorCameraAnalysis(_ mirrored: Bool) {
        faceTracking.analyzer.mirrored = mirrored
        handTracking.analyzer.mirrored = mirrored
    }

    /// CAM-010-R13: the camera badge adds "Hand tracking" while the camera runs and hands are analysed.
    var cameraHandTrackingShown: Bool { cameraIndicator.isShown && handTracking.isTracking }

    /// CAM-010-R13: the performance overlay's line while the Camera visual is shown: on or off, never a value.
    var handTrackingOverlayLines: [String] {
        guard showsCameraVisual else { return [] }
        return [handTracking.isTracking ? "Hand tracking on" : "Hand tracking off"]
    }

    #if DEBUG
    /// Launch argument for the device check CAM-010-T17: bind Pinch to the Camera visual's ring inner radius.
    static let bindCameraRadiusToPinchArgument = "-uitestBindCameraRadiusToPinch"

    private func bindCameraRadiusToPinchIfRequested(_ host: CameraVisualHost) {
        guard ProcessInfo.processInfo.arguments.contains(Self.bindCameraRadiusToPinchArgument) else { return }
        host.modulation.load(host.modulation.bindings + [AudioFeatureBinding(source: .hand(.pinch),
                                                                             target: VisualParameterIDs.circularSpectrumInnerRadius,
                                                                             outputStart: 0.2, outputEnd: 0.6)])
    }
    #endif
}
