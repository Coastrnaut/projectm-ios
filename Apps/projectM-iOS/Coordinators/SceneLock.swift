// SceneLock.swift — SCN-015: the scene lock (specs/197-scn-015-scene-lock; R1 to R4, R8; research SCN-015-D1, D2, D5;
// contract L1).
//
// * One Boolean on the device, key `settings.scene.locked` (absent → unlocked). Owned by `AppSettings`, so every
//   holder of the settings (Settings, the inspector, the shelf, macros, snapshots) reads the same lock.
// * `refusesEdit()` is the single choke point: every coordinator API that writes the scene (the Settings targets,
//   macros, snapshots, the show's edits, undo/redo) calls it first and changes nothing when it returns true. It
//   records the refusal and announces it (library lane, ACC-004). Navigation (cues, blackout, tempo, presets,
//   MIDI/OSC values) never calls it.
// * `lock()` and `unlock()` announce "Scene locked" / "Scene unlocked". The deliberate unlock (a confirmation) is
//   the views' job (`SceneLockViews`); this model only records the state.
// * Excluded from library backups (FILE-005): session state of this device.
import Foundation
import Observation

@MainActor
@Observable
final class SceneLock {
    static let key = "settings.scene.locked"
    static let refusalMessage = "Scene locked. Unlock the scene to edit."
    static let lockedAnnouncement = "Scene locked"
    static let unlockedAnnouncement = "Scene unlocked"

    private(set) var isLocked: Bool
    /// The last refusal's message (nil until an edit is refused while locked).
    private(set) var lastRefusal: String?
    /// How many edits were refused (tests and DEBUG probes).
    private(set) var refusals = 0
    /// The controls asked for the unlock confirmation (`SceneLockBadge` presents it; R2).
    var isConfirmingUnlock = false

    @ObservationIgnored private let defaults: UserDefaults
    /// VoiceOver announcements (AppCoordinator routes them to the announcer's library lane).
    @ObservationIgnored var announce: (String) -> Void = { (_: String) in }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isLocked = defaults.bool(forKey: Self.key)
    }

    func lock() { set(true) }

    /// Call only after the user confirmed (R2).
    func unlock() { set(false) }

    private func set(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        if locked { defaults.set(true, forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
        announce(locked ? Self.lockedAnnouncement : Self.unlockedAnnouncement)
    }

    /// True (and the refusal reported) when the scene is locked; false, with no effect, when it is not.
    func refusesEdit() -> Bool {
        guard isLocked else { return false }
        refusals += 1
        lastRefusal = Self.refusalMessage
        announce(Self.refusalMessage)
        return true
    }

    /// The accessibility value of the lock controls.
    var accessibilityValue: String { isLocked ? "Locked" : "Unlocked" }
}
