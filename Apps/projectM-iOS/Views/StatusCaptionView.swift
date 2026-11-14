// StatusCaptionView.swift — the transient status caption and the visualizer's status-event changes
// (ACC-011; contract specs/100-acc-011-captioned-status-events/contracts/status-events.md C1, C3).
//
// * `StatusCaptionView`: the router's caption ("Camera off", "OSC off", "Output restored", "Last scene
//   reopened.") for 4 s; static text with identifier `statusCaption`, wrapping at accessibility sizes
//   (ACC-006), shown and hidden without animation (ACC-011-R7).
// * `StatusEventChanges`: the `.onChange`s that post rows X6-X14a and X21-X23, kept out of
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

    // Three typed steps in the original order: one chain of seven `onChange`s took 229 ms to type-check
    // (budget 200 ms, 2026-11-14; CI's Xcode 26 gives up on long chains).
    func body(content: Content) -> some View {
        captureChanges(recordingResultChanges(recordingChanges(content)))
    }

    /// Blackout and recording state rows (X9, X10, X21-X23).
    private func recordingChanges(_ view: some View) -> some View {
        view
            // X21-X23 (ACC-004-R5 texts, research D3): by phase, whichever control or key caused it.
            .onChange(of: coordinator.externalDisplay.blackoutPhase) { (_: OutputBlackout.Phase, phase: OutputBlackout.Phase) in
                post(StatusEventCatalog.blackout(phase))
            }
            // X9, X10: entering recording or finishing (a direct recording → idle also says "Recording stopped").
            .onChange(of: coordinator.videoRecording.state) { (old: VideoRecordingCoordinator.State, new: VideoRecordingCoordinator.State) in
                recordingStateChanged(from: old, to: new)
            }
    }

    /// Recording notices and the finished recording's offer (X11-X14a).
    private func recordingResultChanges(_ view: some View) -> some View {
        view
            .onChange(of: coordinator.videoRecording.notice) { _, notice in   // X12-X14a
                if let notice { post(StatusEventCatalog.recordingNotice(notice)) }
            }
            .onChange(of: coordinator.videoRecording.offered != nil) { _, offered in   // X11
                if offered { post(StatusEventCatalog.recording(.idle)) }
            }
    }

    /// Frame capture and sharing rows (X6-X8).
    private func captureChanges(_ view: some View) -> some View {
        view
            .onChange(of: coordinator.frameCapture.notice) { _, notice in   // X6
                if let notice { post(StatusEventCatalog.frameNotice(notice)) }
            }
            .onChange(of: coordinator.frameCapture.offered != nil) { _, offered in   // X7
                if offered { post(StatusEventCatalog.frameOffered()) }
            }
            .onChange(of: coordinator.captureShare.notice) { _, notice in   // X8
                if let notice { post(StatusEventCatalog.shareNotice(notice)) }
            }
    }

    private func recordingStateChanged(from old: VideoRecordingCoordinator.State, to new: VideoRecordingCoordinator.State) {
        let state: VideoRecordingCoordinator.State = new == .idle && old == .recording ? .finishing : new
        if state != .idle {
            post(StatusEventCatalog.recording(state, elapsed: coordinator.videoRecording.elapsedText))
        }
    }

    private func post(_ event: StatusEvent) {
        coordinator.statusEvents.post(event)
    }
}
