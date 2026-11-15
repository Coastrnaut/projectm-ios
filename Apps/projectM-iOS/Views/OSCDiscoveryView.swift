// OSCDiscoveryView.swift — the Nearby Devices screen (OSC-011-R3, R8, R9; specs/289-osc-011-local-peer-discovery,
// contract D3). Opened from the OSC section in Settings: "Find nearby devices", "Let nearby devices find this one",
// the status and the devices found, each with explicit Allow and Use as send destination buttons. Small views so
// each body stays under CI's type-check budget. Nothing is announced when the list changes.
import PerformanceControl
import SwiftUI

struct OSCDiscoveryView: View {
    var discovery: OSCDiscoveryCoordinator

    var body: some View {
        List {
            OSCDiscoverySwitchSection(discovery: discovery)
            if discovery.browseEnabled && discovery.isOSCEnabled {
                OSCDiscoveredPeersSection(discovery: discovery)
            }
        }
        .navigationTitle("Nearby Devices")
    }
}

private struct OSCDiscoverySwitchSection: View {
    var discovery: OSCDiscoveryCoordinator

    var body: some View {
        Section {
            Toggle("Find nearby devices", isOn: Binding(get: { () -> Bool in discovery.browseEnabled },
                                                        set: { (on: Bool) -> Void in discovery.setBrowse(on) }))
                .disabled(!discovery.isOSCEnabled)
                .accessibilityIdentifier("oscDiscoveryBrowseToggle")
            Toggle("Let nearby devices find this one", isOn: Binding(get: { () -> Bool in discovery.advertiseEnabled },
                                                                     set: { (on: Bool) -> Void in discovery.setAdvertise(on) }))
                .disabled(!discovery.isOSCEnabled)
                .accessibilityIdentifier("oscDiscoveryAdvertiseToggle")
            Text(discovery.statusText)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Discovery status")
                .accessibilityValue(discovery.statusText)
                .accessibilityIdentifier("oscDiscoveryStatus")
            if let advertising = discovery.advertiseStatusText {
                Text(advertising)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("oscDiscoveryAdvertiseStatus")
            }
            if !discovery.isOSCEnabled {
                Text("Turn on the OSC receiver to use these.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("oscDiscoveryNeedsOSC")
            }
        } footer: {
            Text("Uses Bonjour on your local network only, never a server or the internet. Both are off until you turn them on, and stop when you turn off the OSC receiver or leave the app. This device is shown to others only as a generic “projectM” name, never its own name.")
        }
    }
}

private struct OSCDiscoveredPeersSection: View {
    var discovery: OSCDiscoveryCoordinator

    var body: some View {
        Section {
            if discovery.peers.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            }
            ForEach(Array(discovery.peers.enumerated()), id: \.element.id) { (index: Int, peer: OSCDiscoveredPeer) in
                OSCDiscoveredPeerRow(discovery: discovery, peer: peer, index: index)
            }
            if let note = discovery.actionNote {
                Text(note)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("oscDiscoveryActionNote")
            }
        } header: {
            Text("Found")
        } footer: {
            Text("A device found here is never trusted by itself: tap Allow to add it to Approved Devices, or Use as send destination to send OSC to it.")
        }
    }
}

private struct OSCDiscoveredPeerRow: View {
    var discovery: OSCDiscoveryCoordinator
    let peer: OSCDiscoveredPeer
    let index: Int

    private var addressText: String { peer.addressText ?? "Resolving…" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(peer.name)
            Text(addressText)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
            HStack {
                Button(discovery.isApproved(peer) ? "Allowed" : "Allow") { discovery.allow(peer) }
                    .disabled(peer.address == nil || discovery.isApproved(peer) || !discovery.canAllow)
                    .accessibilityLabel("Allow " + peer.name)
                    .accessibilityIdentifier("oscDiscoveryAllow_\(index)")
                Spacer()
                Button("Use as send destination") { discovery.useAsSendDestination(peer) }
                    .disabled(peer.destination == nil)
                    .accessibilityLabel("Use " + peer.name + " as send destination")
                    .accessibilityIdentifier("oscDiscoveryUseAsDestination_\(index)")
            }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("oscDiscoveredPeer_\(index)")
    }
}
