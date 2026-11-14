// StatusCaptionView.swift — the transient status caption and the visualizer's status-event changes
// (ACC-011; contract specs/100-acc-011-captioned-status-events/contracts/status-events.md C1, C3).
//
// * `StatusCaptionView`: the router's caption ("Camera off", "OSC off", "Output restored", "Last scene
//   reopened.") for 4 s; static text with identifier `statusCaption`, wrapping at accessibility sizes
//   (ACC-006), shown and hidden without animation (ACC-011-R7).
// * `StatusEventChanges`: the `.onChange`s that post rows X6-X14a and X21-X23, kept out of
//   VisualizerView's body (one modifier line there).
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                .accessibilityLabel(caption)
                .accessibilityIdentifier("statusCaption")
        }
    }
}

/// Posts the recording, frame capture, sharing and blackout rows when their state changes.
struct StatusEventChanges: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        content
            // X21-X23 (ACC-004-R5 texts, research D3): by phase, whichever control or key caused it.
            .onChange(of: coordinator.externalDisplay.blackoutPhase) { _, phase in
                post(StatusEventCatalog.blackout(phase))
            }
            // X9, X10: entering recording or finishing (a direct recording → idle also says "Recording stopped").
            .onChange(of: coordinator.videoRecording.state) { old, new in
                let state: VideoRecordingCoordinator.State = new == .idle && old == .recording ? .finishing : new
                if state != .idle {
                    post(StatusEventCatalog.recording(state, elapsed: coordinator.videoRecording.elapsedText))
                }
            }
            .onChange(of: coordinator.videoRecording.notice) { _, notice in   // X12-X14a
                if let notice { post(StatusEventCatalog.recordingNotice(notice)) }
            }
            .onChange(of: coordinator.videoRecording.offered != nil) { _, offered in   // X11
                if offered { post(StatusEventCatalog.recording(.idle)) }
            }
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

    private func post(_ event: StatusEvent) {
        coordinator.statusEvents.post(event)
    }
}
