// HapticBeatSection.swift — ACC-007-R1, R6, R11 (specs/238-acc-007-haptic-beat-feedback, contract C4):
// Settings → Haptics, after Reduce flashing.
//
// A switch "Haptic beat pulses" (off by default) and, only while it is on, "Pulse on" (Beats, Downbeats, Kicks)
// and "Strength" (Light, Medium, Strong). Disabled with a note on hardware without haptics; the stored choice is
// kept. Rows appear without animation (no MotionPolicy path needed, ACC-001). A view of its own, built from small
// properties, so SettingsView's body stays within CI's Xcode 26 type-check budget.
import PerformanceControl
import SwiftUI

struct HapticBeatSection: View {
    @Bindable var coordinator: HapticBeatCoordinator

    private var footerText: String {
        guard !coordinator.isAvailable else { return HapticBeatCoordinator.footer }
        let note: String = HapticBeatCoordinator.noHardwareNote
        return note + " " + HapticBeatCoordinator.footer
    }

    var body: some View {
        Section {
            toggle
            if coordinator.enabled {
                choicePicker
                strengthPicker
            }
        } header: {
            Text(HapticBeatCoordinator.sectionTitle)
        } footer: {
            Text(footerText)
        }
    }

    private var toggle: some View {
        Toggle("Haptic beat pulses", isOn: $coordinator.enabled)
            .disabled(!coordinator.isAvailable)
            .accessibilityIdentifier("hapticBeatToggle")
    }

    private var choicePicker: some View {
        Picker("Pulse on", selection: $coordinator.choice) {
            ForEach(HapticBeatChoice.allCases, id: \.self) { (choice: HapticBeatChoice) in
                Text(choice.title).tag(choice)
            }
        }
        .disabled(!coordinator.isAvailable)
        .accessibilityIdentifier("hapticBeatEventPicker")
    }

    private var strengthPicker: some View {
        Picker("Strength", selection: $coordinator.strength) {
            ForEach(HapticPulseStrength.allCases, id: \.self) { (strength: HapticPulseStrength) in
                Text(strength.title).tag(strength)
            }
        }
        .disabled(!coordinator.isAvailable)
        .accessibilityIdentifier("hapticBeatStrengthPicker")
    }
}
