// MotionModulationCoordinator.swift — CAM-011-R5, R8, R9, R11, R12, R14 (specs/247-cam-011-motion-sensor-modulation,
// research CAM-011-D5, D6, D9; contract motion-sources M5, M8, M9).
//
// * Demand (R8): the sensor runs only while motion is available, the app is active, and something reads motion: the
//   shown visual has a motion binding or trigger (`hostUsesMotion`, reported by `NativeSpectrumHost`) or Settings ›
//   Motion is on screen (`readoutOpen`). Every change re-evaluates; a stop keeps the tracker's last values and a start
//   restarts its unwrapping (the first sample re-anchors and snaps).
// * Rate (R9): 60 Hz, 30 Hz while the power budget (PERF-008, Low Power Mode) caps frames at 30.
// * The tracker's values are read by the host once per evaluated frame (`currentValues`, no observation); the Settings
//   readout (`readout`) is refreshed at most 10 times a second (R14).
// * Calibrate (R5) takes the current attitude as neutral and announces "Motion calibrated" (the `.parameter` lane).
// * One preference (R12): `settings.motion.range` (`narrow`, `medium`, `wide`; absent or unknown → medium), written on
//   change only; FILE-005 included key, erased with Settings (FILE-011), `ALLOWED_KEYS`, removed by
//   `-uitestResetNotice`. Calibration and readings are memory only (R10).
import Foundation
import Observation
import ParameterGraph
import Rendering

@MainActor
@Observable
final class MotionModulationCoordinator {
    static let rangeKey = "settings.motion.range"
    static let allKeys: [String] = [rangeKey]
    static let sectionTitle = "Motion"
    static let footer = "Tilt and shake can drive settings in scenes that use them. Calibrate takes how you hold the device now as the middle. Motion is read only while it is used and the app is open, and never leaves this device."
    static let unavailableNote = "Motion sensors are not available on this device."
    static let calibratedAnnouncement = "Motion calibrated"
    /// The full and the reduced sensor rate (R9).
    static let fullRateHz = 60.0
    static let reducedRateHz = 30.0
    /// The readout refresh interval (R14): at most 10 per second.
    static let readoutIntervalNanoseconds: UInt64 = 100_000_000

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sampler: any MotionSampling
    @ObservationIgnored private let frameCap: @MainActor () -> Int
    @ObservationIgnored let tracker: MotionTracker
    @ObservationIgnored private var lastReadoutTime: UInt64?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Posts an announcement (the app wires ACC-004's announcer).
    @ObservationIgnored var announce: (@MainActor (String) -> Void)?

    var range: MotionRange {
        didSet {
            guard range != oldValue else { return }
            defaults.set(range.rawValue, forKey: Self.rangeKey)
            tracker.range = range
        }
    }

    /// The device has motion sensors (or the DEBUG stand-in).
    let isAvailable: Bool
    /// The values shown in Settings, refreshed at most 10 times a second while sampling.
    private(set) var readout: MotionFeatureValues = .neutral
    /// True while the sensor runs.
    private(set) var isSampling = false
    /// The rate the sensor runs at (0 while stopped).
    private(set) var rateHz: Double = 0

    @ObservationIgnored private(set) var appActive = true
    @ObservationIgnored private(set) var hostUsesMotion = false
    @ObservationIgnored private(set) var readoutOpen = false
    /// The host whose bindings decide `hostUsesMotion`; weak, so a released host stops the sensor at the next sample.
    @ObservationIgnored private weak var host: NativeSpectrumHost?

    init(defaults: UserDefaults, sampler: any MotionSampling,
         frameCap: @escaping @MainActor () -> Int = MotionModulationCoordinator.systemFrameCap) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.rangeKey)   // the UI-test reset: Medium
        }
        self.defaults = defaults
        self.sampler = sampler
        self.frameCap = frameCap
        let stored = MotionRange(stored: defaults.string(forKey: Self.rangeKey))
        range = stored
        tracker = MotionTracker(range: stored)
        isAvailable = sampler.isAvailable
    }

    /// The app's sampler: the stand-in under `-uitestMotionStandIn` (DEBUG), else CoreMotion.
    static func systemSampler() -> any MotionSampling {
        #if DEBUG
        if StandInMotionSampler.isRequested { return StandInMotionSampler() }
        #endif
        return CoreMotionSampler()
    }

    /// The power budget's frame cap with the system's Low Power Mode state (PERF-008).
    static func systemFrameCap() -> Int {
        PowerProfileState.budget(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled).maxFramesPerSecond
    }

    /// Follows power profile and Low Power Mode changes (the app's coordinator only; tests call `update()`).
    func observePowerChanges() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [PowerProfileState.didChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] (_: Notification) -> Void in
                MainActor.assumeIsolated { self?.update() }
            })
        }
    }

    // MARK: Demand (R8)

    /// Connects a newly created host: it reads the tracker's values and reports its motion demand.
    func connect(_ host: NativeSpectrumHost) {
        self.host = host
        host.motionValues = { [weak self] () -> MotionFeatureValues in self?.currentValues ?? .neutral }
        host.onMotionDemandChange = { [weak self] (uses: Bool) -> Void in self?.setHostUsesMotion(uses) }
        hostUsesMotion = host.usesMotion
        update()
    }

    func setHostUsesMotion(_ uses: Bool) {
        hostUsesMotion = uses
        update()
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        update()
    }

    func setReadoutOpen(_ open: Bool) {
        readoutOpen = open
        update()
    }

    /// The values a frame reads (neutral without motion).
    var currentValues: MotionFeatureValues { isAvailable ? tracker.values : .neutral }

    /// Whether the sensor should run now.
    var wantsSampling: Bool {
        let hostDemand: Bool = hostUsesMotion && (host?.usesMotion ?? false)
        return isAvailable && appActive && (hostDemand || readoutOpen)
    }

    /// The rate for the current power budget.
    var desiredRateHz: Double { frameCap() <= 30 ? Self.reducedRateHz : Self.fullRateHz }

    /// Starts, stops or re-rates the sensor to match the demand.
    func update() {
        guard wantsSampling else {
            if isSampling {
                sampler.stop()
                isSampling = false
                rateHz = 0
            }
            return
        }
        let rate: Double = desiredRateHz
        guard !isSampling || rate != rateHz else { return }
        if !isSampling { tracker.restart() }
        isSampling = true
        rateHz = rate
        sampler.start(rateHz: rate) { [weak self] (sample: MotionSample) -> Void in self?.receive(sample) }
    }

    /// One sample: re-checks demand (a released host stops the sensor here), feeds the tracker, refreshes the readout.
    func receive(_ sample: MotionSample) {
        guard isSampling else { return }
        guard wantsSampling else {
            update()
            return
        }
        tracker.ingest(sample)
        let due: Bool = lastReadoutTime.map { (last: UInt64) -> Bool in
            sample.timeNanoseconds < last || sample.timeNanoseconds - last >= Self.readoutIntervalNanoseconds
        } ?? true
        if readoutOpen, due {
            readout = tracker.values
            lastReadoutTime = sample.timeNanoseconds
        }
    }

    // MARK: Calibration (R5)

    /// Takes the current attitude as neutral; every attitude value reads 0.5 at once.
    func calibrate() {
        guard isAvailable else { return }
        tracker.calibrate()
        readout = tracker.values
        announce?(Self.calibratedAnnouncement)
    }

    /// "Tilt forward 50 percent" (the readout rows' accessibility label and value).
    static func percent(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 100).rounded()) }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        sampler.stop()
    }
}
