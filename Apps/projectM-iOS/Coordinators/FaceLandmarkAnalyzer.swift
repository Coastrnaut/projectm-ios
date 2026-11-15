// FaceLandmarkAnalyzer.swift — CAM-009: the opt-in, on-device face analysis of the Camera visual's own pictures
// (CAM-009-R1, R2, R4, R6, R10, R11; research CAM-009-D1 to D4, D7; contract face-sources F3 to F5; ADR-0081).
//
// * `FaceLandmarkDetecting` finds the largest face in one picture and returns only its scalars
//   (`FaceObservationSample`). `VisionFaceLandmarkDetector` uses Vision's face landmarks on the device; it creates its
//   request lazily, on its first detection. `StubFaceLandmarkDetector` stands in for tests and the simulator.
// * `FaceLandmarkAnalyzer` is the shared `CameraFeatureAnalyzer` (CameraFeatureAnalyzer.swift, CAM-010-D3) over the
//   face tracker: the consent gate first, a lazy detector, 15 Hz, one in flight, results dropped after switching off.
// * Nothing here writes a file, logs a value or uses the network. Values live in memory under one lock.
import CameraLayer
import CoreVideo
import Foundation
import ImageIO
import os
import ParameterGraph
import Vision

/// Finds the largest face in one picture (contract F3). Called on the analyzer's queue only.
protocol FaceLandmarkDetecting: AnyObject {
    /// The largest face's scalars, or nil when no face is seen.
    func detect(_ pixels: CVPixelBuffer, rotation: CameraRotation) throws -> FaceObservationSample?
}

/// Vision's on-device face landmarks (research CAM-009-D1).
final class VisionFaceLandmarkDetector: FaceLandmarkDetecting {
    private var request: VNDetectFaceLandmarksRequest?

    /// The iOS Simulator cannot run Vision's face models reliably; the app treats face tracking as unavailable there.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    func detect(_ pixels: CVPixelBuffer, rotation: CameraRotation) throws -> FaceObservationSample? {
        let made: VNDetectFaceLandmarksRequest = request ?? VNDetectFaceLandmarksRequest()
        request = made
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: Self.orientation(rotation), options: [:])
        try handler.perform([made])
        let faces: [VNFaceObservation] = made.results ?? []
        let largest: VNFaceObservation? = faces.max { (a: VNFaceObservation, b: VNFaceObservation) -> Bool in
            a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
        }
        guard let face = largest else { return nil }
        return Self.sample(face)
    }

    /// The clockwise turn that shows the picture upright, as EXIF orientation (as CAM-008-D2).
    static func orientation(_ rotation: CameraRotation) -> CGImagePropertyOrientation {
        switch rotation {
        case .none: return .up
        case .clockwise90: return .right
        case .clockwise180: return .down
        case .clockwise270: return .left
        }
    }

    /// Copies only the scalars and the three regions' points; the observation is dropped afterwards.
    static func sample(_ face: VNFaceObservation) -> FaceObservationSample {
        let box: CGRect = face.boundingBox
        return FaceObservationSample(boxX: Double(box.minX), boxY: Double(box.minY), boxWidth: Double(box.width),
                                     boxHeight: Double(box.height), roll: face.roll.map { (n: NSNumber) -> Double in n.doubleValue },
                                     yaw: face.yaw.map { (n: NSNumber) -> Double in n.doubleValue },
                                     innerLips: points(face.landmarks?.innerLips), leftEye: points(face.landmarks?.leftEye),
                                     rightEye: points(face.landmarks?.rightEye))
    }

    private static func points(_ region: VNFaceLandmarkRegion2D?) -> [FacePoint] {
        guard let region else { return [] }
        return region.normalizedPoints.map { (p: CGPoint) -> FacePoint in FacePoint(x: Double(p.x), y: Double(p.y)) }
    }
}

/// A stand-in detector: a fixed face, no face, or failing. Counts detections (tests).
final class StubFaceLandmarkDetector: FaceLandmarkDetecting {
    private let sample: FaceObservationSample?
    private let fails: Bool
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    init(sample: FaceObservationSample?, fails: Bool = false) {
        self.sample = sample
        self.fails = fails
    }

    var detections: Int { counter.withLock { $0 } }

    func detect(_ pixels: CVPixelBuffer, rotation: CameraRotation) throws -> FaceObservationSample? {
        counter.withLock { $0 += 1 }
        if fails { throw FaceLandmarkError.injected }
        return sample
    }

    /// A centred face with a half-open mouth (DEBUG `-uitestFaceDetector stub`).
    static let centredFace = FaceObservationSample(
        boxX: 0.35, boxY: 0.35, boxWidth: 0.3, boxHeight: 0.3, roll: 0, yaw: 0,
        innerLips: [FacePoint(x: 0.4, y: 0.25), FacePoint(x: 0.6, y: 0.35)],
        leftEye: [FacePoint(x: 0.2, y: 0.7), FacePoint(x: 0.4, y: 0.76)],
        rightEye: [FacePoint(x: 0.6, y: 0.7), FacePoint(x: 0.8, y: 0.76)])
}

enum FaceLandmarkError: Error, Equatable {
    case injected
}

/// Whether face values can be produced now (CAM-010 shares the type with hand tracking).
typealias FaceAnalysisAvailability = CameraFeatureAvailability

/// CAM-009's analyzer is the shared camera feature analyzer over the face tracker (research CAM-010-D3).
typealias FaceLandmarkAnalyzer = CameraFeatureAnalyzer<FaceFeatureTracker>

extension CameraFeatureAnalyzer where Tracker == FaceFeatureTracker {
    /// `makeDetector` is called at most once per analyzer, inside the first analysis after the gate opened.
    convenience init(supported: Bool, makeDetector: @escaping @Sendable () -> any FaceLandmarkDetecting, runner: Runner? = nil,
                     clock: (@Sendable () -> UInt64)? = nil) {
        self.init(supported: supported, queueLabel: "org.projectmios.camera.faceLandmarks",
                  makeDetect: { () -> Detect in
                      let detector: any FaceLandmarkDetecting = makeDetector()
                      return { (pixels: CVPixelBuffer, rotation: CameraRotation) throws -> FaceObservationSample? in
                          try detector.detect(pixels, rotation: rotation)
                      }
                  },
                  runner: runner, clock: clock)
    }
}
