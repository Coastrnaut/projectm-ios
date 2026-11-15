// FaceFeatureTracker.swift — a face's derived scalars as normalized modulation values, the analysis schedule and the
// consent gate (CAM-009-R6 to R10, R15; specs/270-cam-009-face-landmark-emitters, research CAM-009-D3 to D5, contract
// face-sources F2, F3).
//
// * A `FaceObservationSample` holds only what the detector reports for one face: its box (normalized to the picture,
//   origin bottom-left), roll and yaw in radians, and the inner-lip and eye points normalized to the box. It is never
//   stored; the tracker turns it into eight values and drops it.
// * `FaceFeatureNormalizer.measure` maps a sample to targets (each 0…1, or NaN where the sample cannot say: the tracker
//   then holds that value). `FaceFeatureTracker` smooths toward them with MOD-005's one-pole (80 ms toward a face,
//   300 ms toward neutral without one) on an injected nanosecond clock; the first face after a reset snaps.
// * `FaceAnalysisSchedule` starts an analysis only when none is in flight and the interval has passed (15 Hz, 10 Hz
//   under reduced power, paused when the device is warm). `FaceTrackingGate` is the consent gate: switch ∧ consent ∧
//   camera authorization.
// Foundation-free: builds on Linux. The detector (Vision) lives in the app.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One face signal a binding can follow (CAM-009-R6). The raw value is the source ID's suffix.
public enum FaceFeature: String, Sendable, Hashable, CaseIterable {
    /// 1 while a face is seen, 0 otherwise (smoothed).
    case present
    /// The face centre left (0) to right (1) in the shown picture.
    case x
    /// The face centre bottom (0) to top (1).
    case y
    /// The face height relative to the picture height.
    case size
    /// Head tilt toward a shoulder: ±45° → 0…1, 0.5 upright.
    case roll
    /// Head turn left or right: ±45° → 0…1, 0.5 facing the camera.
    case yaw
    /// Inner-lip gap ÷ face height ÷ 0.2: 0 closed, 1 wide open.
    case mouth
    /// Mean eye height ÷ width, (ratio − 0.1) ÷ 0.2: 0 closed, 1 open.
    case eyes
}

/// One frame's face values, each finite and within 0…1.
public struct FaceFeatureValues: Sendable, Hashable {
    public var present: Double
    public var x: Double
    public var y: Double
    public var size: Double
    public var roll: Double
    public var yaw: Double
    public var mouth: Double
    public var eyes: Double

    public init(present: Double, x: Double, y: Double, size: Double, roll: Double, yaw: Double, mouth: Double, eyes: Double) {
        self.present = present
        self.x = x
        self.y = y
        self.size = size
        self.roll = roll
        self.yaw = yaw
        self.mouth = mouth
        self.eyes = eyes
    }

    /// No face: present 0, centre and angles 0.5, size, mouth and eyes 0 (CAM-009-R9).
    public static let neutral = FaceFeatureValues(present: 0, x: 0.5, y: 0.5, size: 0, roll: 0.5, yaw: 0.5, mouth: 0, eyes: 0)

    /// The neutral value of `feature`.
    public static func neutralValue(_ feature: FaceFeature) -> Double { neutral.raw(feature) }

    /// The stored value of `feature`, unclamped.
    func raw(_ feature: FaceFeature) -> Double {
        switch feature {
        case .present: present
        case .x: x
        case .y: y
        case .size: size
        case .roll: roll
        case .yaw: yaw
        case .mouth: mouth
        case .eyes: eyes
        }
    }

    mutating func set(_ feature: FaceFeature, _ value: Double) {
        switch feature {
        case .present: present = value
        case .x: x = value
        case .y: y = value
        case .size: size = value
        case .roll: roll = value
        case .yaw: yaw = value
        case .mouth: mouth = value
        case .eyes: eyes = value
        }
    }

    /// The value of `feature`, clamped to 0…1; a non-finite value reads the neutral value (contract F2).
    public func value(_ feature: FaceFeature) -> Double {
        let stored: Double = raw(feature)
        guard stored.isFinite else { return Self.neutralValue(feature) }
        return min(max(stored, 0), 1)
    }
}

/// A landmark point normalized to the face box (0…1, origin bottom-left).
public struct FacePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// What the detector reports for one face (memory only; dropped after `ingest`).
public struct FaceObservationSample: Sendable, Hashable {
    public var boxX: Double
    public var boxY: Double
    public var boxWidth: Double
    public var boxHeight: Double
    /// Radians; nil when the detector does not report it.
    public var roll: Double?
    public var yaw: Double?
    public var innerLips: [FacePoint]
    public var leftEye: [FacePoint]
    public var rightEye: [FacePoint]

    public init(boxX: Double, boxY: Double, boxWidth: Double, boxHeight: Double, roll: Double? = nil, yaw: Double? = nil,
                innerLips: [FacePoint] = [], leftEye: [FacePoint] = [], rightEye: [FacePoint] = []) {
        self.boxX = boxX
        self.boxY = boxY
        self.boxWidth = boxWidth
        self.boxHeight = boxHeight
        self.roll = roll
        self.yaw = yaw
        self.innerLips = innerLips
        self.leftEye = leftEye
        self.rightEye = rightEye
    }
}

/// CAM-009-R7: a sample → targets (each 0…1, or NaN where the sample cannot say).
public enum FaceFeatureNormalizer {
    /// ±45° spans 0…1 for roll and yaw.
    public static let angleHalfRange: Double = Double.pi / 4
    /// The lip gap (as a fraction of the face height) that reads fully open.
    public static let mouthFullScale = 0.2
    /// Eye height ÷ width at closed and at open.
    public static let eyeClosedRatio = 0.1
    public static let eyeOpenRatio = 0.3

    public static func measure(_ sample: FaceObservationSample, mirrored: Bool) -> FaceFeatureValues {
        let nan: Double = .nan
        let boxOK: Bool = sample.boxX.isFinite && sample.boxY.isFinite && sample.boxWidth.isFinite && sample.boxHeight.isFinite
            && sample.boxWidth > 0 && sample.boxHeight > 0
        var centreX: Double = boxOK ? sample.boxX + sample.boxWidth / 2 : nan
        if mirrored, centreX.isFinite { centreX = 1 - centreX }
        let centreY: Double = boxOK ? sample.boxY + sample.boxHeight / 2 : nan
        let size: Double = boxOK ? sample.boxHeight : nan
        let roll: Double = angle(sample.roll, mirrored: mirrored)
        let yaw: Double = angle(sample.yaw, mirrored: mirrored)
        let mouth: Double = span(sample.innerLips).map { (gap: (width: Double, height: Double)) -> Double in gap.height / mouthFullScale } ?? nan
        let aspect: Double = boxOK ? sample.boxHeight / sample.boxWidth : nan
        let eyes: Double = eyeOpenness(sample.leftEye, sample.rightEye, boxAspect: aspect)
        return FaceFeatureValues(present: 1, x: clamp(centreX), y: clamp(centreY), size: clamp(size), roll: roll, yaw: yaw,
                                 mouth: clamp(mouth), eyes: eyes)
    }

    /// NaN stays NaN; otherwise clamped to 0…1.
    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return .nan }
        return min(max(value, 0), 1)
    }

    /// ±45° → 0…1 (0.5 straight); a mirrored picture turns the other way.
    private static func angle(_ radians: Double?, mirrored: Bool) -> Double {
        guard let radians, radians.isFinite else { return .nan }
        let signed: Double = mirrored ? -radians : radians
        return clamp(0.5 + signed / (2 * angleHalfRange))
    }

    /// The points' width and height (box units); nil for fewer than 2 finite points.
    private static func span(_ points: [FacePoint]) -> (width: Double, height: Double)? {
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        var count = 0
        for point in points where point.x.isFinite && point.y.isFinite {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            count += 1
        }
        guard count >= 2 else { return nil }
        return (maxX - minX, maxY - minY)
    }

    /// The mean height ÷ width of the eyes that have a width (box units scaled by the box aspect), mapped to 0…1.
    private static func eyeOpenness(_ left: [FacePoint], _ right: [FacePoint], boxAspect: Double) -> Double {
        guard boxAspect.isFinite, boxAspect > 0 else { return .nan }
        var total = 0.0
        var eyes = 0
        for eye in [left, right] {
            guard let s = span(eye), s.width > 0 else { continue }
            total += s.height * boxAspect / s.width
            eyes += 1
        }
        guard eyes > 0 else { return .nan }
        let ratio: Double = total / Double(eyes)
        return clamp((ratio - eyeClosedRatio) / (eyeOpenRatio - eyeClosedRatio))
    }
}

/// CAM-009-R9: smooths measured targets on the analysis clock. One owner (the analyzer, under its lock).
public final class FaceFeatureTracker {
    /// Toward a seen face.
    public static let tracking = AudioFeatureEnvelope(attackSeconds: 0.08, releaseSeconds: 0.08)
    /// Toward neutral when no face is seen.
    public static let fading = AudioFeatureEnvelope(attackSeconds: 0.3, releaseSeconds: 0.3)
    /// The longest elapsed time one step applies.
    public static let maximumStepSeconds = 0.25

    public private(set) var values: FaceFeatureValues = .neutral
    private var lastTime: UInt64?
    private var snapNext = true

    public init() {}

    /// Back to neutral at once (switch off, camera stop or switch); the next face snaps.
    public func reset() {
        values = .neutral
        lastTime = nil
        snapNext = true
    }

    /// Advances with one analysis: `sample` nil means no face was seen.
    public func ingest(_ sample: FaceObservationSample?, mirrored: Bool, timeNanoseconds: UInt64) {
        var elapsed = 0.0
        if let last = lastTime {
            if timeNanoseconds > last {
                elapsed = min(Double(timeNanoseconds - last) / 1e9, Self.maximumStepSeconds)
                lastTime = timeNanoseconds
            }
        } else {
            lastTime = timeNanoseconds
        }
        guard let sample else {
            step(toward: .neutral, envelope: Self.fading, elapsed: elapsed, snap: false)
            return
        }
        let targets: FaceFeatureValues = FaceFeatureNormalizer.measure(sample, mirrored: mirrored)
        step(toward: targets, envelope: Self.tracking, elapsed: elapsed, snap: snapNext)
        snapNext = false
    }

    /// Moves every feature with a finite target; a NaN target holds its value.
    private func step(toward targets: FaceFeatureValues, envelope: AudioFeatureEnvelope, elapsed: Double, snap: Bool) {
        for feature in FaceFeature.allCases {
            let target: Double = targets.raw(feature)
            guard target.isFinite else { continue }
            let next: Double = snap ? target : envelope.step(from: values.raw(feature), toward: target, elapsedSeconds: elapsed)
            values.set(feature, next)
        }
    }
}

/// CAM-009-R10 (research CAM-009-D4): which offers start an analysis. Not thread-safe (the analyzer guards it).
public struct FaceAnalysisSchedule: Sendable, Equatable {
    public private(set) var intervalNanoseconds: UInt64?
    public private(set) var inFlight = false
    private var lastStart: UInt64?

    /// `interval` nil: paused.
    public init(intervalNanoseconds: UInt64?) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    /// True when an analysis starts now (then `inFlight`).
    public mutating func offer(at time: UInt64) -> Bool {
        guard let interval = intervalNanoseconds, !inFlight else { return false }
        if let last = lastStart, time >= last, time - last < interval { return false }
        lastStart = time
        inFlight = true
        return true
    }

    public mutating func finish() { inFlight = false }

    public mutating func setInterval(_ interval: UInt64?) { intervalNanoseconds = interval }

    /// Forgets the last start (an analysis still in flight stays counted).
    public mutating func reset() { lastStart = nil }
}

/// CAM-009-R10: the device's state → the analysis interval, nil when paused.
public enum FaceTrackingRate {
    public static let normalInterval: UInt64 = 1_000_000_000 / 15
    public static let reducedPowerInterval: UInt64 = 1_000_000_000 / 10

    public static func interval(warm: Bool, reducedPower: Bool) -> UInt64? {
        if warm { return nil }
        return reducedPower ? reducedPowerInterval : normalInterval
    }
}

/// CAM-009-R1, R4, R5 (research CAM-009-D3): analysis may run only with the switch on, consent given and the camera
/// authorized.
public struct FaceTrackingGate: Sendable, Hashable {
    public var switchOn: Bool
    public var consented: Bool
    public var cameraAuthorized: Bool

    public init(switchOn: Bool, consented: Bool, cameraAuthorized: Bool) {
        self.switchOn = switchOn
        self.consented = consented
        self.cameraAuthorized = cameraAuthorized
    }

    public var allowsAnalysis: Bool { switchOn && consented && cameraAuthorized }
}
