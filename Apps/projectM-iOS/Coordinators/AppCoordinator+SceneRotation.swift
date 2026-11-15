// AppCoordinator+SceneRotation.swift — SHOW-013: auto scene rotation's link to the show, the tempo and the safety
// settings (specs/256-show-013-auto-scene-rotation; R3, R6; research SHOW-013-D3, D5).
//
// * Holds: SHOW-002's driver's (Hold, pause, blackout, repair report, background) and "a timed cue counts down unheld"
//   (the show plays on its timeline: rotation waits).
// * Bar lines come from SHOW-011's tempo snapshot; Reduce flashing is read at each arm.
// * DEBUG `-uitestSceneRotation <seconds>`: rotation on at launch with that timer interval and seed 1 (UI tests only).
import Foundation
import PerformanceControl

extension AppCoordinator {
    func makeSceneRotation(defaults: UserDefaults) -> SceneRotationCoordinator {
        let driver: ShowAutoAdvanceCoordinator = showAutoAdvance   // first: rotation chains after its `cueStarted`
        let rotation = SceneRotationCoordinator(show: show, defaults: defaults)
        rotation.tempo = { [weak self] () -> TempoSnapshot in self?.tempo.snapshot ?? .none }
        rotation.reduceFlashing = { [weak self] () -> Bool in self?.settings.reduceFlashing ?? true }
        rotation.isHeld = { [weak driver] () -> Bool in
            guard let driver else { return true }
            return driver.isOperatorHeld || driver.isHeld()
        }
        rotation.showPlays = { [weak driver] () -> Bool in
            guard let countdown = driver?.countdown else { return false }
            return !countdown.held
        }
        #if DEBUG
        Self.applyRotationTestArgument(rotation)
        #endif
        return rotation
    }

    #if DEBUG
    /// `-uitestSceneRotation <seconds>`: on at launch, fixed seed, the given timer interval.
    private static func applyRotationTestArgument(_ rotation: SceneRotationCoordinator) {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uitestSceneRotation"), index + 1 < arguments.count,
              let seconds = Int(arguments[index + 1]), seconds > 0 else { return }
        rotation.intervalOverrideSeconds = seconds
        rotation.makeSeed = { () -> UInt64 in 1 }
        rotation.setOn(true)
    }
    #endif
}
