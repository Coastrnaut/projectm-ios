// ReduceFlashingSection.swift — FR-072's Reduce flashing toggle, moved out of SettingsView's body for CI's
// Xcode 26 type-check budget (ACC-012). ACC-012 (clarify Q2): the footer says when the sensory safety
// profile keeps flashing reduced; the toggle keeps the user's own choice.
import SwiftUI

struct ReduceFlashingSection: View {
    @Bindable var settings: AppSettings
    /// False on the fallback renderer without the flash limiter.
    let available: Bool

    /// FR-072 footer; ACC-012 (clarify Q2): says when the sensory safety profile keeps flashing reduced.
    static func footer(_ settings: AppSettings) -> String {
        let base: String = settings.reduceFlashingFollowsSystem
            ? "Limits rapid full-screen brightness changes. Follows the system Reduce Motion setting until you change it."
            : "Limits rapid full-screen brightness changes."
        guard settings.effectiveReduceFlashing && !settings.reduceFlashing else { return base }
        return base + " Your sensory safety profile keeps flashing reduced."
    }

    var body: some View {
        Section {
            Toggle("Reduce flashing", isOn: $settings.reduceFlashing)
                .disabled(!available)
                .accessibilityIdentifier("reduceFlashingToggle")
            if !settings.reduceFlashingFollowsSystem {
                Button("Follow Reduce Motion") { settings.followSystemForReduceFlashing() }
                    .accessibilityIdentifier("reduceFlashingFollowSystem")
            }
        } footer: {
            if available {
                Text(Self.footer(settings))
            } else {
                Text("Reduce flashing isn't available on this device: the app is using its fallback renderer. Avoid watching if flashing lights affect you.")
                    .accessibilityIdentifier("reduceFlashingUnavailable")
            }
        }
    }
}
