// SettingsView.swift — Settings (task T103): the performance overlay (FR-048), Reduce flashing
// (FR-072) and the Licenses screen (FR-067).
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Reduce flashing", isOn: $settings.reduceFlashing)
                        .accessibilityIdentifier("reduceFlashingToggle")
                    if !settings.reduceFlashingFollowsSystem {
                        Button("Follow Reduce Motion") { settings.followSystemForReduceFlashing() }
                            .accessibilityIdentifier("reduceFlashingFollowSystem")
                    }
                } footer: {
                    Text(settings.reduceFlashingFollowsSystem
                         ? "Limits rapid full-screen brightness changes. Follows the system Reduce Motion setting until you change it."
                         : "Limits rapid full-screen brightness changes.")
                }
                Section {
                    Toggle("Performance overlay", isOn: $settings.showsPerformanceOverlay)
                        .accessibilityIdentifier("performanceOverlayToggle")
                } footer: {
                    Text("Shows the frame rate and the audio state over the visualization.")
                }
                Section {
                    NavigationLink("Licenses") { LicensesView() }
                        .accessibilityIdentifier("licensesLink")
                    LabeledContent("Version",
                                   value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("settings")
    }
}
