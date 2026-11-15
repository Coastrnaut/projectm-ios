// CountdownSection.swift — Settings → Countdown (MED-012-R5, R9; spec Clarifications).
//
// Show Countdown (off by default), the remaining time, Start/Pause/Resume and Reset, Minutes and Seconds (a change
// resets the countdown), Start From New Cues, Position and Alignment. The footer says which visuals show it. Each
// change is saved at once by the coordinator. Small bodies built in typed steps (type-check budget).
import SwiftUI
import TextLayer

struct CountdownSection: View {
    @Bindable var countdown: CountdownOverlayCoordinator

    var body: some View {
        Section {
            showToggle
            controlRows
            durationRows
            cueToggle
            if countdown.settings.isShown { placementRows }
        } header: {
            Text("Countdown")
        } footer: {
            Text(CountdownOverlayCoordinator.help)
        }
    }

    private var showToggle: some View {
        Toggle("Show Countdown", isOn: $countdown.settings.isShown)
            .accessibilityIdentifier("showCountdownToggle")
    }

    private var startTitle: String {
        switch countdown.state {
        case .running: "Pause"
        case .paused: "Resume"
        case .idle, .finished: "Start"
        }
    }

    @ViewBuilder private var controlRows: some View {
        LabeledContent("Remaining", value: countdown.currentText ?? "")
            .accessibilityIdentifier("countdownRemaining")
        HStack {
            Button(startTitle) { toggleRun() }
                .accessibilityIdentifier("countdownStartButton")
            Spacer()
            Button("Reset") { countdown.reset() }
                .disabled(countdown.state == .idle)
                .accessibilityIdentifier("countdownResetButton")
        }
        .buttonStyle(.borderless)
    }

    private func toggleRun() {
        if countdown.state == .running { countdown.pause() } else { countdown.start() }
    }

    @ViewBuilder private var durationRows: some View {
        Stepper(value: $countdown.settings.minutes, in: 0...99) {
            Text("Minutes: " + String(countdown.settings.minutes))
        }
        .accessibilityIdentifier("countdownMinutesStepper")
        Stepper(value: $countdown.settings.seconds, in: 0...59) {
            Text("Seconds: " + String(countdown.settings.seconds))
        }
        .accessibilityIdentifier("countdownSecondsStepper")
    }

    private var cueToggle: some View {
        Toggle("Start From New Cues", isOn: $countdown.settings.startsFromCues)
            .accessibilityIdentifier("countdownCuesToggle")
    }

    @ViewBuilder private var placementRows: some View {
        Picker("Position", selection: $countdown.settings.style.verticalPosition) {
            ForEach(TextVerticalPosition.allCases, id: \.self) { (position: TextVerticalPosition) in
                Text(position.title).tag(position)
            }
        }
        .accessibilityIdentifier("countdownPositionPicker")
        Picker("Alignment", selection: $countdown.settings.style.alignment) {
            ForEach(TextAlignmentChoice.allCases, id: \.self) { (alignment: TextAlignmentChoice) in
                Text(alignment.title).tag(alignment)
            }
        }
        .accessibilityIdentifier("countdownAlignmentPicker")
    }
}
