// AppCoordinator+GestureShortcuts.swift — UIX-006-R6, R7 (specs/290-uix-006-touch-gesture-mapping, contract G3;
// research UIX-006-D4): a recognised touch sequence is resolved with the stored mapping and the live VoiceOver state,
// and the winner runs through `GestureShortcutPerformer` (the existing controls' paths, quietly).
import PerformanceControl
import UIKit

extension AppCoordinator {
    /// Resolves one touch sequence's recognised gestures, runs the winner and returns it (nil: nothing ran, the touch
    /// stays with the controls tap).
    @discardableResult
    func handleGestureShortcut(_ recognised: Set<PerformanceGesture>,
                               voiceOverRunning: Bool = UIAccessibility.isVoiceOverRunning) -> GestureShortcutResolution? {
        guard let winner = GestureShortcutResolver.resolve(recognised, configuration: gestureShortcuts.configuration,
                                                           voiceOverRunning: voiceOverRunning) else { return nil }
        gestureShortcutPerformer.perform(winner.action)
        return winner
    }

    func makeGestureShortcutsSetting(defaults: UserDefaults) -> GestureShortcutsSetting {
        let lock: SceneLock = settings.sceneLock
        return GestureShortcutsSetting(defaults: defaults, lock: lock)
    }

    func makeGestureShortcutPerformer() -> GestureShortcutPerformer {
        let performer = GestureShortcutPerformer(
            show: show, presets: presets, tempo: tempo, hud: sceneHUD,
            announcePresetChange: { [weak self] (change: @escaping () async -> Void) async -> Void in
                await self?.announcingPresetChange(change)
            })
        performer.didPerform = { [weak self, unowned performer] () -> Void in
            self?.lastGestureShortcut = performer.last
            self?.gestureShortcutCount = performer.count
        }
        return performer
    }
}
