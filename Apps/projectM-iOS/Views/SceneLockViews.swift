// SceneLockViews.swift — SCN-015: the scene lock's views (specs/197-scn-015-scene-lock; R2, R6 to R8; research
// SCN-015-D4; contract L4).
//
// * `SceneLockBadge`: "Scene locked" in the visualizer's top status stack while locked, with or without the
//   controls (R7). It also presents the controls' unlock confirmation (`SceneLock.isConfirmingUnlock`), because the
//   controls can hide while it is open and the badge stays.
// * `SceneLockSection`: Settings' first section: a "Lock scene" switch; turning it off asks first (R2).
// * `SceneLockNote`: the one-line note on edit screens ("Scene locked. Unlock the scene to edit.").
// * Every unlock goes through the "Unlock scene?" confirmation; locking needs none.
import SwiftUI

extension SceneLock {
    static let unlockTitle = "Unlock scene?"
    static let unlockMessage = "Visual settings, snapshots, macros, the show's cues and undo can be edited again."
}

struct SceneLockBadge: View {
    @Bindable var lock: SceneLock

    var body: some View {
        if lock.isLocked {
            Label("Scene locked", systemImage: "lock.fill")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .statusBadgeBackground(Capsule())   // ACC-003-R9
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sceneLockBadge")
                .alert(SceneLock.unlockTitle, isPresented: $lock.isConfirmingUnlock) {
                    SceneUnlockButtons(lock: lock)
                } message: {
                    Text(SceneLock.unlockMessage)
                }
        }
    }
}

/// The confirmation's buttons (Unlock first; Cancel keeps the lock).
struct SceneUnlockButtons: View {
    let lock: SceneLock

    var body: some View {
        Button("Unlock") { lock.unlock() }.accessibilityIdentifier("sceneUnlockConfirm")
        Button("Cancel", role: .cancel) {}
    }
}

struct SceneLockSection: View {
    let lock: SceneLock
    @State private var confirming = false

    private var binding: Binding<Bool> {
        Binding(get: { () -> Bool in lock.isLocked },
                set: { (locked: Bool) -> Void in if locked { lock.lock() } else { confirming = true } })
    }

    var body: some View {
        Section {
            Toggle(isOn: binding) { Label("Lock scene", systemImage: lock.isLocked ? "lock.fill" : "lock.open") }
                .accessibilityIdentifier("sceneLockToggle")
                .accessibilityHint(lock.isLocked ? "Asks before unlocking" : "Stops edits to the scene; cues still play")
                .confirmationDialog(SceneLock.unlockTitle, isPresented: $confirming, titleVisibility: .visible) {
                    SceneUnlockButtons(lock: lock)
                } message: {
                    Text(SceneLock.unlockMessage)
                }
        } header: {
            Text("Scene lock")
        } footer: {
            Text(lock.isLocked
                 ? "Scene locked. Visual settings, layers, snapshots, macros, the show's cues and undo can't be changed. Cues, blackout, tap tempo and presets still work."
                 : "Locks the scene for a performance: edits are refused, while cues, blackout, tap tempo and presets keep working.")
        }
        .id("sceneLock")
    }
}

struct SceneLockNote: View {
    var body: some View {
        Label(SceneLock.refusalMessage, systemImage: "lock.fill")
            .font(.footnote)
            .accessibilityIdentifier("sceneLockNote")
    }
}
