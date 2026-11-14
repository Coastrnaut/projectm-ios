// RecentHistorySection.swift — Settings › Recently Played (roadmap PRE-006,
// specs/159-pre-006-recent-history; R3, R4, R6): "Remember Recently Played" (on by default; off stops
// recording and clears the history) and Clear History (asks first; the history only).
import SwiftUI

struct RecentHistorySection: View {
    let recent: RecentPresetsCoordinator
    @State private var confirming = false

    var body: some View {
        Section {
            Toggle("Remember Recently Played", isOn: Binding(get: { recent.isEnabled },
                                                             set: { (on: Bool) in recent.setEnabled(on) }))
                .accessibilityIdentifier("recentToggle")
            Button(RecentPresetsCoordinator.clearTitle, role: .destructive) { confirming = true }
                .disabled(recent.ids.isEmpty)
                .accessibilityIdentifier("recentClear")
        } header: {
            Text(RecentPresetsCoordinator.title)
        } footer: {
            Text("Keeps the last 50 presets that stayed on screen for 3 seconds, on this device only, never in backups. Turning this off clears the list.")
        }
        .recentClearConfirmation(recent, isPresented: $confirming)
    }
}
