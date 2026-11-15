// CameraVisualHost+PersonMask.swift — the person mask on the Camera visual (CAM-008-R1, R4 to R6;
// research CAM-008-D1, D5, D6, D8; contracts/person-mask.md C2, C5).
//
// The host gives the camera layer one `PersonMasker` when it is made: the system's on-device person
// segmentation (Vision), or for UI tests with the stand-in camera (DEBUG) a fixture segmenter chosen by
// `-uitestPersonSegmenter fixture|unsupported|failing`. The masker's plan follows the device's heat and
// power (Low Power Mode or a PERF-008 profile below 60 fps) and is re-evaluated on the same
// notifications as the frame-rate governor. The choice reaches the layer from the next frame; nothing
// here starts the camera, and no mask is stored.
import CameraLayer
import Foundation
import ParameterGraph
import Rendering

extension CameraVisualHost {
    /// CAM-008-R1: Off, Person or Background, from the next frame.
    var personMask: CameraPersonMaskMode {
        get { camera.personMaskMode }
        set { camera.personMaskMode = newValue }
    }

    /// CAM-008-D5: whether masks can be drawn now.
    var personMaskAvailability: PersonMaskAvailability {
        camera.personMasker?.availability ?? .unsupported
    }

    /// CAM-008-R5: called on the main thread when the availability changes.
    var onPersonMaskAvailabilityChange: ((PersonMaskAvailability) -> Void)? {
        get { camera.personMasker?.onAvailabilityChange }
        set { camera.personMasker?.onAvailabilityChange = newValue }
    }

    /// CAM-008-D1, D8: the segmenter for this run.
    static func makePersonSegmenter(arguments: [String] = ProcessInfo.processInfo.arguments) -> any PersonSegmenting {
        #if DEBUG
        if let i = arguments.firstIndex(of: "-uitestPersonSegmenter"), i + 1 < arguments.count {
            // The stand-in camera's picture is 64 × 48; the fixture person is its middle half.
            let mask: PersonMaskBitmap? = PersonMaskBitmap.rectangle(width: 64, height: 48, x0: 16, y0: 12, x1: 48, y1: 36)
            switch arguments[i + 1] {
            case "unsupported": return FixturePersonSegmenter(mask: mask, supported: false)
            case "failing": return FixturePersonSegmenter(mask: mask, fails: true)
            default: return FixturePersonSegmenter(mask: mask)
            }
        }
        #endif
        return VisionPersonSegmenter()
    }

    /// CAM-008-R6 (research CAM-008-D6): heat and power → the masker's plan.
    static func personMaskPlan(thermal: ProcessInfo.ThermalState, lowPower: Bool, profile: PowerProfile) -> PersonMaskPlan {
        let level: PersonMaskThermal
        switch thermal {
        case .nominal: level = .nominal
        case .fair: level = .fair
        case .serious: level = .serious
        case .critical: level = .critical
        @unknown default: level = .serious
        }
        let reduced: Bool = lowPower || profile.budget(lowPower: lowPower).maxFramesPerSecond < 60
        return PersonMaskPolicy.plan(thermal: level, reducedPower: reduced)
    }

    /// Applies the current heat and power state to the masker (main thread).
    func updatePersonMaskPlan() {
        let info = ProcessInfo.processInfo
        let plan: PersonMaskPlan = Self.personMaskPlan(thermal: info.thermalState, lowPower: info.isLowPowerModeEnabled,
                                                       profile: PowerProfileState.current)
        camera.personMasker?.plan = plan
        (camera.provider.pictureAnalyzer as? FaceLandmarkAnalyzer)?.interval = Self.faceInterval(plan)   // CAM-009-R10
    }

    /// CAM-009-R10: the same heat and power state → the face analysis interval (paused when warm; 10 Hz when reduced).
    static func faceInterval(_ plan: PersonMaskPlan) -> UInt64? {
        switch plan {
        case .paused: return FaceTrackingRate.interval(warm: true, reducedPower: false)
        case let .run(quality, _): return FaceTrackingRate.interval(warm: false, reducedPower: quality == .fast)
        }
    }
}
