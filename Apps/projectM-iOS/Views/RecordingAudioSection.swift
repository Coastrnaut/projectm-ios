// RecordingAudioSection.swift — REC-004-R9, R13: Settings → Recording.
//
// The "Include microphone audio" toggle (off by default; never asks for the microphone permission), a
// footer saying what recordings contain, and the next recording's audio status as plain text
// (`recordingAudioStatus`). Strings come from `RecordingAudioSetting` and `RecordingAudioDecision`.
import SwiftUI

struct RecordingAudioSection: View {
    @Bindable var setting: RecordingAudioSetting
    /// The audio the next recording would contain (nil in previews).
    let status: (() -> String)?

    private static let title = "Recording"

    var body: some View {
        Section {
            Toggle(RecordingAudioSetting.toggleTitle, isOn: $setting.includeMicrophone)
                .accessibilityIdentifier("recordingMicrophoneToggle")
            statusRow
        } header: {
            Text(Self.title)
        } footer: {
            Text(RecordingAudioSetting.footer)
        }
    }

    @ViewBuilder private var statusRow: some View {
        if let status {
            let text: String = status()
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recordingAudioStatus")
        }
    }
}

/// REC-004-R9: the line under the recording indicator naming the audio this recording holds.
struct RecordingAudioLine: View {
    let recording: VideoRecordingCoordinator

    var body: some View {
        if recording.state == .recording {
            let text: String = recording.audioStatusText
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlaySurface(Capsule())   // ACC-008-R2
                .accessibilityIdentifier("recordingAudioLine")
        }
    }
}
