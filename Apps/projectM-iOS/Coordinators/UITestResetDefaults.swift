// UITestResetDefaults.swift — the `-uitestResetNotice` reset of a setting's keys, which keeps the keys a launch typed
// with DEBUG `-uitestDefaults` (QA-011 device acceptance). Settings objects are often created lazily, after
// `AppCoordinator.applyUITestDefaults` wrote the typed values, so a plain reset in their init erased them: a
// Draft or Portrait recording asked for by a device test was recorded at Standard and Match screen (D2,
// 2026-11-15). The typed keys are listed under `uitest.defaults.keys`, which only the DEBUG hook writes; without
// it (Release, every ordinary launch) this is exactly `removeObject(forKey:)`.
import Foundation

extension UserDefaults {
    /// Removes `key` for the UI-test reset unless this launch typed it with `-uitestDefaults` (DEBUG only; the list
    /// key exists only in DEBUG builds, so Release stores and reads nothing new: the privacy key scan).
    func removeForUITestReset(_ key: String) {
        #if DEBUG
        if (stringArray(forKey: "uitest.defaults.keys") ?? []).contains(key) { return }
        #endif
        removeObject(forKey: key)
    }
}
