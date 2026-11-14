// AppCoordinator+ExternalDisplay.swift — OUT-002 (spec specs/161-out-002-display-hotplug, contract
// contracts/hot-plug.md C2, C3): hot-plug wiring. A running recording holds the visual's placement
// (OUT-002-R4), and settled connections are posted as status events X27 and X28 (OUT-002-R6).
// Nothing here touches the render session, the scene, the preset or the audio source (OUT-002-R1).
// OUT-004: the stored output correction is applied at launch (ExternalOutputSetting).
import Foundation

extension AppCoordinator {
    func connectExternalDisplay() {
        externalDisplay.follow(videoRecording)
        externalDisplay.correction = externalOutput.correction   // OUT-004: the stored choice from launch
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
