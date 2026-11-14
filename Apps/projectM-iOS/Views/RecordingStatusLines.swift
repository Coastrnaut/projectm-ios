// RecordingStatusLines.swift — REC-009 recording status overlay (spec specs/190-rec-009-status-overlay,
// contract contracts/status-overlay.md C1, C2).
//
// * `RecordingStatusLines`: under the recording indicator (which shows the duration, "0:07 / 0:10"), the
//   dropped-frames line (`recordingDroppedFrames`) and the storage line (`recordingStorageStatus`), only while
//   recording. A warning carries a triangle symbol and words, and its VoiceOver label starts "Warning: " (never
//   colour alone). Nothing animates (REC-009-R5), so Reduce Motion needs no special case (ACC-001).
// * App UI only: never drawn into a recording (REC-009-R6; the recorder is fed from the visual's own Metal
//   output) and never on an external display (it sits in the device's banner stack).
// * `RecordingStatusEventChanges`: posts the coordinator's throttled `statusWarning` as X9f or X9g through
//   the status router (ACC-011), never directly.
import FrameRecording
import SwiftUI

struct RecordingStatusLines: View {
    let recording: VideoRecordingCoordinator

    var body: some View {
        if recording.state == .recording, let summary = recording.statusSummary {
            lines(summary)
        }
    }

    private func lines(_ summary: RecordingStatusSummary) -> some View {
        let storageWarned: Bool = (summary.storageLevel ?? .ok) != .ok
        return VStack(alignment: .leading, spacing: 2) {
            RecordingStatusLine(text: summary.droppedText, symbol: "film.stack", warned: summary.droppedWarning,
                                identifier: "recordingDroppedFrames")
            RecordingStatusLine(text: summary.storageText, symbol: "internaldrive", warned: storageWarned,
                                identifier: "recordingStorageStatus")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .overlaySurface(RoundedRectangle(cornerRadius: 10))   // ACC-008-R2
        .transaction { (t: inout Transaction) in t.animation = nil }   // REC-009-R5: never animated
    }
}

/// One line: a symbol (a triangle when warned) and the text; one VoiceOver element.
struct RecordingStatusLine: View {
    let text: String
    let symbol: String
    let warned: Bool
    let identifier: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: warned ? "exclamationmark.triangle.fill" : symbol)
                .foregroundStyle(warned ? Color.yellow : Color.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption.monospacedDigit())
                .fontWeight(warned ? .semibold : .regular)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(warned ? "Warning: " + text : text)
        .accessibilityIdentifier(identifier)
    }
}

/// REC-009-R4: X9f / X9g when the coordinator raises a (throttled) warning.
struct RecordingStatusEventChanges: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        content.onChange(of: coordinator.videoRecording.statusWarning, warningChanged)
    }

    private func warningChanged(_: RecordingStatusWarning?, _ warning: RecordingStatusWarning?) {
        guard let warning else { return }
        coordinator.statusEvents.post(StatusEventCatalog.recordingWarning(warning))
    }
}
