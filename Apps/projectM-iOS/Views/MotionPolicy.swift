// MotionPolicy.swift — ACC-001 (Reduce motion mode; spec ACC-001-R1 to R7, contract C1).
//
// Every app-owned decorative UI animation goes through this policy: while the system Reduce Motion
// setting is on it becomes nil (instant), otherwise it plays unchanged. Safety fades — a fade that
// protects against a flash (PERF-014's placeholder, OUT-010's restore) — are outside the policy and
// are marked with `MotionPolicy.safetyFade` so they are never shortened. The visualization itself is
// content: Reduce Motion changes none of its parameters (Reduce flashing governs flashes, FR-072).
// `scripts/check_motion_policy.py` fails on an app animation that bypasses this file.
import SwiftUI

struct MotionPolicy: Equatable {
    /// The system Reduce Motion state (or, in DEBUG UI tests, its override).
    var reduceMotion: Bool

    /// The policy for the current settings; reading it inside a view (or `withObservationTracking`)
    /// tracks `systemReduceMotion`, so a change re-renders at once (ACC-001-R3).
    @MainActor init(settings: AppSettings) { reduceMotion = settings.systemReduceMotion }

    init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }

    /// The controls overlay's show/hide cross-fade (inventory A1; the badges A2-A3 ride on it).
    static let controlsSeconds = 0.2

    /// A decorative animation: nil (instant) while Reduce Motion is on.
    func decoration(_ animation: Animation) -> Animation? { reduceMotion ? nil : animation }

    /// A decorative duration for imperative code: 0 while Reduce Motion is on.
    func seconds(_ seconds: Double) -> Double { reduceMotion ? 0 : seconds }

    /// The controls transition's animation with Reduce Motion off.
    static let controlsFade = Animation.easeInOut(duration: controlsSeconds)

    /// The animation the controls transition uses.
    var controlsAnimation: Animation? { decoration(Self.controlsFade) }

    /// How long the controls transition lasts (0.2 s, or 0 with Reduce Motion).
    var controlsTransitionSeconds: Double { seconds(Self.controlsSeconds) }

    /// Marks a safety fade: returned unchanged whatever the Reduce Motion state (ACC-001-R4).
    static func safetyFade(_ animation: Animation) -> Animation { animation }
}

extension View {
    /// `.animation(_:value:)` for a decorative animation: `policy` turns it into an instant change
    /// while Reduce Motion is on. New UI animation uses this (or `policy.decoration`).
    func reduceMotionAware(_ animation: Animation, value: some Equatable, policy: MotionPolicy) -> some View {
        self.animation(policy.decoration(animation), value: value)
    }
}
