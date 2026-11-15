// GestureShortcutViews.swift — UIX-006 (specs/290-uix-006-touch-gesture-mapping; R3-R8, R10, R11; contract G2-G5;
// research UIX-006-D1, D3, D4):
// * `GestureShortcutRecognizer` summarises one touch sequence (most fingers down at once, each finger's displacement,
//   duration) and recognises only when the pure resolver says a mapped gesture wins; the other recognisers on the
//   same touch (the controls tap, CAM-005's double-tap) wait for it to fail, so one action runs per touch. It fails
//   at once when the sequence cannot become a shortcut (one finger lifted or dragged, five fingers, too long), so a
//   one-finger tap is not delayed.
// * `GestureShortcutAttachment` attaches it to the visualization's tap area only while some gesture is mapped, the
//   switch is on and VoiceOver is off (VoiceOver owns multi-finger gestures).
// * `GestureShortcutsSection`: Settings → Performance → Gesture shortcuts (disabled while the scene is locked).
import PerformanceControl
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

final class GestureShortcutRecognizer: UIGestureRecognizer {
    /// True when the recognised set has a winning mapped action (the resolver with the live configuration).
    var wins: (Set<PerformanceGesture>) -> Bool = { (_: Set<PerformanceGesture>) -> Bool in false }
    /// The set recognised by the last sequence that ended with a winner.
    private(set) var recognised: Set<PerformanceGesture> = []

    private var starts: [ObjectIdentifier: CGPoint] = [:]
    private var latest: [ObjectIdentifier: CGPoint] = [:]
    private var down = 0
    private var maxTouches = 0
    private var firstTime: TimeInterval?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let point: CGPoint = touch.location(in: nil)
            starts[ObjectIdentifier(touch)] = point
            latest[ObjectIdentifier(touch)] = point
            firstTime = firstTime ?? touch.timestamp
        }
        down += touches.count
        maxTouches = max(maxTouches, down)
        if maxTouches > 3 { state = .failed }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches)
        if maxTouches == 1, maxDisplacement() > GestureThresholds.tapSlop { state = .failed }   // a one-finger drag
        else if tooLong(touches) { state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        record(touches)
        down -= touches.count
        if maxTouches < 2 { state = .failed; return }   // a one-finger tap: the controls' tap, undelayed (R11)
        guard down <= 0 else { return }
        let summary: GestureTouchSummary = summarise(endTime: touches.first?.timestamp ?? firstTime ?? 0)
        let set: Set<PerformanceGesture> = GestureClassifier.recognise(summary)
        if wins(set) {
            recognised = set
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        starts = [:]
        latest = [:]
        down = 0
        maxTouches = 0
        firstTime = nil
    }

    /// D3: the controls' tap and CAM-005's double-tap wait for this recogniser to fail.
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        !(otherGestureRecognizer is GestureShortcutRecognizer)
    }

    private func record(_ touches: Set<UITouch>) {
        for touch in touches { latest[ObjectIdentifier(touch)] = touch.location(in: nil) }
    }

    private func tooLong(_ touches: Set<UITouch>) -> Bool {
        guard let firstTime, let now = touches.first?.timestamp else { return false }
        return now - firstTime > GestureThresholds.swipeMaxDuration
    }

    private func displacement(_ id: ObjectIdentifier) -> CGVector {
        guard let start = starts[id], let end = latest[id] else { return .zero }
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    private func maxDisplacement() -> Double {
        var largest: Double = 0
        for id in starts.keys {
            let d: CGVector = displacement(id)
            largest = max(largest, Double((d.dx * d.dx + d.dy * d.dy).squareRoot()))
        }
        return largest
    }

    private func summarise(endTime: TimeInterval) -> GestureTouchSummary {
        var dx: Double = 0, dy: Double = 0
        for id in starts.keys {
            let d: CGVector = displacement(id)
            dx += Double(d.dx)
            dy += Double(d.dy)
        }
        let count: Double = Double(max(starts.count, 1))
        return GestureTouchSummary(maxTouches: maxTouches, dx: dx / count, dy: dy / count, maxDisplacement: maxDisplacement(),
                                   duration: endTime - (firstTime ?? endTime))
    }
}

/// The recogniser as a SwiftUI gesture (iOS 18+ `UIGestureRecognizerRepresentable`).
struct GestureShortcutGesture: UIGestureRecognizerRepresentable {
    let coordinator: AppCoordinator
    let setting: GestureShortcutsSetting

    func makeUIGestureRecognizer(context: Context) -> GestureShortcutRecognizer {
        let recognizer = GestureShortcutRecognizer(target: nil, action: nil)
        updateUIGestureRecognizer(recognizer, context: context)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: GestureShortcutRecognizer, context: Context) {
        recognizer.wins = Self.predicate(setting)
    }

    private static func predicate(_ setting: GestureShortcutsSetting) -> (Set<PerformanceGesture>) -> Bool {
        func check(_ set: Set<PerformanceGesture>) -> Bool { wins(set, setting) }
        return check
    }

    /// True when the live configuration gives the recognised set a winner (VoiceOver read at the moment of the touch).
    private static func wins(_ set: Set<PerformanceGesture>, _ setting: GestureShortcutsSetting) -> Bool {
        let configuration: GestureShortcutConfiguration = setting.configuration
        let voiceOver: Bool = UIAccessibility.isVoiceOverRunning
        let winner: GestureShortcutResolution? = GestureShortcutResolver.resolve(set, configuration: configuration, voiceOverRunning: voiceOver)
        return winner != nil
    }

    func handleUIGestureRecognizerAction(_ recognizer: GestureShortcutRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        coordinator.handleGestureShortcut(recognizer.recognised)
    }
}

/// R5, R6: attached only while a gesture can win and VoiceOver is off.
struct GestureShortcutAttachment: ViewModifier {
    let coordinator: AppCoordinator
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled: Bool

    func body(content: Content) -> some View {
        let setting: GestureShortcutsSetting = coordinator.gestureShortcuts
        if GestureShortcutResolver.isActive(setting.configuration, voiceOverRunning: voiceOverEnabled) {
            content.gesture(GestureShortcutGesture(coordinator: coordinator, setting: setting))
        } else {
            content
        }
    }
}

/// Contract G5 (DEBUG, `-uitestDiagnostics`): "<last action>:<count>".
struct GestureShortcutProbe: View {
    let coordinator: AppCoordinator

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
            let value: String = coordinator.lastGestureShortcut.rawValue + ":" + String(coordinator.gestureShortcutCount)
            let preset: String = coordinator.presets.current?.name ?? "none"
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("gestureShortcutLast")
                .accessibilityValue(value)
            Text(preset)   // the shown preset, readable with the controls hidden
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("gestureShortcutPreset")
                .accessibilityValue(preset)
        }
        #endif
    }
}

/// Contract G4: Settings → Performance → Gesture shortcuts.
struct GestureShortcutsSection: View {
    let setting: GestureShortcutsSetting
    let locked: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled: Bool

    private var enabled: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in setting.isEnabled }, set: { (on: Bool) -> Void in setting.setEnabled(on) })
    }

    private func choice(_ gesture: PerformanceGesture) -> Binding<GestureAction> {
        Binding<GestureAction>(get: { () -> GestureAction in setting.action(for: gesture) },
                               set: { (action: GestureAction) -> Void in setting.setAction(action, for: gesture) })
    }

    var body: some View {
        Section {
            if locked {
                Text(SceneLock.refusalMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("gestureShortcutsLockNote")
            }
            Toggle(GestureShortcutsSetting.title, isOn: enabled)
                .accessibilityIdentifier("gestureShortcutsToggle")
            if setting.isEnabled { pickers }
        } header: {
            Text("Gestures")
        } footer: {
            footer
        }
        .disabled(locked)   // R8
    }

    /// Taps first, then the swipes (the footer states the precedence, which is not the display order).
    static let displayOrder: [PerformanceGesture] = [.twoFingerTap, .threeFingerTap, .twoFingerSwipeLeft, .twoFingerSwipeRight,
                                                     .twoFingerSwipeUp, .twoFingerSwipeDown]

    @ViewBuilder private var pickers: some View {
        ForEach(Self.displayOrder, id: \.self) { (gesture: PerformanceGesture) in
            Picker(gesture.title, selection: choice(gesture)) {
                ForEach(GestureAction.allCases, id: \.self) { (action: GestureAction) in
                    Text(action.title).tag(action)
                }
            }
            .accessibilityIdentifier("gestureShortcut." + gesture.rawValue)
        }
    }

    private var footer: some View {
        let note: String = voiceOverEnabled ? " " + GestureShortcutsSetting.voiceOverNote : ""
        return Text(GestureShortcutsSetting.footer + note)
    }
}
