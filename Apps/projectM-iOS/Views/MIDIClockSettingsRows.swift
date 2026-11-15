// MIDIClockSettingsRows.swift — "Follow MIDI clock" and its status row in Settings → MIDI (MIDI-010-R6;
// specs/273-midi-010-midi-clock-receive, contracts/midi-clock.md C4). Rows of MIDISettingsSection's list section, in a
// view of their own so that section's body stays small (CI's Xcode 26 type-check budget). No animation; Dynamic Type
// and VoiceOver come from the standard rows.
import SwiftUI

struct MIDIClockSettingsRows: View {
    var clock: MIDIClockCoordinator

    var body: some View {
        Toggle("Follow MIDI clock", isOn: followBinding)
            .accessibilityHint("Sets the show's tempo from a connected device's MIDI clock")
            .accessibilityIdentifier("midiFollowClockToggle")
            .onAppear { clock.refresh() }
        if clock.isFollowing {
            Text(clock.statusText)
                .foregroundStyle(.secondary)
                .accessibilityLabel("MIDI clock status")
                .accessibilityValue(clock.statusText)
                .accessibilityIdentifier("midiClockStatus")
            #if DEBUG
            if UITestFakeMIDI.isRequested { UITestFakeMIDIClockToggle() }
            #endif
        }
    }

    private var followBinding: Binding<Bool> {
        Binding<Bool>(get: { () -> Bool in clock.isFollowing },
                      set: { (on: Bool) -> Void in clock.setFollowing(on) })
    }
}
