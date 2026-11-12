// Previews.swift — SwiftUI previews for the shared views (task T033): the chooser with every mode
// in both availability variants, the banner with every StopReason message and every state, and the
// microphone explainer. Strings come from UIStrings, which matches contracts/ui-states.md.
#if canImport(SwiftUI)
import AudioCore
import CaptureKit
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

    /// Two imported tracks, newest first (AUD-001).
    static let importedTracks: [ImportedTrack] = [("Evening Set", 3725.0), ("Test Tone", 185.0)].enumerated().map { index, item in
        let digest = String(repeating: index == 0 ? "ab" : "cd", count: 32)
        return ImportedTrack(id: UUID(), title: item.0, originalFileName: "\(item.0).m4a", sha256: digest,
                             fileName: "\(digest).m4a", byteCount: 1_000_000, durationSeconds: item.1, sampleRate: 44_100,
                             channelCount: 2, importedAt: Date(timeIntervalSince1970: 1_794_477_600))
    }

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

#Preview("Chooser — with imported audio (AUD-001)") {
    SourceChooserView(availability: PreviewFixtures.allAvailable, onSelect: { _ in }, extraSections: {
        ImportedAudioSection(tracks: PreviewFixtures.importedTracks, isImporting: false,
                             onImport: {}, onPlay: { _ in }, onRemove: { _ in })
    })
}

#Preview("Chooser — importing, empty library") {
    SourceChooserView(availability: PreviewFixtures.allAvailable, onSelect: { _ in }, extraSections: {
        ImportedAudioSection(tracks: [], isImporting: true, onImport: {}, onPlay: { _ in }, onRemove: { _ in })
    })
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
