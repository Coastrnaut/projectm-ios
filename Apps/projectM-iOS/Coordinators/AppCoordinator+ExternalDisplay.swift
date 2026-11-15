// AppCoordinator+ExternalDisplay.swift — OUT-002 (spec specs/161-out-002-display-hotplug, contract
// contracts/hot-plug.md C2, C3): hot-plug wiring. A running recording holds the visual's placement
// (OUT-002-R4), and settled connections are posted as status events X27 and X28 (OUT-002-R6).
// Nothing here touches the render session, the scene, the preset or the audio source (OUT-002-R1).
// OUT-004: the stored output correction is applied at launch (ExternalOutputSetting).
// OUT-003: so are the stored output resolution and this device's pixel budget.
// OUT-007: the stored corner pin.
// OUT-006: the stored output mode; the routing's scene-overlay decision drives MED-010's logo layers.
import Foundation
import PresentationLifecycle

extension AppCoordinator {
    func connectExternalDisplay() {
        externalDisplay.follow(videoRecording)
        externalDisplay.correction = externalOutput.correction   // OUT-004: the stored choice from launch
        externalDisplay.pixelBudget = ExternalOutputSetting.devicePixelBudget   // OUT-003
        externalDisplay.resolution = externalOutput.resolution
        externalDisplay.onSceneOverlaysChange = { [weak self] (routes: Bool) -> Void in   // OUT-006-R2, R3
            self?.logo.outputSuppressed = !routes
        }
        externalDisplay.outputMode = externalOutput.outputMode
        externalDisplay.cornerPin = externalOutput.cornerPin   // OUT-007
        logo.outputSuppressed = !externalDisplay.routesSceneOverlays
        externalDisplay.onConnectionChange = { [weak self] (change: ExternalDisplayConnectionChange) -> Void in
            self?.statusEvents.post(StatusEventCatalog.externalDisplay(change))
        }
    }
}

extension ExternalDisplayCoordinator {
    /// OUT-002-R4: the placement is held exactly while `recording` records (also used by the tests).
    func follow(_ recording: VideoRecordingCoordinator) {
        recording.onStateChange = { [weak self] (state: VideoRecordingCoordinator.State) -> Void in
            self?.holdsPlacement = state == .recording
        }
        holdsPlacement = recording.state == .recording
    }
}
