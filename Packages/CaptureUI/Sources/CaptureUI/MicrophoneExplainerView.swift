// MicrophoneExplainerView.swift — shown before the microphone permission prompt (task T048; FR-005).
#if canImport(SwiftUI)
import SwiftUI

public struct MicrophoneExplainerView: View {
    public let onContinue: () -> Void
    public let onCancel: () -> Void

    public init(onContinue: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onContinue = onContinue
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic").font(.largeTitle).accessibilityHidden(true)
            Text(UIStrings.label(.microphone)).font(.title2.bold())
            Text(UIStrings.microphoneExplainer)
                .multilineTextAlignment(.center)
            HStack {
                Button(UIStrings.cancel, role: .cancel, action: onCancel).buttonStyle(.bordered)
                Button(UIStrings.continueAction, action: onContinue).buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
#endif
