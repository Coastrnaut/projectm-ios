// OneHandedSetting.swift — ACC-009-R1, R6, R9 (specs/244-acc-009-one-handed-mode, contract C3): the "One-handed
// layout" preference (Settings → Performance, after Show HUD; iPhone only).
//
// One String, key `settings.controls.oneHanded`: "left" or "right"; absent (or anything else) = Off, the standard
// layout. Written on change only. A preference: backed up with the library settings (FILE-005 `includedKeys`), erased
// with the Settings category (FILE-011), removed by `-uitestResetNotice`. On iPad it is not offered and is ignored
// (`isActive` is false), so iPad layouts are unchanged. Never in scenes, cues, MIDI or OSC.
// ACC-010-R1, R6, R7 (specs/248-acc-010-left-handed-layout): the "Left-handed controls" switch lives here too (one
// handedness object, research ACC-010-D2): one Boolean, key `settings.controls.leftHanded` (absent = off; off removes
// it), iPhone and iPad, same backup, erase and reset rules. `controlsSide` is the one-handed hand while that layout is
// active, else the switch.
import Foundation
import Observation
import ShowControl
import UIKit

@MainActor
@Observable
final class OneHandedSetting {
    static let key = "settings.controls.oneHanded"
    static let title = "One-handed layout"
    static let footer = "Moves Stop, Pause, Previous, Next, Random, Presets, Settings, Black out, Tap tempo and the cue buttons into large buttons at the bottom corner on the side of the hand that holds the phone."

    static let leftHandedKey = "settings.controls.leftHanded"
    static let leftHandedTitle = "Left-handed controls"
    static let leftHandedFooter = "Moves the performance pad's Black out and Tap tempo buttons and the emergency Black out button to the left side. The visualization is never mirrored. While the one-handed layout is on, its hand decides."

    @ObservationIgnored private let defaults: UserDefaults
    /// False on iPad: the choice is not offered and is ignored (ACC-009-R6).
    let isPhone: Bool

    /// The holding hand; nil = Off.
    var hand: OneHandedHand? {
        didSet {
            guard hand != oldValue else { return }
            if let hand { defaults.set(hand.rawValue, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        }
    }

    /// ACC-010-R1: mirror the edge-anchored performance controls (off by default).
    var leftHanded: Bool {
        didSet {
            guard leftHanded != oldValue else { return }
            if leftHanded { defaults.set(true, forKey: Self.leftHandedKey) } else { defaults.removeObject(forKey: Self.leftHandedKey) }
        }
    }

    /// ACC-010-R6: the side the pad and the emergency button favour.
    var controlsSide: ControlsSide { ControlsSide.resolve(oneHanded: isActive ? hand : nil, leftHanded: leftHanded) }

    /// The one-handed layout is in use.
    var isActive: Bool { isPhone && hand != nil }

    init(defaults: UserDefaults, isPhone: Bool = UIDevice.current.userInterfaceIdiom == .phone) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.key)   // the UI-test reset: Off (a launch argument still overrides)
            defaults.removeObject(forKey: Self.leftHandedKey)   // ACC-010-R7
        }
        self.defaults = defaults
        self.isPhone = isPhone
        leftHanded = defaults.bool(forKey: Self.leftHandedKey)
        hand = defaults.string(forKey: Self.key).flatMap { (raw: String) -> OneHandedHand? in OneHandedHand(rawValue: raw) }
    }
}

extension AppCoordinator {
    /// ACC-009: the one-handed layout is in use (a hand is chosen, on iPhone).
    var oneHandedActive: Bool { oneHanded.isActive }

    /// ACC-009 contract C2: the state that decides which critical actions exist now.
    var oneHandedContext: CriticalActionContext {
        CriticalActionContext(hasCues: show.hasCues, padOn: performanceLayout, alternateVisual: showsAlternateVisual,
                              controlsVisible: controlsVisible)
    }
}
