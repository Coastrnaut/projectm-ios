// CameraLensRow.swift — Settings › Camera › Lens (CAM-003-R2, R5, R6, R11; contracts/lens-selection.md C3).
//
// The row lists exactly the back lenses this device has, and only for Back with at least two lenses:
// an unavailable lens is hidden, never disabled. It shows the lens actually running when the Camera
// visual exists (so a lens that could not be opened reverts on screen to the previous one), else the
// stored lens resolved against the device (a lens the device lacks shows as Wide). Choosing a lens
// stores it and forwards it to the running camera at once; it never starts the camera. When the
// switch ends on another lens (the chosen one could not be opened), the stored choice follows it.
import CameraLayer
import SwiftUI

/// What the Lens row needs from the app (closures, so previews and tests can supply their own).
struct CameraLensChoice {
    var offered: @MainActor () -> [CameraLens]
    var shown: @MainActor () -> CameraLens
    var choose: @MainActor (CameraLens) -> Void
}

struct CameraLensRow: View {
    let choice: CameraLensChoice

    private var selection: Binding<CameraLens> {
        Binding<CameraLens>(get: { () -> CameraLens in choice.shown() },
                            set: { (lens: CameraLens) -> Void in choice.choose(lens) })
    }

    var body: some View {
        let lenses: [CameraLens] = choice.offered()
        if lenses.count >= 2 {
            Picker("Lens", selection: selection) {
                ForEach(lenses, id: \.self) { (lens: CameraLens) in
                    Text(lens.title).tag(lens)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Lens")
            .accessibilityValue(choice.shown().title)
            .accessibilityIdentifier("cameraLensPicker")
        }
    }
}

extension AppCoordinator {
    /// CAM-003-R2: the lenses the row offers (none for Front or a one-lens device).
    var offeredCameraLenses: [CameraLens] {
        cameraLensInventory.offeredLenses(for: settings.cameraPosition)
    }

    /// CAM-003-R5, R6: the running lens while the Camera visual exists, else the stored lens resolved.
    var shownCameraLens: CameraLens {
        _ = cameraState   // observed: an asynchronous lens switch ends in a state change
        _ = settings.cameraLens   // observed: a choice re-reads the running lens (a failed switch shows the previous)
        if let host = cameraVisual, settings.cameraPosition == .back { return host.cameraLens }
        return cameraLensInventory.resolve(settings.cameraLens)
    }

    /// CAM-003-R4, R6: stores the lens and switches the running camera at once.
    func chooseCameraLens(_ lens: CameraLens) {
        settings.cameraLens = lens
        cameraSettingsChanged()
        cameraLensChoicePending = true
        reconcileCameraLensChoice()
    }

    /// CAM-003-R6: once the user's switch has ended on the running back camera, the stored choice
    /// follows the lens actually running (a lens that could not be opened returns to the previous
    /// one). Only after a user's choice: a lens the device lacks keeps its stored value (R5).
    func reconcileCameraLensChoice() {
        guard cameraLensChoicePending, let host = cameraVisual, host.feedState != .starting else { return }
        cameraLensChoicePending = false
        guard settings.cameraPosition == .back, host.feedState == .running, host.cameraLens != settings.cameraLens else { return }
        settings.cameraLens = host.cameraLens
    }

    var cameraLensChoice: CameraLensChoice {
        CameraLensChoice(offered: { [weak self] () -> [CameraLens] in self?.offeredCameraLenses ?? [] },
                         shown: { [weak self] () -> CameraLens in self?.shownCameraLens ?? .wide },
                         choose: { [weak self] (lens: CameraLens) -> Void in self?.chooseCameraLens(lens) })
    }
}
