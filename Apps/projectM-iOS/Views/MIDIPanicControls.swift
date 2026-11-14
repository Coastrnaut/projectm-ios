// MIDIPanicControls.swift — the MIDI panic's controls (MIDI-013-R7; specs/183-midi-013-panic, contract P3, research
// MIDI-013-D5): the Settings button, the visualizer's hidden ⌘⇧M key command and VoiceOver action, and the shortcut. The coordinator
// announces "MIDI reset" on the `.midi` lane; nothing here announces. No animation.
import SwiftUI

/// ⌘⇧M ("M" for MIDI). Not used elsewhere in the app (arrows, Page Up/Down, B, Escape, ⌘K, ⌘Z, ⌘⇧Z) and not an iPadOS
/// system shortcut; ⌘. is avoided because UIKit treats it as Escape.
enum MIDIPanicShortcut {
    static let key: KeyEquivalent = "m"
    static let modifiers: EventModifiers = [.command, .shift]
    static let title: String = "MIDI Panic"
    static let hint: String = "Releases every held MIDI key and trigger and stops learning. Mappings and the scene stay."
}

/// Settings › MIDI: always enabled (panic while idle changes nothing and still confirms).
struct MIDIPanicButton: View {
    let mappings: MIDIMappingCoordinator

    var body: some View {
        Button(MIDIPanicShortcut.title) { mappings.panic() }
            .keyboardShortcut(MIDIPanicShortcut.key, modifiers: MIDIPanicShortcut.modifiers)
            .accessibilityHint(MIDIPanicShortcut.hint)
            .accessibilityIdentifier("midiPanicButton")
    }
}

/// The visualizer's ⌘⇧M while Settings is closed (one registration at a time).
struct MIDIPanicKeyCommand: View {
    let mappings: MIDIMappingCoordinator

    var body: some View {
        Button("") { mappings.panic() }
            .keyboardShortcut(MIDIPanicShortcut.key, modifiers: MIDIPanicShortcut.modifiers)
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The visualizer's panic commands (one modifier keeps VisualizerView's type-check cost flat): ⌘⇧M while Settings is
/// closed, and the VoiceOver action "MIDI panic" while Listen for MIDI devices is on.
struct MIDIPanicVisualizerCommands: ViewModifier {
    let coordinator: AppCoordinator

    func body(content: Content) -> some View {
        withAction(withKeyLayer(content))
    }

    private func withKeyLayer<V: View>(_ view: V) -> some View {
        view.background(MIDIPanicVisualizerKeyLayer(coordinator: coordinator))
    }

    private func withAction<V: View>(_ view: V) -> some View {
        view.accessibilityActions { () -> MIDIPanicVoiceOverAction in MIDIPanicVoiceOverAction(coordinator: coordinator) }
    }
}

private struct MIDIPanicVisualizerKeyLayer: View {
    let coordinator: AppCoordinator

    var body: some View {
        if !coordinator.showSettings { MIDIPanicKeyCommand(mappings: coordinator.midiMappings) }
    }
}

private struct MIDIPanicVoiceOverAction: View {
    let coordinator: AppCoordinator

    var body: some View {
        if coordinator.midi.isEnabled {
            Button("MIDI panic") { coordinator.midiMappings.panic() }
        }
    }
}
