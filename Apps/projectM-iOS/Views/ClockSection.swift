// ClockSection.swift — Settings → Clock (MED-011-R7; spec Clarifications).
//
// Show Clock (off by default), Format (24-hour, 12-hour), Seconds, Position (top, middle, bottom) and Alignment
// (leading, centre, trailing). The footer says which visuals show the clock. Each change is saved at once by the
// coordinator and shown from the next tick. Small bodies built in typed steps (type-check budget).
import SwiftUI
import TextLayer

struct ClockSection: View {
    @Bindable var clock: ClockOverlayCoordinator

    var body: some View {
        Section {
            showToggle
            if clock.settings.isShown { formatRows }
            if clock.settings.isShown { placementRows }
        } header: {
            Text("Clock")
        } footer: {
            Text(ClockOverlayCoordinator.help)
        }
    }

    private var showToggle: some View {
        Toggle("Show Clock", isOn: $clock.settings.isShown)
            .accessibilityIdentifier("showClockToggle")
    }

    @ViewBuilder private var formatRows: some View {
        Picker("Format", selection: $clock.settings.hourCycle) {
            ForEach(ClockHourCycle.allCases, id: \.self) { (cycle: ClockHourCycle) in
                Text(cycle.title).tag(cycle)
            }
        }
        .accessibilityIdentifier("clockFormatPicker")
        Toggle("Seconds", isOn: $clock.settings.showsSeconds)
            .accessibilityIdentifier("clockSecondsToggle")
    }

    @ViewBuilder private var placementRows: some View {
        Picker("Position", selection: $clock.settings.style.verticalPosition) {
            ForEach(TextVerticalPosition.allCases, id: \.self) { (position: TextVerticalPosition) in
                Text(position.title).tag(position)
            }
        }
        .accessibilityIdentifier("clockPositionPicker")
        Picker("Alignment", selection: $clock.settings.style.alignment) {
            ForEach(TextAlignmentChoice.allCases, id: \.self) { (alignment: TextAlignmentChoice) in
                Text(alignment.title).tag(alignment)
            }
        }
        .accessibilityIdentifier("clockAlignmentPicker")
    }
}
