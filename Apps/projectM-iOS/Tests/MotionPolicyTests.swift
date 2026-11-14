// MotionPolicyTests.swift — ACC-001-T03 (specs/080-acc-001-reduce-motion-mode; ACC-001-R2 to R5,
// S1-S3). The policy turns decorative animations instant with Reduce Motion on and leaves safety
// fades alone; a change of the system state reaches observers at once; Reduce flashing still follows
// Reduce Motion when set to "Follow system" (FR-072). No clock is read.
import Compositor
import Observation
import SwiftUI
import XCTest
@testable import projectM_iOS

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func set() { lock.withLock { raised = true } }
}

@MainActor
final class MotionPolicyTests: XCTestCase {
    private func settings(reduceMotion: Bool) -> (AppSettings, () -> Void) {
        let suite = "MotionPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppSettings(defaults: defaults, systemReduceMotion: reduceMotion), { defaults.removePersistentDomain(forName: suite) })
    }

    func testReduceMotionOnMakesDecorationInstant() {
        let policy = MotionPolicy(reduceMotion: true)
        XCTAssertNil(policy.decoration(.easeInOut(duration: 0.3)))
        XCTAssertNil(policy.controlsAnimation)
        XCTAssertEqual(policy.seconds(0.3), 0)
        XCTAssertEqual(policy.controlsTransitionSeconds, 0)
    }

    /// CMP-014-T11: a scene crossfade is decorative: a cut with Reduce Motion on, unchanged with it off.
    func testSceneTransitionIsACutWithReduceMotion() throws {
        let fade = try SceneTransitionSpec(style: .dipToBlack, durationSeconds: 2)
        XCTAssertEqual(MotionPolicy(reduceMotion: true).sceneTransition(fade), .cut)
        XCTAssertEqual(MotionPolicy(reduceMotion: true).sceneTransition(.defaultCrossfade), .cut)
        XCTAssertEqual(MotionPolicy(reduceMotion: false).sceneTransition(fade), fade)
        XCTAssertEqual(MotionPolicy(reduceMotion: false).sceneTransition(.cut), .cut)
    }

    func testReduceMotionOffKeepsDecoration() {
        let policy = MotionPolicy(reduceMotion: false)
        XCTAssertEqual(policy.decoration(.easeInOut(duration: 0.3)), .easeInOut(duration: 0.3))
        XCTAssertEqual(policy.controlsAnimation, MotionPolicy.controlsFade)
        XCTAssertEqual(policy.seconds(0.3), 0.3)
        XCTAssertEqual(policy.controlsTransitionSeconds, 0.2)
    }

    func testSafetyFadeIsNeverShortened() {
        let fade = Animation.linear(duration: RenderPlaceholder.fadeSeconds)
        XCTAssertEqual(MotionPolicy.safetyFade(fade), fade)
        XCTAssertEqual(RenderPlaceholder.fadeSeconds, 0.5, "PERF-014-R10's placeholder fade is unchanged")
    }

    /// S2: a view reading the policy is invalidated by the very change of the system state.
    func testSystemChangeReachesObserversAtOnce() {
        let (settings, cleanup) = settings(reduceMotion: false)
        defer { cleanup() }
        let invalidated = Flag()
        let before = withObservationTracking { MotionPolicy(settings: settings) } onChange: { invalidated.set() }
        XCTAssertFalse(before.reduceMotion)
        settings.systemReduceMotion = true
        XCTAssertTrue(invalidated.value, "the change invalidates readers synchronously")
        XCTAssertEqual(MotionPolicy(settings: settings).controlsTransitionSeconds, 0)
    }

    /// R5 / FR-072: Reduce flashing keeps following Reduce Motion on "Follow system", and an explicit
    /// Reduce flashing choice is independent of the motion policy.
    func testReduceFlashingStillFollowsAndStaysIndependent() {
        let (settings, cleanup) = settings(reduceMotion: false)
        defer { cleanup() }
        XCTAssertFalse(settings.reduceFlashing)
        settings.systemReduceMotion = true
        XCTAssertTrue(settings.reduceFlashing)
        settings.reduceFlashing = false
        XCTAssertTrue(MotionPolicy(settings: settings).reduceMotion, "motion follows the system, not Reduce flashing")
    }
}
