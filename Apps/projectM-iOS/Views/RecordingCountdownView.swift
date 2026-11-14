// RecordingCountdownView.swift — REC-007-R7: the countdown on the visualizer's screen.
//
// The remaining number ("Recording in 3"; identifier `recordingCountdown`) and a Cancel button
// (`recordingCountdownCancel`; Escape on a hardware keyboard through `.cancelAction`). App UI only, never in
// the recorded picture or on an external display (it sits with the recording indicator). Nothing animates:
// the number is replaced in place, so Reduce Motion needs no special case (ACC-001). The announcements are
// posted by `StatusEventChanges` (rows X9d, X9e), not here.
import SwiftUI

struct RecordingCountdownView: View {
    let recording: VideoRecordingCoordinator

    var body: some View {
        if let remaining = recording.state.countdownRemaining {
            content(remaining)
        }
    }

    private func content(_ remaining: Int) -> some View {
        let label: String = StatusEventCatalog.countdownText(remaining)
        return HStack(spacing: 14) {
            Text(String(remaining))
                .font(.largeTitle.monospacedDigit().bold())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(String(remaining))
                .accessibilityIdentifier("recordingCountdown")
            Button("Cancel") { recording.cancelCountdown(.user) }
                .font(.body.bold())
                .keyboardShortcut(.cancelAction)   // REC-007-R4: Escape
                .accessibilityHint("Stops the countdown; nothing is recorded")
                .accessibilityIdentifier("recordingCountdownCancel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlaySurface(RoundedRectangle(cornerRadius: 14))   // ACC-008-R2
        .transaction { (t: inout Transaction) in t.animation = nil }   // REC-007-R7: never animated
    }
}
