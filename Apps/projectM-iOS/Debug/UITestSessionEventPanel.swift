// UITestSessionEventPanel.swift — buttons that post synthetic audio-session notifications, for
// InterruptionUITests (AUD-014-T21, T22). DEBUG builds only, and only with the launch argument
// `-uitestSessionEvents`; Release builds contain none of this.
//
// Unlike UITestFakeSource, the real In-App Playback source keeps running: the notifications reach
// its real observers, so the test sees what the app does with an interruption of a playing track.
#if DEBUG
import AVFAudio
import SwiftUI

struct UITestSessionEventPanel: View {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-uitestSessionEvents") }

    var body: some View {
        HStack(spacing: 2) {
            button("session:interruptBegan") { SyntheticSessionEvents.postInterruption(.began) }
            button("session:interruptEndedResume") { SyntheticSessionEvents.postInterruption(.ended, shouldResume: true) }
            button("session:interruptEnded") { SyntheticSessionEvents.postInterruption(.ended) }
            button("session:routeLost") { SyntheticSessionEvents.postOutputRouteLost() }
        }
        .font(.system(size: 9))
        .buttonStyle(.bordered)
        .padding(4)
        .background(.black.opacity(0.6))
    }

    private func button(_ id: String, action: @escaping () -> Void) -> some View {
        Button(id, action: action).accessibilityIdentifier(id)
    }
}
#endif
