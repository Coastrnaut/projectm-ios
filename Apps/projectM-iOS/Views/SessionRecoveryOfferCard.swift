// SessionRecoveryOfferCard.swift — the recovery offer after an abnormal exit (PERF-010-R4;
// specs/070-perf-010-crash-safe-session-recovery, contracts/session-recovery.md C2). Non-blocking: it
// sits in the visualizer's top status stack and above the chooser, and everything else keeps working.
// Reopen appears only when a committed scene can be reopened (never in a crash loop). The card is
// announced to VoiceOver once when it first appears.
import SwiftUI

struct SessionRecoveryOfferCard: View {
    let recovery: SessionRecoveryCoordinator
    let onReopen: () -> Void
    let onStartFresh: () -> Void
    /// ACC-011 X24: announces the card through the status-event router (once per launch).
    let onShown: () -> Void

    var body: some View {
        if recovery.offer == .pending {
            VStack(alignment: .leading, spacing: 8) {
                Text(recovery.title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("sessionRecoveryTitle")
                Text(recovery.message)
                    .font(.footnote)
                if recovery.oscTurnedOff {
                    Text(SessionRecoveryCoordinator.oscMessage)
                        .font(.footnote)
                        .accessibilityIdentifier("sessionRecoveryOSC")
                }
                HStack(spacing: 12) {
                    if recovery.offersReopen {
                        Button("Reopen last scene", action: onReopen)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("sessionRecoveryReopen")
                    }
                    Button("Start fresh", action: onStartFresh)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("sessionRecoveryStartFresh")
                }
                .font(.footnote.bold())
            }
            .padding(12)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sessionRecoveryOffer")
            .onAppear { Self.announceOnce(onShown) }
        }
    }

    /// Posted once per launch, whichever screen shows the card first.
    @MainActor private static var announced = false

    @MainActor private static func announceOnce(_ announce: () -> Void) {
        guard !announced else { return }
        announced = true
        announce()
    }
}
