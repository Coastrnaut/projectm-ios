// GestureShortcuts.swift — UIX-006: touch gesture shortcuts on the visualization (specs/290-uix-006-touch-gesture-
// mapping; R1-R6, R9, R10; contract G1, G2; research UIX-006-D1, D2, D6).
//
// * Six mappable multi-finger gestures, declared in precedence order (highest first): three-finger tap, two-finger
//   swipe left, right, up, down, two-finger tap. One-finger gestures stay with the app's controls tap (FR-042) and
//   CAM-005's double-tap; they are not in this type.
// * A safe action catalogue: navigation and reversible view preferences only. No blackout, restore or editing
//   action exists in the type (spec Clarifications).
// * `GestureClassifier` turns one touch sequence's summary into the set of gestures it can be read as;
//   `GestureShortcutResolver` picks the one winning action, or none.
// Foundation only: tested on Linux too.
import Foundation

/// A mappable gesture. `allCases` is the precedence order, highest first (UIX-006-R3).
public enum PerformanceGesture: String, CaseIterable, Codable, Sendable, Hashable {
    case threeFingerTap
    case twoFingerSwipeLeft
    case twoFingerSwipeRight
    case twoFingerSwipeUp
    case twoFingerSwipeDown
    case twoFingerTap

    /// 0 is the highest precedence.
    public var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    public var title: String {
        switch self {
        case .threeFingerTap: "Three-finger tap"
        case .twoFingerSwipeLeft: "Two-finger swipe left"
        case .twoFingerSwipeRight: "Two-finger swipe right"
        case .twoFingerSwipeUp: "Two-finger swipe up"
        case .twoFingerSwipeDown: "Two-finger swipe down"
        case .twoFingerTap: "Two-finger tap"
        }
    }
}

/// The safe action catalogue (UIX-006-R2).
public enum GestureAction: String, CaseIterable, Codable, Sendable, Hashable {
    case none
    case nextCue
    case previousCue
    case nextPreset
    case previousPreset
    case tapTempo
    case toggleHUD

    public var title: String {
        switch self {
        case .none: "None"
        case .nextCue: "Next cue (Go)"
        case .previousCue: "Previous cue"
        case .nextPreset: "Next preset"
        case .previousPreset: "Previous preset"
        case .tapTempo: "Tap tempo"
        case .toggleHUD: "Show/hide HUD"
        }
    }
}

/// The master switch and the mapping (UIX-006-R5, R9). Missing gestures read as their defaults.
public struct GestureShortcutConfiguration: Equatable, Sendable {
    /// What each gesture runs until the user changes it (spec Clarifications: swipes step cues and presets, taps None).
    public static let defaultMapping: [PerformanceGesture: GestureAction] = [
        .twoFingerSwipeLeft: .nextCue, .twoFingerSwipeRight: .previousCue,
        .twoFingerSwipeUp: .nextPreset, .twoFingerSwipeDown: .previousPreset,
        .twoFingerTap: .none, .threeFingerTap: .none,
    ]

    public var isEnabled: Bool
    private var mapping: [PerformanceGesture: GestureAction]

    public init(isEnabled: Bool = false, mapping: [PerformanceGesture: GestureAction] = [:]) {
        self.isEnabled = isEnabled
        self.mapping = mapping
    }

    public func action(for gesture: PerformanceGesture) -> GestureAction {
        mapping[gesture] ?? Self.defaultMapping[gesture] ?? .none
    }

    public mutating func set(_ action: GestureAction, for gesture: PerformanceGesture) {
        mapping[gesture] = action
    }

    /// Equal when the switch and every gesture's effective action agree (a default written out equals a missing one).
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isEnabled == rhs.isEnabled
            && PerformanceGesture.allCases.allSatisfy { (gesture: PerformanceGesture) -> Bool in lhs.action(for: gesture) == rhs.action(for: gesture) }
    }

    // MARK: Storage (UIX-006-D6): one JSON string; unknown names ignored, damaged JSON → default.

    private struct Stored: Codable {
        var enabled: Bool
        var mapping: [String: String]
    }

    public var json: String {
        var names: [String: String] = [:]
        for gesture in PerformanceGesture.allCases { names[gesture.rawValue] = action(for: gesture).rawValue }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Stored(enabled: isEnabled, mapping: names)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public init(json: String?) {
        self.init()
        guard let json, let stored = try? JSONDecoder().decode(Stored.self, from: Data(json.utf8)) else { return }
        isEnabled = stored.enabled
        for (key, value) in stored.mapping {
            guard let gesture = PerformanceGesture(rawValue: key), let action = GestureAction(rawValue: value) else { continue }
            mapping[gesture] = action
        }
    }
}

/// One touch sequence on the visualization, from first finger down to last finger up.
public struct GestureTouchSummary: Equatable, Sendable {
    /// The most fingers down at once.
    public var maxTouches: Int
    /// The fingers' average displacement, in points (screen coordinates: y grows downwards).
    public var dx: Double
    public var dy: Double
    /// The largest single finger's displacement, in points.
    public var maxDisplacement: Double
    public var duration: TimeInterval

    public init(maxTouches: Int, dx: Double = 0, dy: Double = 0, maxDisplacement: Double = 0, duration: TimeInterval) {
        self.maxTouches = maxTouches
        self.dx = dx
        self.dy = dy
        self.maxDisplacement = maxDisplacement
        self.duration = duration
    }
}

/// UIX-006-R10, research UIX-006-D2.
public enum GestureThresholds {
    public static let tapSlop: Double = 20
    public static let tapMaxDuration: TimeInterval = 0.5
    public static let swipeMinDistance: Double = 50
    public static let swipeMaxDuration: TimeInterval = 1.0
}

/// Contract G2: what one touch sequence can be read as.
public enum GestureClassifier {
    public static func recognise(_ touch: GestureTouchSummary) -> Set<PerformanceGesture> {
        guard touch.maxTouches == 2 || touch.maxTouches == 3 else { return [] }
        var result: Set<PerformanceGesture> = []
        if touch.maxDisplacement <= GestureThresholds.tapSlop, touch.duration <= GestureThresholds.tapMaxDuration {
            result.insert(.twoFingerTap)   // a three-finger tap contains a two-finger tap (precedence decides)
            if touch.maxTouches == 3 { result.insert(.threeFingerTap) }
        }
        if touch.maxTouches == 2, touch.duration <= GestureThresholds.swipeMaxDuration, let swipe = swipe(touch) {
            result.insert(swipe)
        }
        return result
    }

    private static func swipe(_ touch: GestureTouchSummary) -> PerformanceGesture? {
        let horizontal: Double = abs(touch.dx), vertical: Double = abs(touch.dy)
        if horizontal >= GestureThresholds.swipeMinDistance, horizontal > vertical {
            return touch.dx < 0 ? .twoFingerSwipeLeft : .twoFingerSwipeRight
        }
        if vertical >= GestureThresholds.swipeMinDistance, vertical > horizontal {
            return touch.dy < 0 ? .twoFingerSwipeUp : .twoFingerSwipeDown
        }
        return nil
    }
}

/// The winner of one touch sequence.
public struct GestureShortcutResolution: Equatable, Sendable {
    public var gesture: PerformanceGesture
    public var action: GestureAction

    public init(gesture: PerformanceGesture, action: GestureAction) {
        self.gesture = gesture
        self.action = action
    }
}

/// Contract G1: the explicit precedence (UIX-006-R3 to R6).
public enum GestureShortcutResolver {
    /// The highest-precedence recognised gesture whose action is not None; nil when the switch is off, VoiceOver
    /// runs, or no recognised gesture is mapped.
    public static func resolve(_ recognised: Set<PerformanceGesture>, configuration: GestureShortcutConfiguration,
                               voiceOverRunning: Bool) -> GestureShortcutResolution? {
        guard configuration.isEnabled, !voiceOverRunning else { return nil }
        for gesture in PerformanceGesture.allCases where recognised.contains(gesture) {
            let action: GestureAction = configuration.action(for: gesture)
            if action != .none { return GestureShortcutResolution(gesture: gesture, action: action) }
        }
        return nil
    }

    /// True while some gesture could still win: the app attaches its recogniser only then.
    public static func isActive(_ configuration: GestureShortcutConfiguration, voiceOverRunning: Bool) -> Bool {
        guard configuration.isEnabled, !voiceOverRunning else { return false }
        return PerformanceGesture.allCases.contains { (gesture: PerformanceGesture) -> Bool in configuration.action(for: gesture) != .none }
    }
}
