// EmergencyBlackoutButton.swift — SHOW-014 (spec specs/061-show-014-emergency-blackout,
// contracts/emergency-blackout.md): the persistent one-tap emergency blackout. The visualizer shows
// it at the bottom trailing edge, with or without the controls, while the output is live or fading
// in (`OutputBlackout.Phase.offersEmergencyBlackout`). One tap is OUT-010's Black out: the output
// slot is black before the tap's handling returns, nothing is restarted. It only blacks out (restore
// is the badge's, SHOW-014-R3), never shows the controls and asks for no confirmation. The B key
// (no modifier) triggers it from a hardware keyboard (research SHOW-014-D3). Device only: the
// external display shows the visualization slot alone (OUT-001-R1).
import PresentationLifecycle
import SwiftUI

struct EmergencyBlackoutButton: View {
    let external: ExternalDisplayCoordinator

    /// The button's action (tests call it the same way).
    @MainActor static func trigger(_ external: ExternalDisplayCoordinator) {
        external.setBlackout(true)
    }

    var body: some View {
        Button {
            Self.trigger(external)
        } label: {
            Image(systemName: "eye.slash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)          // SHOW-014-R5: the minimum comfortable target, no larger
                .overlaySurface(Circle())   // ACC-008-R2
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("b", modifiers: [])          // SHOW-014-R6
        .accessibilityLabel("Emergency black out")
        .accessibilityHint("Makes the output black at once. Restore is at the top.")
        .accessibilityIdentifier("emergencyBlackout")
    }
}
