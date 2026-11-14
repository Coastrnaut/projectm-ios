// OSCListenerBadge.swift — "OSC listening on port N" with Stop (OSC-007; specs/038-osc-007-osc-network-
// access-switch, contracts/osc-listener-badge.md). Shown only while the OSC receiver's listener is
// ready (OSC-007-R2, R3); Stop turns the OSC receiver setting off and closes the listener (R4). On
// the visualizer it sits in the top status stack, independent of the controls (R6); the source
// chooser shows it at the bottom.
import SwiftUI

struct OSCListenerBadge: View {
    let osc: OSCReceiverCoordinator
    /// ACC-011 X20: "OSC off" through the status-event router, with a caption (OSC-007-R7).
    let onStopped: () -> Void

    var body: some View {
        if let port = osc.badgePort {
            HStack(spacing: 10) {
                Image(systemName: StatusCueCatalog.oscSymbol)
                    .accessibilityHidden(true)
                Text(OSCReceiverCoordinator.badgeText(port: port))
                    .font(.footnote.weight(.semibold))
                    .accessibilityLabel("OSC listening")
                    .accessibilityValue(OSCReceiverCoordinator.badgeAccessibilityValue(port: port))   // a String: no "47,124" grouping
                    .accessibilityIdentifier("oscListenerBadgeText")
                Button("Stop") {
                    osc.stopFromBadge()
                    onStopped()   // OSC-007-R7
                }
                .font(.footnote.bold())
                .accessibilityLabel("Stop OSC")
                .accessibilityHint("Turns off the OSC receiver")
                .accessibilityIdentifier("oscStopButton")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .statusBadgeBackground(Capsule())   // ACC-003-R9
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("oscListenerBadge")
        }
    }
}
