// VideoReverseControls.swift — reverse playback of the stored video in Settings → Video (MED-005-R1, R5; spec
// Clarifications 2026-11-14).
//
// * One "Reverse" switch under Speed, shown whenever a video is stored. Turning it on saves and applies at once
//   (VideoCoordinator.setReverse); the clip plays forward until its reverse cache is ready.
// * The caption under it reads "Preparing reverse…" while the cache is built, or the sentence explaining why this clip
//   plays forward (over 30 seconds, larger than 1080p, can't be read). It wraps at accessibility text sizes and has no
//   animation of its own.
// Bodies are kept small (CI's Xcode 26 type-checks each one).
import SwiftUI

struct VideoReverseControls: View {
    let videos: VideoCoordinator

    var body: some View {
        if videos.video != nil {
            Toggle("Reverse", isOn: binding)
                .accessibilityIdentifier("videoReverseToggle")
            if let caption = videos.reverseCaption {
                captionText(caption)
            }
        }
    }

    private var binding: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in videos.reverse },
                      set: { (on: Bool) -> Void in videos.setReverse(on) })
    }

    private func captionText(_ caption: String) -> some View {
        Text(caption)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("videoReverseStatus")
    }
}
