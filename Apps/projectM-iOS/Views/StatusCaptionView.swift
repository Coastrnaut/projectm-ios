// StatusCaptionView.swift — the transient status caption and the visualizer's status-event changes
// (ACC-011; contract specs/100-acc-011-captioned-status-events/contracts/status-events.md C1, C3).
//
// * `StatusCaptionView`: the router's caption ("Camera off", "OSC off", "Output restored", "Last scene
//   reopened.") for 4 s; static text with identifier `statusCaption`, wrapping at accessibility sizes
//   (ACC-006), shown and hidden without animation (ACC-011-R7).
// * `StatusEventChanges`: the `.onChange`s that post rows X6-X14a (X9d, X9e: REC-007) and X21-X23, kept out of
//   VisualizerView's body (one modifier line there).
import PresentationLifecycle
import SwiftUI

struct StatusCaptionView: View {
    let router: StatusEventRouter

    var body: some View {
        if let caption = router.caption {
            Text(caption)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
                .allowsHitTesting(false)
                .accessibilityLabel(caption)
                .accessibilityIdentifier("statusCaption")
        }
    }
}

/// Posts the recording, frame capture, sharing and blackout rows when their state changes.
struct StatusEventChanges: ViewModifier {
    let coordinator: AppCoordinator

    // Each change calls a method (REC-004: keeps this body within the type-check budget).
    func body(content: Content) -> some View {
        content
            // X21-X23 (ACC-004-R5 texts, research D3): by phase, whichever control or key caused it.
            .onChange(of: coordinator.externalDisplay.blackoutPhase, blackoutChanged)
            // X9, X10: entering recording or finishing (a direct recording → idle also says "Recording stopped").
            .onChange(of: coordinator.videoRecording.state, recordingStateChanged)
            .modifier(RecordingResultChanges(coordinator: coordinator))   // X11-X14a
            .modifier(CaptureEventChanges(coordinator: coordinator))   // X6-X8
            .modifier(RecordingAudioEventChanges(coordinator: coordinator))   // REC-004 X9a, X9b
    }

    private func blackoutChanged(_: OutputBlackout.Phase, _ phase: OutputBlackout.Phase) {
        post(StatusEventCatalog.blackout(phase))
    }

    private func recordingStateChanged(_ old: VideoRecordingCoordinator.State, _ new: VideoRecordingCoordinator.State) {
        let recording: VideoRecordingCoordinator = coordinator.videoRecording
        if let event = StatusEventCatalog.recordingTransition(from: old, to: new, elapsed: recording.elapsedText,
                                                              countdownCancel: recording.lastCountdownCancel) {
            post(event)
        }
    }

    private func post(_ event: StatusEvent) {
        coordinator.statusEvents.post(event)
    }
}

/// REC-004-R9: X9a when a recording starts (its audio status), X9b when its audio ends early. Its own
/// modifier keeps `StatusEventChanges.body` within the type-check budget.
struct RecordingAudioEventChanges: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: coordinator.videoRecording.state) { (_: VideoRecordingCoordinator.State, new: VideoRecordingCoordinator.State) in
                guard new == .recording, let audio = coordinator.videoRecording.recordingAudio else { return }
                coordinator.statusEvents.post(StatusEventCatalog.recordingAudio(audio))
            }
            .onChange(of: coordinator.videoRecording.audioEnded) { (_: Bool, ended: Bool) in
                if ended { coordinator.statusEvents.post(StatusEventCatalog.recordingAudioEnded()) }
            }
    }
}

/// X6-X8: frame capture and sharing (split from `StatusEventChanges` for the type-check budget, REC-004).
struct CaptureEventChanges: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: coordinator.frameCapture.notice) { (_: String?, notice: String?) in   // X6
                if let notice { post(StatusEventCatalog.frameNotice(notice)) }
            }
            .onChange(of: coordinator.frameCapture.offered != nil) { (_: Bool, offered: Bool) in   // X7
                if offered { post(StatusEventCatalog.frameOffered()) }
            }
            .onChange(of: coordinator.captureShare.notice) { (_: String?, notice: String?) in   // X8
                if let notice { post(StatusEventCatalog.shareNotice(notice)) }
            }
    }

    private func post(_ event: StatusEvent) {
        coordinator.statusEvents.post(event)
    }
}

/// X11-X14a: the recording's notices and the offered result (split for the type-check budget, REC-004); REC-009's
/// X9f, X9g ride here (the parent chain is at the budget).
struct RecordingResultChanges: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: coordinator.videoRecording.notice, noticeChanged)   // X12-X14a
            .onChange(of: coordinator.videoRecording.offered != nil, offeredChanged)   // X11
            .modifier(RecordingStatusEventChanges(coordinator: coordinator))   // REC-009 X9f, X9g
    }

    private func noticeChanged(_: String?, _ notice: String?) {
        if let notice { coordinator.statusEvents.post(StatusEventCatalog.recordingNotice(notice)) }
    }

    private func offeredChanged(_: Bool, _ offered: Bool) {
        if offered { coordinator.statusEvents.post(StatusEventCatalog.recording(.idle)) }
    }
}
