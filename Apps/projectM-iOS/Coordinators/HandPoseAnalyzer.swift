// HandPoseAnalyzer.swift — CAM-010: the opt-in, on-device hand pose analysis of the Camera visual's own pictures
// (CAM-010-R1, R4, R6, R10, R11; research CAM-010-D1, D3; contract hand-sources H3, H5; ADR-0087).
//
// * `HandPoseDetecting` finds up to two hands in one picture and returns only seven joints each (`HandPoseFrame`).
//   `VisionHandPoseDetector` uses Vision's hand pose on the device; it creates its request lazily, on its first
//   detection. `StubHandPoseDetector` stands in for the simulator and UI tests; `RecordedHandPoseDetector` replays a
//   recorded pose sequence on an injected clock (the acceptance tests feed it instead of Vision).
// * `HandPoseAnalyzer` is the shared `CameraFeatureAnalyzer` over `HandFeatureTracker`: the consent gate first, a lazy
//   detector, 15 Hz, one in flight on its own queue, results dropped after switching off.
// * Nothing here writes a file, logs a value or uses the network.
import CameraLayer
import CoreVideo
import Foundation
import ImageIO
import os
import ParameterGraph
import Vision

/// Finds up to two hands in one picture (contract H3). Called on the analyzer's queue only.
protocol HandPoseDetecting: AnyObject {
    /// The hands' joints, or nil when no hand is seen.
    func detect(_ pixels: CVPixelBuffer, rotation: CameraRotation) throws -> HandPoseFrame?
}

/// Vision's on-device hand pose (research CAM-010-D1).
final class VisionHandPoseDetector: HandPoseDetecting {
    private var request: VNDetectHumanHandPoseRequest?

    /// The iOS Simulator cannot run Vision's hand pose model reliably; the app treats hand tracking as unavailable there.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    func detect(_ pixels: CVPixelBuffer, rotation: CameraRotation) throws -> HandPoseFrame? {
        let made: VNDetectHumanHandPoseRequest = request ?? Self.makeRequest()
        request = made
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: VisionFaceLandmarkDetector.orientation(rotation),
                                            options: [:])
        try handler.perform([made])
        let hands: [VNHumanHandPoseObservation] = made.results ?? []
        guard !hands.isEmpty else { return nil }
        let samples: [HandObservationSample] = hands.prefix(2).map { (hand: VNHumanHandPoseObservation) -> HandObservationSample in
            Self.sample(hand)
        }
        return HandPoseFrame(hands: samples, aspect: Self.uprightAspect(pixels, rotation: rotation))
    }

    private static func makeRequest() -> VNDetectHumanHandPoseRequest {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }

    /// The upright picture's width ÷ height (a quarter turn swaps the sides).
    static func uprightAspect(_ pixels: CVPixelBuffer, rotation: CameraRotation) -> Double {
        let width = Double(CVPixelBufferGetWidth(pixels)), height = Double(CVPixelBufferGetHeight(pixels))
        guard width > 0, height > 0 else { return 1 }
        switch rotation {
        case .none, .clockwise180: return width / height
        case .clockwise90, .clockwise270: return height / width
        }
    }

    /// Copies only the seven joints; the observation is dropped afterwards.
    static func sample(_ hand: VNHumanHandPoseObservation) -> HandObservationSample {
        HandObservationSample(wrist: point(hand, .wrist), thumbTip: point(hand, .thumbTip), indexTip: point(hand, .indexTip),
                              middleTip: point(hand, .middleTip), ringTip: point(hand, .ringTip),
                              littleTip: point(hand, .littleTip), middleKnuckle: point(hand, .middleMCP))
    }

    private static func point(_ hand: VNHumanHandPoseObservation, _ joint: VNHumanHandPoseObservation.JointName) -> HandJointPoint {
        guard let found = try? hand.recognizedPoint(joint) else { return .missing }
        return HandJointPoint(x: Double(found.location.x), y: Double(found.location.y), confidence: Double(found.confidence))
    }
}

/// A stand-in detector: a fixed pose, no hand, or failing. Counts detections (tests, DEBUG).
final class StubHandPoseDetector: HandPoseDetecting {
    private let frame: HandPoseFrame?
    private let fails: Bool
    private let counter = OSAllocatedUnfairLock(initialState: 0)

    init(frame: HandPoseFrame?, fails: Bool = false) {
        self.frame = frame
        self.fails = fails
    }

    var detections: Int { counter.withLock { $0 } }

    func detect(_ pixels: CVPixelBuffer, rotation: CameraRotation) throws -> HandPoseFrame? {
        counter.withLock { $0 += 1 }
        if fails { throw HandPoseError.injected }
        return frame
    }

    /// A centred open hand pinching (DEBUG `-uitestHandDetector stub`).
    static let pinchingHand = HandPoseFrame(hands: [HandObservationSample(
        wrist: HandJointPoint(x: 0.5, y: 0.3, confidence: 0.9), thumbTip: HandJointPoint(x: 0.47, y: 0.5, confidence: 0.9),
        indexTip: HandJointPoint(x: 0.47, y: 0.5, confidence: 0.9), middleTip: HandJointPoint(x: 0.5, y: 0.59, confidence: 0.9),
        ringTip: HandJointPoint(x: 0.55, y: 0.58, confidence: 0.9), littleTip: HandJointPoint(x: 0.65, y: 0.52, confidence: 0.9),
        middleKnuckle: HandJointPoint(x: 0.5, y: 0.45, confidence: 0.9))])
}

/// Replays a recorded pose sequence (contract H3): each detection returns the segment in force at the clock's time.
final class RecordedHandPoseDetector: HandPoseDetecting, Sendable {
    struct Segment: Sendable {
        let startNanoseconds: UInt64
        let frame: HandPoseFrame?
    }

    private let segments: [Segment]
    private let clock: @Sendable () -> UInt64

    init(segments: [Segment], clock: @escaping @Sendable () -> UInt64) {
        self.segments = segments
        self.clock = clock
    }

    func detect(_ pixels: CVPixelBuffer, rotation: CameraRotation) throws -> HandPoseFrame? {
        let now: UInt64 = clock()
        var current: HandPoseFrame?
        for segment in segments where segment.startNanoseconds <= now { current = segment.frame }
        return current
    }
}

enum HandPoseError: Error, Equatable {
    case injected
}

/// CAM-010's analyzer: the shared camera feature analyzer over the hand tracker (research CAM-010-D3).
typealias HandPoseAnalyzer = CameraFeatureAnalyzer<HandFeatureTracker>

extension CameraFeatureAnalyzer where Tracker == HandFeatureTracker {
    /// `makeDetector` is called at most once per analyzer, inside the first analysis after the gate opened.
    convenience init(supported: Bool, makeDetector: @escaping @Sendable () -> any HandPoseDetecting, runner: Runner? = nil,
                     clock: (@Sendable () -> UInt64)? = nil) {
        self.init(supported: supported, queueLabel: "org.projectmios.camera.handPose",
                  makeDetect: { () -> Detect in
                      let detector: any HandPoseDetecting = makeDetector()
                      return { (pixels: CVPixelBuffer, rotation: CameraRotation) throws -> HandPoseFrame? in
                          try detector.detect(pixels, rotation: rotation)
                      }
                  },
                  runner: runner, clock: clock)
    }
}
