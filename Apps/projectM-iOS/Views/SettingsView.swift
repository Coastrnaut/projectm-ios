// SettingsView.swift — Settings (task T103): the visual (VIS-001-R11, VIS-002-R11), its options and
// glow (FX-001-R11),
// the performance overlay (FR-048), Reduce flashing (FR-072) and the Licenses screen (FR-067).
import SwiftUI
import VisualEffects
import VisualGenerators

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// False when the active renderer cannot limit flashing (FR-072, T116). Both current renderers
    /// can (T119); this keeps Settings honest for any renderer that cannot.
    var reduceFlashingAvailable = true
    /// VIS-001-R16: the circular spectrum could not be created on this device.
    var nativeVisualUnavailable = false
    /// FX-001-R13: the glow could not be built on this device.
    var glowUnavailable = false
    @Environment(\.dismiss) private var dismiss

    /// "50%", or "2.0%" with one decimal.
    static func percent(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", value * 100)
    }

    /// A labeled glow slider; VoiceOver reads the label and the percentage (FR-070).
    private func glowSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Float>, text: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: Double(range.lowerBound)...Double(range.upperBound))
                .accessibilityLabel(title)
                .accessibilityValue(text)
                .accessibilityIdentifier(id)
        }
    }

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
                    if settings.visual.isNative {
                        Picker("Bars", selection: $settings.circularSpectrumBars) {
                            ForEach(AppSettings.circularSpectrumBarChoices, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Bars")
                        .accessibilityIdentifier("barsPicker")
                        if settings.visual == .linearSpectrum {
                            Picker("Orientation", selection: $settings.linearSpectrumOrientation) {
                                ForEach(LinearSpectrumOrientation.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Orientation")
                            .accessibilityIdentifier("orientationPicker")
                            Picker("Spacing", selection: $settings.linearSpectrumSpacing) {
                                ForEach(AppSettings.linearSpectrumSpacingChoices, id: \.value) { Text($0.title).tag($0.value) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("Spacing")
                            .accessibilityIdentifier("spacingPicker")
                        }
                        Toggle("Glow", isOn: $settings.glowEnabled)
                            .accessibilityIdentifier("glowToggle")
                        if settings.glowEnabled {
                            glowSlider("Intensity", value: $settings.glowIntensity, range: BloomParameters.intensityRange,
                                       text: Self.percent(settings.glowIntensity), id: "glowIntensitySlider")
                            glowSlider("Radius", value: $settings.glowRadius, range: BloomParameters.radiusRange,
                                       text: Self.percent(settings.glowRadius, decimals: 1), id: "glowRadiusSlider")
                            glowSlider("Threshold", value: $settings.glowThreshold, range: BloomParameters.thresholdRange,
                                       text: Self.percent(settings.glowThreshold), id: "glowThresholdSlider")
                        }
                    }
                } header: {
                    Text("Visual")
                } footer: {
                    if nativeVisualUnavailable && settings.visual.isNative {
                        Text("\(settings.visual.title) isn't available on this device, so projectM is shown.")
                            .accessibilityIdentifier("nativeVisualUnavailableFooter")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("projectM plays presets. Circular Spectrum draws one bar per frequency band, low to high, clockwise from the top. Linear Spectrum draws them side by side, low to high, with caps that mark recent peaks.")
                            if settings.visual.isNative {
                                if glowUnavailable {
                                    Text(AppCoordinator.glowUnavailableMessage)
                                        .accessibilityIdentifier("glowUnavailableFooter")
                                } else {
                                    Text("Glow adds a soft halo around the bright parts; dark areas stay dark.")
                                }
                            }
                        }
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
