// StatusBanner.swift — non-modal status/failure banner (task T033; FR-015, FR-083; ui-states).
#if canImport(SwiftUI)
import AudioCore
import SwiftUI

public struct StatusBanner: View {
    public let mode: AudioSourceMode?
    public let state: AudioState
    public let reason: StopReason?
    public let prolongedSilence: Bool
    public let onAction: (BannerAction) -> Void

    public init(mode: AudioSourceMode?, state: AudioState, reason: StopReason?, prolongedSilence: Bool,
                onAction: @escaping (BannerAction) -> Void) {
        self.mode = mode
        self.state = state
        self.reason = reason
        self.prolongedSilence = prolongedSilence
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let mode {
                    Text(UIStrings.label(mode)).font(.headline)
                }
                Spacer()
                // ACC-003-R2: a symbol per state carries the shape (and, for Active, the colour); the
                // words stay in the primary colour (green text on the light material was about 2:1).
                Image(systemName: UIStrings.stateSymbol(state))
                    .font(.headline)
                    .foregroundStyle(state == .active ? AnyShapeStyle(.green) : AnyShapeStyle(.primary))
                    .accessibilityHidden(true)
                Text(UIStrings.state(state))
                    .font(.headline)
            }
            if let message = detail {
                Text(message).font(.subheadline)
            }
            // AUD-014-R17: why In-App Playback is on hold, and how it continues.
            if let explanation = UIStrings.playbackHoldDetail(mode: mode, reason: reason) {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("playbackHoldDetail")
            }
            if let reason {
                HStack {
                    ForEach(BannerAction.actions(for: reason), id: \.self) { action in
                        Button(action.title) { onAction(action) }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        if let reason { return UIStrings.message(reason) }
        if state == .noAudioReceived { return UIStrings.noAudioHint }
        if prolongedSilence { return UIStrings.prolongedSilenceHint }
        return nil
    }
}
#endif
