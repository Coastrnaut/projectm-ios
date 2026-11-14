// OSCPeersView.swift — the Approved Devices screen (OSC-008-R5, R9; specs/200-osc-008-peer-allowlist, contract A5).
// Opened from the OSC section in Settings: the "Only approved devices" switch, the approved hosts (Remove), the hosts
// recently blocked (Allow) and the blocked count. Small views so each body stays under CI's type-check budget.
// Nothing is announced per datagram; the lists change only on the gated refresh.
import PerformanceControl
import SwiftUI

struct OSCPeersView: View {
    var peers: OSCPeersCoordinator

    var body: some View {
        List {
            OSCPeersSwitchSection(peers: peers)
            OSCApprovedPeersSection(peers: peers)
            OSCBlockedPeersSection(peers: peers)
        }
        .navigationTitle("Approved Devices")
    }
}

private struct OSCPeersSwitchSection: View {
    var peers: OSCPeersCoordinator

    var body: some View {
        Section {
            Toggle("Only approved devices", isOn: Binding(get: { () -> Bool in peers.isEnabled },
                                                          set: { (on: Bool) -> Void in peers.setEnabled(on) }))
                .accessibilityIdentifier("oscPeerAllowlistToggle")
            if peers.isEnabled && peers.approved.isEmpty {
                Text("No device is approved, so every OSC message is blocked. Allow a device below after it sends a message.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("oscPeersEmptyNote")
            }
        } footer: {
            Text("When this is on, projectM applies OSC messages only from the devices you approve on your local network and ignores all others. Approved addresses are kept on this device only.")
        }
    }
}

private struct OSCApprovedPeersSection: View {
    var peers: OSCPeersCoordinator

    var body: some View {
        Section("Approved") {
            if peers.approved.isEmpty {
                Text("None").foregroundStyle(.secondary)
            }
            ForEach(Array(peers.approved.enumerated()), id: \.offset) { (index: Int, peer: OSCPeerAddress) in
                HStack {
                    Text(peer.text).font(.body.monospaced())
                    Spacer()
                    Button("Remove", role: .destructive) { peers.remove(peer) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove " + peer.text)
                        .accessibilityIdentifier("oscRemovePeer_\(index)")
                }
                .accessibilityIdentifier("oscApprovedPeer_\(index)")
            }
        }
    }
}

private struct OSCBlockedPeersSection: View {
    var peers: OSCPeersCoordinator

    var body: some View {
        Section {
            ForEach(Array(peers.recentlyBlocked.enumerated()), id: \.offset) { (index: Int, peer: OSCPeerAddress) in
                HStack {
                    Text(peer.text).font(.body.monospaced())
                    Spacer()
                    Button("Allow") { peers.allow(peer) }
                        .buttonStyle(.borderless)
                        .disabled(peers.isFull)
                        .accessibilityLabel("Allow " + peer.text)
                        .accessibilityIdentifier("oscAllowPeer_\(index)")
                }
                .accessibilityIdentifier("oscBlockedPeer_\(index)")
            }
            LabeledContent("Blocked", value: String(peers.blockedCount))
                .accessibilityIdentifier("oscBlockedCount")
        } header: {
            Text("Recently blocked")
        } footer: {
            Text(peers.isFull ? "The list is full (16 devices). Remove one to allow another." : "Devices that sent OSC messages while not approved, most recent first. The list is cleared when OSC is turned off.")
        }
    }
}
