// CameraFeatureAnalyzer.swift — the opt-in, on-device analysis of the Camera visual's own pictures, shared by face
// tracking (CAM-009) and hand tracking (CAM-010) (CAM-009-R1, R2, R4, R10, R11; CAM-010-R1, R2, R4, R10, R11; research
// CAM-009-D1 to D4, CAM-010-D2 to D4; ADR-0081, ADR-0087).
//
// * `CameraFeatureAnalyzer<Tracker>` is one `CameraPictureAnalyzing`. While disabled (its consent gate is closed) an
//   offer returns at once: no schedule step, no detector, no work. Enabled, an offer starts an analysis only when the
//   schedule allows (15 Hz, one in flight) on its own utility serial queue. The detector is made by the injected factory
//   inside the first analysis, so with the gate closed the factory is never called. The picture is released when the
//   analysis returns. Disabling or `reset()` bumps the generation (a result in flight is dropped) and returns the values
//   to neutral. A detector error stops analysis for this camera run (`failed`), as CAM-008 does.
// * `Tracker` turns one detection into smoothed 0…1 values (`FaceFeatureTracker`, `HandFeatureTracker`).
// * `CameraAnalysisConsent` is the switch, consent and explanation-sheet model both features store (research
//   CAM-010-D4); `CameraAnalysisStatus` what their rows say.
// * Nothing here writes a file, logs a value or uses the network. Values live in memory under one lock.
import CameraLayer
import CoreVideo
import Dispatch
import Foundation
import os
import ParameterGraph

/// Smooths one feature's detections into values (one owner: the analyzer, under its lock).
protocol CameraFeatureTracking: AnyObject {
    associatedtype Sample
    associatedtype Values: Equatable & Sendable
    static var neutralValues: Values { get }
    init()
    var values: Values { get }
    func reset()
    func ingest(_ sample: Sample?, mirrored: Bool, timeNanoseconds: UInt64)
}

extension FaceFeatureTracker: CameraFeatureTracking {
    static var neutralValues: FaceFeatureValues { .neutral }
}

extension HandFeatureTracker: CameraFeatureTracking {
    static var neutralValues: HandFeatureValues { .neutral }
}

/// Whether values can be produced now.
enum CameraFeatureAvailability: Equatable, Sendable {
    case available
    /// Detection cannot run on this device (or the simulator), or it failed during this camera run.
    case unavailable
}

/// A picture handed to the analysis queue (CoreVideo buffers are safe to read from another thread).
private struct OfferedPicture: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let rotation: CameraRotation
    let generation: UInt64
    let mirrored: Bool
}

final class CameraFeatureAnalyzer<Tracker: CameraFeatureTracking>: CameraPictureAnalyzing, @unchecked Sendable {
    typealias Runner = @Sendable (@escaping @Sendable () -> Void) -> Void
    /// One detection on the analyzer's queue: the sample, or nil when nothing is seen.
    typealias Detect = (CVPixelBuffer, CameraRotation) throws -> Tracker.Sample?
    typealias DetectFactory = @Sendable () -> Detect

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
        var detect: Detect?
        let tracker = Tracker()
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let runner: Runner
    private let makeDetect: DetectFactory
    private let clock: @Sendable () -> UInt64
    /// Main thread: called when `availability` changes.
    var onAvailabilityChange: (@MainActor (CameraFeatureAvailability) -> Void)?

    /// `makeDetect` is called at most once per analyzer, inside the first analysis after the gate opened.
    init(supported: Bool, queueLabel: String, makeDetect: @escaping DetectFactory, runner: Runner? = nil,
         clock: (@Sendable () -> UInt64)? = nil) {
        lock = OSAllocatedUnfairLock(uncheckedState: State(supported: supported))
        self.makeDetect = makeDetect
        self.clock = clock ?? { () -> UInt64 in DispatchTime.now().uptimeNanoseconds }
        if let runner {
            self.runner = runner
        } else {
            let queue = DispatchQueue(label: queueLabel, qos: .utility)
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

    /// The shown picture is mirrored (x follows it). Main thread.
    var mirrored: Bool {
        get { lock.withLockUnchecked { $0.mirrored } }
        set { lock.withLockUnchecked { $0.mirrored = newValue } }
    }

    /// The analysis interval; nil pauses (main thread).
    var interval: UInt64? {
        get { lock.withLockUnchecked { $0.schedule.intervalNanoseconds } }
        set { lock.withLockUnchecked { $0.schedule.setInterval(newValue) } }
    }

    var availability: CameraFeatureAvailability {
        lock.withLockUnchecked { (s: inout State) -> CameraFeatureAvailability in s.supported && !s.failed ? .available : .unavailable }
    }

    /// Analyses started and detectors made so far (tests).
    var analysesStarted: Int { lock.withLockUnchecked { $0.started } }
    var detectorsMade: Int { lock.withLockUnchecked { $0.detectorsMade } }

    /// The current values (neutral while disabled). Any thread; a struct copy.
    var values: Tracker.Values {
        lock.withLockUnchecked { (s: inout State) -> Tracker.Values in s.enabled ? s.tracker.values : Tracker.neutralValues }
    }

    /// True while enabled and able to analyse.
    var isActive: Bool {
        lock.withLockUnchecked { (s: inout State) -> Bool in s.enabled && s.supported && !s.failed }
    }

    // MARK: CameraPictureAnalyzing

    func offer(_ pixels: CVPixelBuffer, rotation: CameraRotation, position: CameraPosition) {
        let now: UInt64 = clock()
        let job: OfferedPicture? = lock.withLockUnchecked { (s: inout State) -> OfferedPicture? in
            guard s.enabled, s.supported, !s.failed else { return nil }   // the gate first, before anything
            if s.position != position {   // a camera switch starts from neutral
                if s.position != nil { s.tracker.reset() }
                s.position = position
            }
            guard s.schedule.offer(at: now) else { return nil }
            s.started += 1
            return OfferedPicture(pixels: pixels, rotation: rotation, generation: s.generation, mirrored: s.mirrored)
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

    private func analyse(_ job: OfferedPicture) {
        let detect: Detect? = lock.withLockUnchecked { (s: inout State) -> Detect? in
            guard s.enabled, job.generation == s.generation else { return nil }   // switched off meanwhile: no request
            if s.detect == nil {
                s.detect = makeDetect()
                s.detectorsMade += 1
            }
            return s.detect
        }
        guard let detect else {
            lock.withLockUnchecked { $0.schedule.finish() }
            return
        }
        let result: Result<Tracker.Sample?, Error> = Result { () throws -> Tracker.Sample? in
            try detect(job.pixels, job.rotation)
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

    private func report(_ availability: CameraFeatureAvailability) {
        DispatchQueue.main.async { [self] () -> Void in
            MainActor.assumeIsolated { onAvailabilityChange?(availability) }
        }
    }
}

/// The analysis interval setter the Camera visual's heat and power plan reaches through the analysis slot.
protocol CameraAnalysisRateControlled: AnyObject {
    var interval: UInt64? { get set }
}

extension CameraFeatureAnalyzer: CameraAnalysisRateControlled {}

/// What a camera analysis row says (CAM-009-R5, CAM-010-R5).
enum CameraAnalysisStatus: Equatable {
    case off
    case needsCamera
    case unavailable
    case ready

    init(isOn: Bool, cameraAuthorized: Bool, availability: CameraFeatureAvailability) {
        if !isOn {
            self = .off
        } else if !cameraAuthorized {
            self = .needsCamera
        } else {
            self = availability == .available ? .ready : .unavailable
        }
    }
}

/// The switch, its stored consent and the explanation sheet of one camera analysis feature (research CAM-010-D4).
/// Turning the switch on without consent shows the sheet; only Confirm stores consent and turns it on; Cancel leaves
/// it off; turning it off keeps consent. Both keys stay on this device (excluded from backups, erased with Settings).
struct CameraAnalysisConsent: Equatable {
    let switchKey: String
    let consentKey: String
    private(set) var isOn: Bool
    private(set) var hasConsent: Bool
    var sheetShown = false

    init(defaults: UserDefaults, switchKey: String, consentKey: String) {
        self.switchKey = switchKey
        self.consentKey = consentKey
        hasConsent = defaults.bool(forKey: consentKey)
        isOn = defaults.bool(forKey: consentKey) && defaults.bool(forKey: switchKey)
    }

    var allKeys: [String] { [switchKey, consentKey] }

    /// The switch's request: true when it turned on now; false when it turned off or the sheet is shown instead.
    mutating func request(_ on: Bool, defaults: UserDefaults) -> Bool {
        guard on else {
            isOn = false
            defaults.set(false, forKey: switchKey)
            return false
        }
        guard hasConsent else {
            sheetShown = true   // nothing analysed until Confirm
            return false
        }
        turnOn(defaults: defaults)
        return true
    }

    /// The sheet's Confirm: consent is stored, then the switch turns on.
    mutating func confirm(defaults: UserDefaults) {
        hasConsent = true
        defaults.set(true, forKey: consentKey)
        sheetShown = false
        turnOn(defaults: defaults)
    }

    /// The sheet's Cancel (or dismissal): the switch stays off.
    mutating func cancel() {
        sheetShown = false
    }

    private mutating func turnOn(defaults: UserDefaults) {
        isOn = true
        defaults.set(true, forKey: switchKey)
    }
}
