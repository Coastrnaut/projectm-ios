// CameraWhiteBalanceRow.swift — Settings › Camera › Lock white balance (CAM-006-R1 to R6, R13;
// contracts/white-balance-lock.md C4).
//
// The switch shows the white balance read back from the camera, never the requested state: a refused
// change shows the real state again. It is enabled only while the camera runs and can lock; otherwise
// it is disabled with a note naming why. The note is also the switch's accessibility hint, so
// VoiceOver reads it with the switch (R13). Choosing never starts the camera, and nothing is stored (R10).
import CameraLayer
import SwiftUI

/// What the Lock white balance row needs from the app (closures, so previews and tests can supply their own).
struct CameraWhiteBalanceChoice {
    var state: @MainActor () -> CameraWhiteBalanceState
    var setLocked: @MainActor (Bool) -> Void
}

struct CameraWhiteBalanceRow: View {
    let choice: CameraWhiteBalanceChoice

    /// The note under the switch (contract C4), nil while the switch can be used.
    static func note(for state: CameraWhiteBalanceState) -> String? {
        if !state.canLock { return "This camera can't lock white balance." }
        if !state.isRunning { return "White balance can be locked while the camera is running." }
        return nil
    }

    private var isOn: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in choice.state().isLocked },
                      set: { (locked: Bool) -> Void in choice.setLocked(locked) })
    }

    var body: some View {
        let state: CameraWhiteBalanceState = choice.state()
        let note: String? = Self.note(for: state)
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Lock white balance", isOn: isOn)
                .disabled(!state.isAdjustable)
                .accessibilityIdentifier("cameraWhiteBalanceLock")
                .accessibilityHint(note ?? "Holds the camera's current colors.")
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cameraWhiteBalanceNote")
            }
        }
    }
}

extension AppCoordinator {
    /// CAM-006-R4: locks or releases the running camera's white balance (nothing when it cannot).
    func chooseCameraWhiteBalanceLocked(_ locked: Bool) {
        cameraVisual?.setCameraWhiteBalanceLocked(locked)
    }

    var cameraWhiteBalanceChoice: CameraWhiteBalanceChoice {
        CameraWhiteBalanceChoice(
            state: { [weak self] () -> CameraWhiteBalanceState in self?.cameraWhiteBalance ?? .notRunning(canLock: false) },
            setLocked: { [weak self] (locked: Bool) -> Void in self?.chooseCameraWhiteBalanceLocked(locked) })
    }
}
