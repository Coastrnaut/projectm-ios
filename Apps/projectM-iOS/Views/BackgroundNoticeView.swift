// BackgroundNoticeView.swift — what happened to the source while the app was away (AUD-015-R7).
// Non-blocking, under the status; announced to VoiceOver once; clears itself after 8 s or on
// Dismiss. The timer starts only when the notice is visible (the scene is active), so a long stay
// in the background never uses it up.
import SwiftUI

struct BackgroundNoticeView: View {
    let text: String
    /// ACC-011 X4: announces the notice through the status-event router (kind `background`).
    let announce: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("backgroundNoticeText")
            Button("Dismiss", action: onDismiss)
                .font(.footnote.bold())
                .accessibilityIdentifier("backgroundNoticeDismiss")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("backgroundNotice")
        .task(id: text) {
            announce(text)
            try? await Task.sleep(for: AppCoordinator.backgroundNoticeDuration)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
