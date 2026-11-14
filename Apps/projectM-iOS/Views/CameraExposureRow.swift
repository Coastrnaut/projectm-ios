// CameraExposureRow.swift — Settings › Camera › Lock exposure (CAM-004-R1 to R5, R11;
// contracts/exposure-lock.md C4).
//
// The switch shows the exposure read back from the camera, never the requested state: a refused
// change shows the real state again. It is enabled only while the camera runs and can lock; otherwise
// it is disabled with a note naming why. The note is also the switch's accessibility hint, so
// VoiceOver reads it with the switch (R11). Choosing never starts the camera, and nothing is stored (R8).
import CameraLayer
import SwiftUI

/// What the Lock exposure row needs from the app (closures, so previews and tests can supply their own).
struct CameraExposureChoice {
    var state: @MainActor () -> CameraExposureState
    var setLocked: @MainActor (Bool) -> Void
}

struct CameraExposureRow: View {
    let choice: CameraExposureChoice

    /// The note under the switch (contract C4), nil while the switch can be used.
    static func note(for state: CameraExposureState) -> String? {
        if !state.canLock { return "This camera can't lock exposure." }
        if !state.isRunning { return "Exposure can be locked while the camera is running." }
        return nil
    }

    private var isOn: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in choice.state().isLocked },
                      set: { (locked: Bool) -> Void in choice.setLocked(locked) })
    }

    var body: some View {
        let state: CameraExposureState = choice.state()
        let note: String? = Self.note(for: state)
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Lock exposure", isOn: isOn)
                .disabled(!state.isAdjustable)
                .accessibilityIdentifier("cameraExposureLock")
                .accessibilityHint(note ?? "Holds the camera's current brightness.")
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cameraExposureNote")
            }
        }
    }
}

extension AppCoordinator {
    /// CAM-004-R4: locks or releases the running camera's exposure (nothing when it cannot).
    func chooseCameraExposureLocked(_ locked: Bool) {
        cameraVisual?.setCameraExposureLocked(locked)
    }

    var cameraExposureChoice: CameraExposureChoice {
        CameraExposureChoice(state: { [weak self] () -> CameraExposureState in self?.cameraExposure ?? .notRunning(canLock: false) },
                             setLocked: { [weak self] (locked: Bool) -> Void in self?.chooseCameraExposureLocked(locked) })
    }
}
