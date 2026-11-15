// HandFeatureTracker.swift — up to two hands' derived scalars as normalized modulation values (CAM-010-R6, R7, R9,
// R15; specs/276-cam-010-hand-pose-modulation, research CAM-010-D5, D6, contract hand-sources H1, H2).
//
// * A `HandPoseFrame` holds only what the detector reports for one picture: up to two hands, each seven joints
//   (wrist, five fingertips, middle knuckle) in normalized picture coordinates (origin bottom-left) with their
//   confidences, and the upright picture's aspect. It is never stored; the tracker turns it into nine values and
//   drops it.
// * `HandFeatureNormalizer.measure` maps a frame to targets (each 0…1, or NaN where the frame cannot say: the tracker
//   then holds that value). Joints below confidence 0.3 are ignored; a hand needs 6 confident joints. Distances are in
//   picture-height units (x scaled by the aspect); the palm (wrist → middle knuckle) is the hand's own scale.
// * `HandFeatureTracker` smooths with MOD-005's one-pole (80 ms toward a seen hand, 300 ms toward neutral) on an
//   injected nanosecond clock, hold-then-step: each ingest first moves toward the target held since the previous
//   measurement, then holds the new one. The one-pole is exponential, so values at a time depend only on the poses and
//   their times, never on how many frames arrived in between (research CAM-010-D6).
// Foundation-free: builds on Linux. The detector (Vision) lives in the app.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// One hand signal a binding can follow (CAM-010-R6). The raw value is the source ID's suffix.
public enum HandFeature: String, Sendable, Hashable, CaseIterable {
    /// 1 while a hand is seen, 0 otherwise (smoothed).
    case present
    /// The first hand's wrist left (0) to right (1) in the shown picture.
    case x
    /// The first hand's wrist bottom (0) to top (1).
    case y
    /// Thumb tip to index tip: 1 touching, 0 apart (0.8 palm lengths or more).
    case pinch
    /// Mean fingertip-to-wrist distance: 0 a fist, 1 a spread hand.
    case open
    /// The first hand's palm length relative to 0.4 of the picture height.
    case size
    /// 1 while a second hand is seen.
    case second
    /// The second hand's wrist left (0) to right (1).
    case secondX
    /// The second hand's wrist bottom (0) to top (1).
    case secondY
}

/// One frame's hand values, each finite and within 0…1 when read.
public struct HandFeatureValues: Sendable, Hashable {
    public var present: Double
    public var x: Double
    public var y: Double
    public var pinch: Double
    public var open: Double
    public var size: Double
    public var second: Double
    public var secondX: Double
    public var secondY: Double

    public init(present: Double, x: Double, y: Double, pinch: Double, open: Double, size: Double, second: Double,
                secondX: Double, secondY: Double) {
        self.present = present
        self.x = x
        self.y = y
        self.pinch = pinch
        self.open = open
        self.size = size
        self.second = second
        self.secondX = secondX
        self.secondY = secondY
    }

    /// No hand: present 0, positions 0.5, the rest 0 (CAM-010-R9).
    public static let neutral = HandFeatureValues(present: 0, x: 0.5, y: 0.5, pinch: 0, open: 0, size: 0, second: 0,
                                                  secondX: 0.5, secondY: 0.5)

    /// The neutral value of `feature`.
    public static func neutralValue(_ feature: HandFeature) -> Double { neutral.raw(feature) }

    /// The stored value of `feature`, unclamped.
    func raw(_ feature: HandFeature) -> Double {
        switch feature {
        case .present: present
        case .x: x
        case .y: y
        case .pinch: pinch
        case .open: open
        case .size: size
        case .second: second
        case .secondX: secondX
        case .secondY: secondY
        }
    }

    mutating func set(_ feature: HandFeature, _ value: Double) {
        switch feature {
        case .present: present = value
        case .x: x = value
        case .y: y = value
        case .pinch: pinch = value
        case .open: open = value
        case .size: size = value
        case .second: second = value
        case .secondX: secondX = value
        case .secondY: secondY = value
        }
    }

    /// The value of `feature`, clamped to 0…1; a non-finite value reads the neutral value (contract H2).
    public func value(_ feature: HandFeature) -> Double {
        let stored: Double = raw(feature)
        guard stored.isFinite else { return Self.neutralValue(feature) }
        return min(max(stored, 0), 1)
    }
}

/// One joint in normalized picture coordinates (0…1, origin bottom-left) with the detector's confidence.
public struct HandJointPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }

    /// A joint the detector did not see.
    public static let missing = HandJointPoint(x: 0, y: 0, confidence: 0)
}

/// The seven joints read from one hand (memory only).
public struct HandObservationSample: Sendable, Hashable {
    public var wrist: HandJointPoint
    public var thumbTip: HandJointPoint
    public var indexTip: HandJointPoint
    public var middleTip: HandJointPoint
    public var ringTip: HandJointPoint
    public var littleTip: HandJointPoint
    /// The middle finger's knuckle (MCP); wrist → knuckle is the palm length.
    public var middleKnuckle: HandJointPoint

    public init(wrist: HandJointPoint, thumbTip: HandJointPoint, indexTip: HandJointPoint, middleTip: HandJointPoint,
                ringTip: HandJointPoint, littleTip: HandJointPoint, middleKnuckle: HandJointPoint) {
        self.wrist = wrist
        self.thumbTip = thumbTip
        self.indexTip = indexTip
        self.middleTip = middleTip
        self.ringTip = ringTip
        self.littleTip = littleTip
        self.middleKnuckle = middleKnuckle
    }

    var joints: [HandJointPoint] { [wrist, thumbTip, indexTip, middleTip, ringTip, littleTip, middleKnuckle] }
}

/// What the detector reports for one picture: 0…2 hands and the upright picture's width ÷ height (memory only).
public struct HandPoseFrame: Sendable, Hashable {
    public var hands: [HandObservationSample]
    public var aspect: Double

    public init(hands: [HandObservationSample], aspect: Double = 1) {
        self.hands = hands
        self.aspect = aspect
    }
}

/// CAM-010-R7 (research CAM-010-D5): a frame → targets (each 0…1, or NaN where the frame cannot say).
public enum HandFeatureNormalizer {
    /// Joints below this confidence are ignored.
    public static let confidenceFloor = 0.3
    /// A hand needs at least this many confident joints of the seven.
    public static let minimumJoints = 6
    /// Palms shorter than this (picture heights) are degenerate.
    public static let minimumPalm = 0.01
    /// Thumb–index gap ÷ palm length at which pinch reads 1 (touching) and 0 (apart).
    public static let pinchClosedRatio = 0.2
    public static let pinchOpenRatio = 0.8
    /// Mean fingertip–wrist distance ÷ palm length for a fist (0) and a spread hand (1).
    public static let fistRatio = 1.0
    public static let spreadRatio = 1.9
    /// The palm length (picture heights) that reads size 1.
    public static let fullSizePalm = 0.4

    public static func measure(_ frame: HandPoseFrame, mirrored: Bool) -> HandFeatureValues {
        let aspect: Double = frame.aspect.isFinite && frame.aspect > 0 ? frame.aspect : 1
        let counted: [HandObservationSample] = frame.hands.filter { (hand: HandObservationSample) -> Bool in isCounted(hand) }
        let ordered: [HandObservationSample] = counted.sorted { (a: HandObservationSample, b: HandObservationSample) -> Bool in
            palm(a, aspect: aspect) > palm(b, aspect: aspect)
        }
        var values: HandFeatureValues = .neutral
        guard let first = ordered.first else { return values }
        let nan: Double = .nan
        values.present = 1
        let wrist: (x: Double, y: Double) = position(first.wrist, mirrored: mirrored)
        values.x = wrist.x
        values.y = wrist.y
        let palmLength: Double = palm(first, aspect: aspect)
        let palmOK: Bool = palmLength.isFinite && palmLength >= minimumPalm
        values.pinch = palmOK ? pinch(first, palm: palmLength, aspect: aspect) : nan
        values.open = palmOK ? openness(first, palm: palmLength, aspect: aspect) : nan
        values.size = palmOK ? clamp(palmLength / fullSizePalm) : nan
        guard ordered.count > 1 else { return values }
        let other: (x: Double, y: Double) = position(ordered[1].wrist, mirrored: mirrored)
        values.second = 1
        values.secondX = other.x
        values.secondY = other.y
        return values
    }

    /// NaN stays NaN; otherwise clamped to 0…1.
    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return .nan }
        return min(max(value, 0), 1)
    }

    static func usable(_ joint: HandJointPoint) -> Bool {
        joint.confidence.isFinite && joint.confidence >= confidenceFloor && joint.x.isFinite && joint.y.isFinite
    }

    static func isCounted(_ hand: HandObservationSample) -> Bool {
        var count = 0
        for joint in hand.joints where usable(joint) { count += 1 }
        return count >= minimumJoints
    }

    /// The wrist in the shown picture; NaN when the wrist is not usable.
    private static func position(_ wrist: HandJointPoint, mirrored: Bool) -> (x: Double, y: Double) {
        guard usable(wrist) else { return (.nan, .nan) }
        let x: Double = mirrored ? 1 - wrist.x : wrist.x
        return (clamp(x), clamp(wrist.y))
    }

    /// The distance between two usable joints in picture heights; NaN otherwise.
    static func distance(_ a: HandJointPoint, _ b: HandJointPoint, aspect: Double) -> Double {
        guard usable(a), usable(b) else { return .nan }
        let dx: Double = (a.x - b.x) * aspect
        let dy: Double = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func palm(_ hand: HandObservationSample, aspect: Double) -> Double {
        let length: Double = distance(hand.wrist, hand.middleKnuckle, aspect: aspect)
        return length.isFinite ? length : 0
    }

    private static func pinch(_ hand: HandObservationSample, palm: Double, aspect: Double) -> Double {
        let gap: Double = distance(hand.thumbTip, hand.indexTip, aspect: aspect)
        guard gap.isFinite else { return .nan }
        let ratio: Double = gap / palm
        return clamp(1 - (ratio - pinchClosedRatio) / (pinchOpenRatio - pinchClosedRatio))
    }

    private static func openness(_ hand: HandObservationSample, palm: Double, aspect: Double) -> Double {
        var total = 0.0
        var count = 0
        for tip in [hand.thumbTip, hand.indexTip, hand.middleTip, hand.ringTip, hand.littleTip] {
            let reach: Double = distance(tip, hand.wrist, aspect: aspect)
            guard reach.isFinite else { continue }
            total += reach
            count += 1
        }
        guard count > 0 else { return .nan }
        let ratio: Double = total / Double(count) / palm
        return clamp((ratio - fistRatio) / (spreadRatio - fistRatio))
    }
}

/// CAM-010-R9 (research CAM-010-D6): smooths measured targets on the analysis clock, hold-then-step. One owner (the
/// analyzer, under its lock).
public final class HandFeatureTracker {
    /// Toward a seen hand.
    public static let tracking = AudioFeatureEnvelope(attackSeconds: 0.08, releaseSeconds: 0.08)
    /// Toward neutral when no hand is seen.
    public static let fading = AudioFeatureEnvelope(attackSeconds: 0.3, releaseSeconds: 0.3)
    /// The longest elapsed time one step applies.
    public static let maximumStepSeconds = 0.25

    public private(set) var values: HandFeatureValues = .neutral
    private var target: HandFeatureValues = .neutral
    private var envelope: AudioFeatureEnvelope = HandFeatureTracker.fading
    private var lastTime: UInt64?
    private var snapNext = true

    public init() {}

    /// Back to neutral at once (switch off, camera stop or switch); the next hand snaps.
    public func reset() {
        values = .neutral
        target = .neutral
        envelope = Self.fading
        lastTime = nil
        snapNext = true
    }

    /// Advances to `timeNanoseconds` toward the held target, then holds `frame`'s measurement (nil or no hand counted:
    /// neutral, fading). A time before the last one applies no step.
    public func ingest(_ frame: HandPoseFrame?, mirrored: Bool, timeNanoseconds: UInt64) {
        if let last = lastTime, timeNanoseconds > last {
            let elapsed: Double = min(Double(timeNanoseconds - last) / 1e9, Self.maximumStepSeconds)
            step(elapsed: elapsed)
        }
        if lastTime.map({ (last: UInt64) -> Bool in timeNanoseconds > last }) ?? true { lastTime = timeNanoseconds }
        let measured: HandFeatureValues? = frame.map { (f: HandPoseFrame) -> HandFeatureValues in
            HandFeatureNormalizer.measure(f, mirrored: mirrored)
        }
        guard let measured, measured.present == 1 else {
            target = .neutral
            envelope = Self.fading
            return
        }
        hold(measured)
        if snapNext {
            values = target
            snapNext = false
        }
    }

    /// The new target: features the frame cannot give (NaN) keep their previous target.
    private func hold(_ measured: HandFeatureValues) {
        for feature in HandFeature.allCases {
            let value: Double = measured.raw(feature)
            if value.isFinite {
                target.set(feature, value)
            } else if snapNext || target.present == 0 {
                target.set(feature, values.raw(feature))   // nothing better known: stay
            }
        }
        envelope = Self.tracking
    }

    private func step(elapsed: Double) {
        for feature in HandFeature.allCases {
            let next: Double = envelope.step(from: values.raw(feature), toward: target.raw(feature), elapsedSeconds: elapsed)
            values.set(feature, next)
        }
    }
}
