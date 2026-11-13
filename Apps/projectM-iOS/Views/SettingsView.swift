// SettingsView.swift — Settings (task T103): the visual (VIS-001-R11), the performance overlay
// (FR-048), Reduce flashing (FR-072) and the Licenses screen (FR-067).
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// False when the active renderer cannot limit flashing (FR-072, T116). Both current renderers
    /// can (T119); this keeps Settings honest for any renderer that cannot.
    var reduceFlashingAvailable = true
    /// VIS-001-R16: the circular spectrum could not be created on this device.
    var nativeVisualUnavailable = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Visual", selection: $settings.visual) {
                        ForEach(VisualChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Visual")
                    .accessibilityIdentifier("visualPicker")
                    if settings.visual == .circularSpectrum {
                        Picker("Bars", selection: $settings.circularSpectrumBars) {
                            ForEach(AppSettings.circularSpectrumBarChoices, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Bars")
                        .accessibilityIdentifier("barsPicker")
                    }
                } header: {
                    Text("Visual")
                } footer: {
                    if nativeVisualUnavailable && settings.visual == .circularSpectrum {
                        Text("Circular Spectrum isn't available on this device, so projectM is shown.")
                            .accessibilityIdentifier("nativeVisualUnavailableFooter")
                    } else {
                        Text("projectM plays presets. Circular Spectrum draws one bar per frequency band, low to high, clockwise from the top.")
                    }
                }
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
