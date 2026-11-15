// OSCCueSyncView.swift — the Cue Sync screen (OSC-012-R1, R14; specs/291-osc-012-peer-cue-sync, contract C6). Opened
// from the OSC section in Settings: the role (Off, Lead, Follow), the status line, refreshed once a second for the
// follower's "started N s ago", and the counts. Small views so each body stays under CI's type-check budget. Nothing is
// announced here.
import PerformanceControl
import SwiftUI

struct OSCCueSyncView: View {
    var cueSync: OSCCueSyncCoordinator

    var body: some View {
        List {
            OSCCueSyncRoleSection(cueSync: cueSync)
        }
        .navigationTitle("Cue Sync")
        .onAppear { cueSync.conditionsChanged() }
    }
}

private struct OSCCueSyncRoleSection: View {
    var cueSync: OSCCueSyncCoordinator

    private var roleBinding: Binding<OSCCueSyncRole> {
        Binding(get: { () -> OSCCueSyncRole in cueSync.role },
                set: { (role: OSCCueSyncRole) -> Void in cueSync.setRole(role) })
    }

    var body: some View {
        Section {
            Picker("Cue sync", selection: roleBinding) {
                ForEach(OSCCueSyncRole.allCases, id: \.self) { (role: OSCCueSyncRole) in
                    Text(OSCCueSyncCoordinator.title(role)).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Cue sync")
            .accessibilityIdentifier("oscCueSyncRole")
            OSCCueSyncStatusRow(cueSync: cueSync)
        } footer: {
            Text(Self.footer)
        }
    }

    static let footer = "Lead sends this device's current cue to Send OSC's destination; Follow moves this show to the cue an approved device sends. Both need the OSC receiver and Only approved devices, and both devices need the same show. Cue sync only moves the show; it changes no setting."
}

private struct OSCCueSyncStatusRow: View {
    var cueSync: OSCCueSyncCoordinator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { (_: TimelineViewDefaultContext) in
            VStack(alignment: .leading, spacing: 4) {
                Text(cueSync.statusText)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cue sync status")
                    .accessibilityValue(cueSync.statusText)
                    .accessibilityIdentifier("oscCueSyncStatus")
                if !cueSync.countsText.isEmpty {
                    Text(cueSync.countsText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("oscCueSyncCounts")
                }
            }
        }
    }
}
