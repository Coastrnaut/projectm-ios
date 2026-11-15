// MotionTracker.swift — device tilt and shake as normalized modulation values (CAM-011-R3 to R7, R11, R13;
// specs/247-cam-011-motion-sensor-modulation, research CAM-011-D3 to D5, contract motion-sources M3 to M6).
//
// * Attitude (pitch, roll, yaw in radians) is unwrapped between consecutive samples: each sample adds
//   `remainder(new − last, 2π)` to the axis's offset from the calibrated neutral, so the sensor's ±π seam never
//   makes the output jump. The offset stays within ±2π (one turn back always returns). A restart re-anchors the
//   offset at `remainder(angle − neutral, 2π)` on the first new sample.
// * value = clamp(0.5 + offset / (2 · range), 0, 1), smoothed by MOD-005's one-pole `AudioFeatureEnvelope.step`
//   (60 ms) on the sample clock; shake = clamp(|user acceleration| / 2 g, 0, 1) through attack 20 ms / release 300 ms.
// * The only clock is the sample time in integer nanoseconds: Δt 0 on the first sample after a (re)start and when time
//   does not increase, at most 0.25 s. Non-finite sample components are ignored (the last value held), so every output
//   is finite and within 0…1. No allocation: plain stored Doubles. One owner (not `Sendable`).
// Foundation-free (the C math library only): builds on Linux. The sensor itself lives in the app (CoreMotion).
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A motion signal a binding can follow (CAM-011-R1).
public enum MotionAxis: String, Sendable, Hashable, CaseIterable {
    /// Tilting forward and back (rotation about the device's x axis).
    case pitch
    /// Tilting sideways (rotation about the device's y axis).
    case roll
    /// Turning about the vertical (relative to where sampling started; calibration makes it explicit).
    case yaw
    /// The strength of the user's acceleration (gravity removed), as an envelope.
    case shake
}

/// One device-motion reading: attitude in radians, user acceleration in g, and its time.
public struct MotionSample: Sendable, Hashable {
    public var pitch: Double
    public var roll: Double
    public var yaw: Double
    public var accelerationX: Double
    public var accelerationY: Double
    public var accelerationZ: Double
    public var timeNanoseconds: UInt64

    public init(pitch: Double, roll: Double, yaw: Double, accelerationX: Double = 0, accelerationY: Double = 0,
                accelerationZ: Double = 0, timeNanoseconds: UInt64) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
        self.timeNanoseconds = timeNanoseconds
    }
}

/// The half-width of the attitude range mapped onto 0…1 (CAM-011-R3).
public enum MotionRange: String, Sendable, Hashable, CaseIterable {
    case narrow
    case medium
    case wide

    public static let defaultRange: MotionRange = .medium

    /// The stored raw value, Medium when absent or unknown.
    public init(stored raw: String?) {
        self = raw.flatMap(MotionRange.init(rawValue:)) ?? .defaultRange
    }

    /// ±20°, ±45°, ±90°.
    public var degrees: Double {
        switch self {
        case .narrow: 20
        case .medium: 45
        case .wide: 90
        }
    }

    public var radians: Double { degrees * Double.pi / 180 }

    public var title: String {
        switch self {
        case .narrow: "Narrow (±20°)"
        case .medium: "Medium (±45°)"
        case .wide: "Wide (±90°)"
        }
    }
}

/// One frame's motion values, each finite and within 0…1.
public struct MotionFeatureValues: Sendable, Hashable {
    public var pitch: Double
    public var roll: Double
    public var yaw: Double
    public var shake: Double

    public init(pitch: Double, roll: Double, yaw: Double, shake: Double) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.shake = shake
    }

    /// No motion (or none available): attitude at the middle, no shake (CAM-011-R11).
    public static let neutral = MotionFeatureValues(pitch: 0.5, roll: 0.5, yaw: 0.5, shake: 0)

    /// The value of `axis`, clamped to 0…1; a non-finite value reads the neutral value (contract M2).
    public func value(_ axis: MotionAxis) -> Double {
        let raw: Double
        let fallback: Double
        switch axis {
        case .pitch: raw = pitch; fallback = 0.5
        case .roll: raw = roll; fallback = 0.5
        case .yaw: raw = yaw; fallback = 0.5
        case .shake: raw = shake; fallback = 0
        }
        guard raw.isFinite else { return fallback }
        return min(max(raw, 0), 1)
    }
}

public final class MotionTracker {
    /// The attitude smoothing time constant (one-pole, attack = release).
    public static let attitudeSmoothing = AudioFeatureEnvelope(attackSeconds: 0.06, releaseSeconds: 0.06)
    /// The shake envelope: a quick rise and a smooth fall.
    public static let shakeEnvelope = AudioFeatureEnvelope(attackSeconds: 0.02, releaseSeconds: 0.3)
    /// The user acceleration (in g) that reads as a full shake.
    public static let shakeFullScaleG = 2.0
    /// The longest elapsed time one sample applies.
    public static let maximumStepSeconds = 0.25
    /// The unwrapped offset from neutral is limited to one turn either way.
    public static let maximumOffset = 2 * Double.pi

    /// The half-width mapped onto 0…1; changes apply from the next sample.
    public var range: MotionRange

    // Calibrated neutral attitude; yaw's is taken from the first sample until calibrated.
    private var neutral: (pitch: Double, roll: Double, yaw: Double) = (0, 0, 0)
    private var yawNeutralSet = false
    // Last raw (finite) angle per axis, for unwrapping; nil until the axis has a finite reading since the start.
    private var lastPitch: Double?
    private var lastRoll: Double?
    private var lastYaw: Double?
    // Unwrapped offsets from neutral.
    private var offsetPitch = 0.0
    private var offsetRoll = 0.0
    private var offsetYaw = 0.0
    private var lastTime: UInt64?
    private var snapNext = true

    /// The smoothed outputs (neutral before the first sample).
    public private(set) var values: MotionFeatureValues = .neutral
    /// True once a sample has been ingested since the last restart.
    public private(set) var hasSamples = false

    public init(range: MotionRange = .defaultRange) {
        self.range = range
    }

    /// Sampling (re)starts: the next sample re-anchors the unwrapping and the smoothing snaps to it; the held values
    /// stay readable until then. The pitch and roll neutral are kept (gravity-referenced); the yaw neutral is taken
    /// again from the first new sample, because the sensor's yaw reference changes on every start (research CAM-011-D5).
    public func restart() {
        yawNeutralSet = false
        lastPitch = nil
        lastRoll = nil
        lastYaw = nil
        lastTime = nil
        snapNext = true
        hasSamples = false
    }

    /// Takes the current attitude as neutral: every attitude value reads 0.5 at once (CAM-011-R5).
    public func calibrate() {
        if let p = lastPitch { neutral.pitch = p }
        if let r = lastRoll { neutral.roll = r }
        if let y = lastYaw {
            neutral.yaw = y
            yawNeutralSet = true
        }
        offsetPitch = 0
        offsetRoll = 0
        offsetYaw = 0
        values.pitch = 0.5
        values.roll = 0.5
        values.yaw = 0.5
    }

    /// Advances the tracker with one sample (contract M3, M4, M6).
    public func ingest(_ sample: MotionSample) {
        var elapsed = 0.0
        if let last = lastTime {
            if sample.timeNanoseconds > last {
                elapsed = min(Double(sample.timeNanoseconds - last) / 1e9, Self.maximumStepSeconds)
                lastTime = sample.timeNanoseconds
            }
        } else {
            lastTime = sample.timeNanoseconds
        }
        if sample.yaw.isFinite, !yawNeutralSet {
            neutral.yaw = sample.yaw
            yawNeutralSet = true
        }
        Self.unwrap(sample.pitch, last: &lastPitch, offset: &offsetPitch, neutral: neutral.pitch)
        Self.unwrap(sample.roll, last: &lastRoll, offset: &offsetRoll, neutral: neutral.roll)
        Self.unwrap(sample.yaw, last: &lastYaw, offset: &offsetYaw, neutral: neutral.yaw)

        let width: Double = 2 * range.radians
        let pitchGoal: Double = Self.normalized(offsetPitch, width: width)
        let rollGoal: Double = Self.normalized(offsetRoll, width: width)
        let yawGoal: Double = Self.normalized(offsetYaw, width: width)
        let shakeGoal: Double = Self.shakeLevel(sample)
        if snapNext {
            values = MotionFeatureValues(pitch: pitchGoal, roll: rollGoal, yaw: yawGoal, shake: shakeGoal)
            snapNext = false
        } else {
            let smooth = Self.attitudeSmoothing
            values.pitch = smooth.step(from: values.pitch, toward: pitchGoal, elapsedSeconds: elapsed)
            values.roll = smooth.step(from: values.roll, toward: rollGoal, elapsedSeconds: elapsed)
            values.yaw = smooth.step(from: values.yaw, toward: yawGoal, elapsedSeconds: elapsed)
            values.shake = Self.shakeEnvelope.step(from: values.shake, toward: shakeGoal, elapsedSeconds: elapsed)
        }
        hasSamples = true
    }

    /// Adds the wrapped change since the last reading to the offset; the first reading anchors it within ±π of neutral.
    /// A non-finite reading changes nothing.
    private static func unwrap(_ angle: Double, last: inout Double?, offset: inout Double, neutral: Double) {
        guard angle.isFinite else { return }
        if let previous = last {
            offset += remainder(angle - previous, 2 * Double.pi)
        } else {
            offset = remainder(angle - neutral, 2 * Double.pi)
        }
        offset = min(max(offset, -maximumOffset), maximumOffset)
        last = angle
    }

    private static func normalized(_ offset: Double, width: Double) -> Double {
        guard offset.isFinite, width > 0 else { return 0.5 }
        return min(max(0.5 + offset / width, 0), 1)
    }

    /// |a| / 2 g clamped; non-finite components count as 0.
    private static func shakeLevel(_ sample: MotionSample) -> Double {
        let x: Double = sample.accelerationX.isFinite ? sample.accelerationX : 0
        let y: Double = sample.accelerationY.isFinite ? sample.accelerationY : 0
        let z: Double = sample.accelerationZ.isFinite ? sample.accelerationZ : 0
        let magnitude: Double = (x * x + y * y + z * z).squareRoot()
        guard magnitude.isFinite else { return 1 }   // overflow of huge finite components: a full shake
        return min(magnitude / shakeFullScaleG, 1)
    }
}
