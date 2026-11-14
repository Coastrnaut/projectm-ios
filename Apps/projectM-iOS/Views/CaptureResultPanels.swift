// CaptureResultPanels.swift — the "Frame ready" and "Recording ready" panels with Save…, Share… and
// Discard, the share notice, and the DEBUG share simulation (REC-012; spec
// specs/060-rec-012-share-via-files, contracts/capture-share.md).
//
// * Each panel is one accessibility container with labeled buttons (REC-012-R13, FR-070); the system
//   share sheet is presented from behind its Share… button, so the iPad popover points at it.
// * A still and a recording can be offered at the same time, each in its own panel (REC-012-R16).
// * DEBUG `-uitestShareSimulation`: "Simulate share completed" / "Simulate share cancelled" replace the
//   system sheet, and `captureShareProbe` reads "copies=<n> frame=<yes|no> recording=<yes|no>
//   last=<outcome|none>" (REC-012-R14).
import SwiftUI

struct CaptureResultPanels: View {
    let frameCapture: FrameCaptureCoordinator
    let videoRecording: VideoRecordingCoordinator
    let share: CaptureShareCoordinator

    var body: some View {
        if let frame = frameCapture.offered {
            panel(kind: .frame, title: "Frame ready", icon: "photo",
                  save: { frameCapture.requestExport() },
                  shareAction: { _ = share.shareFrame(frame, date: frameCapture.offeredDate) },
                  discard: { frameCapture.discardOffered() })
        }
        if let recording = videoRecording.offered {
            panel(kind: .recording, title: "Recording ready", icon: "film",
                  save: { videoRecording.requestSave() },
                  shareAction: { _ = share.shareRecording(recording) },
                  discard: { videoRecording.discardOffered() })
        }
        if let notice = share.notice {   // REC-012-R11, R15 (FR-070: a labeled element)
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .accessibilityHidden(true)
                Text(notice)
                    .font(.footnote)
                    .accessibilityIdentifier("captureShareNoticeText")
                Button("Dismiss") { share.clearNotice() }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("captureShareNoticeDismiss")
            }
            .padding(10)
            .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("captureShareNotice")
        }
        #if DEBUG
        if share.simulation {
            simulationPanel
        }
        #endif
    }

    private func panel(kind: CaptureShareCoordinator.Kind, title: String, icon: String, save: @escaping () -> Void,
                       shareAction: @escaping () -> Void, discard: @escaping () -> Void) -> some View {
        let prefix = kind == .frame ? "frameResult" : "recordingResult"
        let noun = kind == .frame ? "frame" : "recording"
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(title)
                .font(.footnote.bold())
            Button("Save…", action: save)
                .accessibilityLabel("Save the \(noun) to Files")
                .accessibilityIdentifier("\(prefix)Save")
            Button("Share…", action: shareAction)
                .accessibilityLabel("Share the \(noun)")
                .accessibilityIdentifier("\(prefix)Share")
                .background {
                    if !share.simulation {
                        ActivitySharePresenter(request: share.request, kind: kind) { (outcome: ShareOutcome) in share.finish(outcome) }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            Button("Discard", role: .destructive, action: discard)
                .foregroundStyle(OverlayContrast.criticalText)   // ACC-008-R5: system red missed 4.5:1 on the overlay
                .accessibilityLabel("Discard the \(noun)")
                .accessibilityIdentifier("\(prefix)Discard")
        }
        .font(.footnote)
        .padding(10)
        .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(prefix)
    }

    #if DEBUG
    /// UI tests: the system sheet cannot be driven, so the outcome is delivered here (REC-012-R14).
    private var simulationPanel: some View {
        let value = "copies=\(share.copyCount) frame=\(frameCapture.offered != nil ? "yes" : "no") "
            + "recording=\(videoRecording.offered != nil ? "yes" : "no") last=\(share.lastOutcome?.rawValue ?? "none")"
        return VStack(spacing: 4) {
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("captureShareProbe")
                .accessibilityValue(value)
            if share.request != nil {
                HStack {
                    Button("Simulate share completed") { share.finish(.completed) }
                        .accessibilityIdentifier("simulateShareCompleted")
                    Button("Simulate share cancelled") { share.finish(.cancelled) }
                        .accessibilityIdentifier("simulateShareCancelled")
                }
                .font(.caption)
            }
        }
    }
    #endif
}
