// FaceLandmarkAnalyzer.swift — CAM-009: the opt-in, on-device face analysis of the Camera visual's own pictures
// (CAM-009-R1, R2, R4, R6, R10, R11; research CAM-009-D1 to D4, D7; contract face-sources F3 to F5; ADR-0081).
//
// * `FaceLandmarkDetecting` finds the largest face in one picture and returns only its scalars
//   (`FaceObservationSample`). `VisionFaceLandmarkDetector` uses Vision's face landmarks on the device; it creates its
//   request lazily, on its first detection. `StubFaceLandmarkDetector` stands in for tests and the simulator.
// * `FaceLandmarkAnalyzer` is the camera's `CameraPictureAnalyzing`. While disabled (the consent gate is closed) an
//   offer returns at once: no schedule step, no detector, no work. Enabled, an offer starts an analysis only when the
//   schedule allows (15 Hz, one in flight) on a utility serial queue. The detector is made by the injected factory
//   inside the first analysis, so with the gate closed the factory is never called. The picture is released when the
//   analysis returns. Disabling or `reset()` bumps the generation (a result in flight is dropped) and returns the
//   values to neutral. A detector error stops analysis for this analyzer's camera run (`failed`), as CAM-008 does.
// * Nothing here writes a file, logs a value or uses the network. Values live in memory under one lock.
import CameraLayer
import CoreVideo
import Dispatch
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

/// Whether face values can be produced now.
enum FaceAnalysisAvailability: Equatable, Sendable {
    case available
    /// Face detection cannot run on this device (or the simulator), or it failed during this camera run.
    case unavailable
}

/// A picture handed to the analysis queue (CoreVideo buffers are safe to read from another thread).
private struct OfferedFacePicture: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let rotation: CameraRotation
    let generation: UInt64
    let mirrored: Bool
}

final class FaceLandmarkAnalyzer: CameraPictureAnalyzing, @unchecked Sendable {
    typealias Runner = @Sendable (@escaping @Sendable () -> Void) -> Void
    typealias DetectorFactory = @Sendable () -> any FaceLandmarkDetecting

    private struct State {
        var enabled = false
        var supported: Bool
        var failed = false
        var mirrored = false
        var position: CameraPosition?
        var schedule = FaceAnalysisSchedule(intervalNanoseconds: FaceTrackingRate.normalInterval)
        var generation: UInt64 = 0
        var started = 0
        var detectorsMade = 0
        var detector: (any FaceLandmarkDetecting)?
        let tracker = FaceFeatureTracker()
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let runner: Runner
    private let makeDetector: DetectorFactory
    private let clock: @Sendable () -> UInt64
    /// Main thread: called when `availability` changes.
    var onAvailabilityChange: (@MainActor (FaceAnalysisAvailability) -> Void)?

    /// `makeDetector` is called at most once per analyzer, inside the first analysis after the gate opened.
    init(supported: Bool, makeDetector: @escaping DetectorFactory, runner: Runner? = nil,
         clock: (@Sendable () -> UInt64)? = nil) {
        lock = OSAllocatedUnfairLock(uncheckedState: State(supported: supported))
        self.makeDetector = makeDetector
        self.clock = clock ?? { () -> UInt64 in DispatchTime.now().uptimeNanoseconds }
        if let runner {
            self.runner = runner
        } else {
            let queue = DispatchQueue(label: "org.projectmios.camera.faceLandmarks", qos: .utility)
            self.runner = { (job: @escaping @Sendable () -> Void) -> Void in queue.async(execute: job) }
        }
    }

    /// The consent gate's answer (main thread). Turning off drops any result in flight and resets the values.
    var isEnabled: Bool {
        get { lock.withLockUnchecked { $0.enabled } }
        set {
            lock.withLockUnchecked { (s: inout State) -> Void in
                guard s.enabled != newValue else { return }
                s.enabled = newValue
                guard !newValue else { return }
                s.generation &+= 1
                s.schedule.reset()
                s.tracker.reset()
            }
        }
    }

    /// The shown picture is mirrored (x and roll follow it). Main thread.
    var mirrored: Bool {
        get { lock.withLockUnchecked { $0.mirrored } }
        set { lock.withLockUnchecked { $0.mirrored = newValue } }
    }

    /// CAM-009-R10: the analysis interval; nil pauses (main thread).
    var interval: UInt64? {
        get { lock.withLockUnchecked { $0.schedule.intervalNanoseconds } }
        set { lock.withLockUnchecked { $0.schedule.setInterval(newValue) } }
    }

    var availability: FaceAnalysisAvailability {
        lock.withLockUnchecked { (s: inout State) -> FaceAnalysisAvailability in s.supported && !s.failed ? .available : .unavailable }
    }

    /// Analyses started and detectors made so far (tests).
    var analysesStarted: Int { lock.withLockUnchecked { $0.started } }
    var detectorsMade: Int { lock.withLockUnchecked { $0.detectorsMade } }

    /// The current values (neutral while disabled). Any thread; a struct copy.
    var values: FaceFeatureValues {
        lock.withLockUnchecked { (s: inout State) -> FaceFeatureValues in s.enabled ? s.tracker.values : .neutral }
    }

    /// True while enabled and able to analyse (the badge and the overlay say "Face tracking").
    var isActive: Bool {
        lock.withLockUnchecked { (s: inout State) -> Bool in s.enabled && s.supported && !s.failed }
    }

    // MARK: CameraPictureAnalyzing

    func offer(_ pixels: CVPixelBuffer, rotation: CameraRotation, position: CameraPosition) {
        let now: UInt64 = clock()
        let job: OfferedFacePicture? = lock.withLockUnchecked { (s: inout State) -> OfferedFacePicture? in
            guard s.enabled, s.supported, !s.failed else { return nil }   // CAM-009-R1: the gate first, before anything
            if s.position != position {   // a camera switch starts from neutral
                if s.position != nil { s.tracker.reset() }
                s.position = position
            }
            guard s.schedule.offer(at: now) else { return nil }
            s.started += 1
            return OfferedFacePicture(pixels: pixels, rotation: rotation, generation: s.generation, mirrored: s.mirrored)
        }
        guard let job else { return }
        runner { [self] () -> Void in analyse(job) }
    }

    /// The camera stopped or switched: values back to neutral; a result in flight is dropped. A failure is forgotten,
    /// so the next camera run tries again.
    func reset() {
        let recovered: Bool = lock.withLockUnchecked { (s: inout State) -> Bool in
            s.generation &+= 1
            s.schedule.reset()
            s.tracker.reset()
            s.position = nil
            defer { s.failed = false }
            return s.failed && s.supported
        }
        if recovered { report(.available) }
    }

    private func analyse(_ job: OfferedFacePicture) {
        let detector: (any FaceLandmarkDetecting)? = lock.withLockUnchecked { (s: inout State) -> (any FaceLandmarkDetecting)? in
            guard s.enabled, job.generation == s.generation else { return nil }   // switched off meanwhile: no request
            if s.detector == nil {
                s.detector = makeDetector()
                s.detectorsMade += 1
            }
            return s.detector
        }
        guard let detector else {
            lock.withLockUnchecked { $0.schedule.finish() }
            return
        }
        let result: Result<FaceObservationSample?, Error> = Result { () throws -> FaceObservationSample? in
            try detector.detect(job.pixels, rotation: job.rotation)
        }
        let now: UInt64 = clock()
        let failedNow: Bool = lock.withLockUnchecked { (s: inout State) -> Bool in
            s.schedule.finish()
            switch result {
            case let .success(sample):
                guard s.enabled, job.generation == s.generation else { return false }
                s.tracker.ingest(sample, mirrored: job.mirrored, timeNanoseconds: now)
                return false
            case .failure:
                guard !s.failed else { return false }
                s.failed = true
                s.tracker.reset()
                return true
            }
        }
        if failedNow { report(.unavailable) }
    }

    private func report(_ availability: FaceAnalysisAvailability) {
        DispatchQueue.main.async { [self] () -> Void in
            MainActor.assumeIsolated { onAvailabilityChange?(availability) }
        }
    }
}
