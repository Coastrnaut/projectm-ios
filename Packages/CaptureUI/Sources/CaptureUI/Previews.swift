// Previews.swift — SwiftUI previews for the shared views (task T033): the chooser with every mode
// in both availability variants, the banner with every StopReason message and every state, and the
// microphone explainer. Strings come from UIStrings, which matches contracts/ui-states.md.
#if canImport(SwiftUI)
import AudioCore
import SwiftUI

enum PreviewFixtures {
    /// Every StopReason, once each; `.error` carries an example description.
    /// ViewRenderTests.testFixturesCoverEveryStopReason compares this list with an exhaustive
    /// switch over StopReason, so a new case must be added both there and here.
    static let stopReasons: [StopReason] = [
        .cancelled, .permissionDenied, .microphoneUnavailable, .inAppPlaybackFailed, .interrupted,
        .audioRouteChanged, .endedBySystem, .unsupportedOS, .screenRecordingNotAllowed,
        .error("Example description"),
    ]

    /// iOS 27 or later: every mode available.
    static let allAvailable: [AudioSourceMode: SourceAvailability] =
        Dictionary(uniqueKeysWithValues: AudioSourceMode.allCases.map { ($0, .available) })

    /// iOS 26: System/App Capture unavailable, fallbacks available (FR-004).
    static let iOS26: [AudioSourceMode: SourceAvailability] = [
        .systemAppCapture: .unavailable(.unsupportedOS), .microphone: .available, .inAppPlayback: .available,
    ]

    /// iOS 27 or later with screen recording not allowed on the device (FR-004).
    static let notAllowed: [AudioSourceMode: SourceAvailability] = [
        .systemAppCapture: .unavailable(.screenRecordingNotAllowed), .microphone: .available,
        .inAppPlayback: .available,
    ]

    static func state(for reason: StopReason) -> AudioState {
        reason == .endedBySystem ? .endedBySystem : .stopped
    }
}

#Preview("Chooser — iOS 27, all modes available") {
    SourceChooserView(availability: PreviewFixtures.allAvailable) { _ in }
}

#Preview("Chooser — iOS 26, capture unavailable") {
    SourceChooserView(availability: PreviewFixtures.iOS26) { _ in }
}

#Preview("Chooser — iOS 27, screen recording not allowed") {
    SourceChooserView(availability: PreviewFixtures.notAllowed) { _ in }
}

#Preview("Banner — every StopReason") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(Array(PreviewFixtures.stopReasons.enumerated()), id: \.offset) { _, reason in
                StatusBanner(mode: .systemAppCapture, state: PreviewFixtures.state(for: reason), reason: reason,
                             prolongedSilence: false) { _ in }
            }
        }
        .padding()
    }
}

#Preview("Banner — every state") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(AudioState.allCases, id: \.self) { state in
                StatusBanner(mode: .microphone, state: state, reason: nil, prolongedSilence: state == .silent) { _ in }
            }
        }
        .padding()
    }
}

#Preview("Microphone explainer") {
    MicrophoneExplainerView(onContinue: {}, onCancel: {})
}
#endif
