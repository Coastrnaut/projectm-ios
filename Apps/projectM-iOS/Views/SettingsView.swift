// SettingsView.swift — Settings (task T103): the performance overlay (FR-048), Reduce flashing
// (FR-072) and the Licenses screen (FR-067).
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// False when the active renderer cannot limit flashing (FR-072, T116). Both current renderers
    /// can (T119); this keeps Settings honest for any renderer that cannot.
    var reduceFlashingAvailable = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Reduce flashing", isOn: $settings.reduceFlashing)
                        .disabled(!reduceFlashingAvailable)
                        .accessibilityIdentifier("reduceFlashingToggle")
                    if !settings.reduceFlashingFollowsSystem {
                        Button("Follow Reduce Motion") { settings.followSystemForReduceFlashing() }
                            .accessibilityIdentifier("reduceFlashingFollowSystem")
                    }
                } footer: {
                    if reduceFlashingAvailable {
                        Text(settings.reduceFlashingFollowsSystem
                             ? "Limits rapid full-screen brightness changes. Follows the system Reduce Motion setting until you change it."
                             : "Limits rapid full-screen brightness changes.")
                    } else {
                        Text("Reduce flashing isn't available on this device: the app is using its fallback renderer. Avoid watching if flashing lights affect you.")
                            .accessibilityIdentifier("reduceFlashingUnavailable")
                    }
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
