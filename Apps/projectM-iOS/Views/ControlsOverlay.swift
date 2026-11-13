// ControlsOverlay.swift — the visualizer controls (task T085; FR-082, FR-087, FR-070).
//
// FR-082 contents: the source-and-state indicator, Stop, Pause/Resume, Previous, Next, Random, the
// preset browser, the current preset name, and Settings. Regular width uses two rows; compact width
// (iPhone portrait, the smallest iPad split view) uses one row of icon buttons with the preset name
// above it, and the preset browser opens as a sheet in both. Every control has an accessibility
// label equal to its meaning (FR-070).
//
// AUD-006: while In-App Playback is the active source, the transport (CaptureUI's TransportBar:
// track title, scrubber and times, Previous track, Play or Pause playback, Stop playback, Next
// track) sits above those rows in both layouts. It is not shown for Microphone or System/App
// track) sits above those rows in both layouts. It is not shown for Microphone or System/App
// Capture, and it appears and hides with the rest of the controls (AUD-006-R24, R25). For imported
// audio it also offers the queue (AUD-003) and the Repeat control (AUD-004).
//
// PRE-015-R1: next to the current preset's name, "Duplicate to My Presets" copies a built-in
// preset on screen into My Presets (not shown for a user preset).
//
// VIS-001-R13: while the native Circular Spectrum is shown there is no preset on screen, so the title
// names the visual (`currentVisual`) and Previous, Next, Random, Presets and Duplicate are left out;
// Stop, Pause/Resume, Settings and the transport stay.
import CaptureKit
import CaptureUI
import PresetLibrary
import SwiftUI

struct ControlsOverlay: View {
    let coordinator: AppCoordinator
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // A real container, not a Group: a Group would pass the identifiers below to every button.
        VStack(spacing: 10) {
            if coordinator.transport.isAvailable {
                transport
                Divider()
            }
            // Accessibility text sizes use the one-row icon layout too: seven labeled buttons in a
            // row cannot fit (FR-070).
            if sizeClass == .compact || typeSize.isAccessibilitySize {
                compact
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("controlsCompact")
            } else {
                regular
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("controlsRegular")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("controls")
    }

    /// AUD-006: the transport of In-App Playback.
    private var transport: some View {
        let model = coordinator.transport
        _ = model.positionRevision          // a seek or a track change shows at once, not at the next poll
        return TransportBar(title: model.current?.title ?? "", isPlaying: model.state == .playing,
                            position: { model.position },
                            onPlayPause: { coordinator.transportPlayPause() }, onStop: { coordinator.transportStop() },
                            onPrevious: { coordinator.transportPrevious() }, onNext: { coordinator.transportNext() },
                            onSeek: { coordinator.transportSeek(to: $0) },
                            onShowQueue: coordinator.transportShowsQueue ? { coordinator.openQueue() } : nil,   // AUD-003
                            // AUD-004: the queue's repeat mode, for imported audio only.
                            repeatMode: coordinator.transportShowsQueue ? coordinator.audioLibrary.queue.repeatMode : nil,
                            onCycleRepeat: {
                                coordinator.showControls()
                                coordinator.audioLibrary.queue.cycleRepeatMode()
                            },
                            // AUD-005: Shuffle, for imported audio only.
                            isShuffled: coordinator.transportShowsQueue ? coordinator.audioLibrary.queue.isShuffled : nil,
                            onToggleShuffle: {
                                coordinator.showControls()
                                coordinator.audioLibrary.queue.toggleShuffle()
                            })
            .frame(maxWidth: 560)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transport")
    }

    @ViewBuilder private var presetName: some View {
        if coordinator.showsNativeVisual {
            VStack(alignment: .leading, spacing: 1) {
                Text(VisualChoice.circularSpectrum.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .accessibilityIdentifier("currentVisual")
                Text("Native visual")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            presetRow
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            presetTitle
            if let current = coordinator.presets.current, current.source != PresetLibrary.userSource {
                Button {
                    coordinator.showControls()
                    Task { await coordinator.userPresets.duplicate(current) }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(coordinator.userPresets.isDuplicating)
                .accessibilityLabel("Duplicate to My Presets")
                .accessibilityIdentifier("duplicateCurrent")
            }
        }
    }

    private var presetTitle: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(coordinator.presets.current?.name ?? "No preset")
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("currentPreset")
            // Feature 002 FR-120: the scope Next/Previous/Random walk, and its playable count.
            Text(coordinator.presets.scopeLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("scopeLine")
        }
    }

    /// One row of icon buttons (FR-087).
    private var compact: some View {
        VStack(spacing: 8) {
            HStack {
                SourceStatusIndicator(coordinator: coordinator)
                Spacer(minLength: 0)
            }
            presetName.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(buttons, id: \.id) { item in
                    Button(action: item.action) {
                        Image(systemName: item.icon).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .accessibilityLabel(item.title)
                    .accessibilityIdentifier(item.id)
                }
            }
            .font(.title3)
        }
    }

    private var regular: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SourceStatusIndicator(coordinator: coordinator)
                Spacer()
                presetName
            }
            HStack(spacing: 10) {
                ForEach(buttons, id: \.id) { item in
                    Button(action: item.action) {
                        Label(item.title, systemImage: item.icon)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(item.id)
                }
            }
        }
    }

    private struct Item {
        let id: String
        let title: String
        let icon: String
        let action: () -> Void
    }

    private var buttons: [Item] {
        let presetIDs: Set<String> = ["previous", "next", "random", "presets"]
        return allButtons.filter { !coordinator.showsNativeVisual || !presetIDs.contains($0.id) }
    }

    private var allButtons: [Item] {
        [
            Item(id: "stop", title: "Stop", icon: "stop.fill") { coordinator.stop() },
            Item(id: "pauseResume", title: coordinator.userPaused ? "Resume" : "Pause",
                 icon: coordinator.userPaused ? "play.fill" : "pause.fill") { coordinator.togglePause() },
            Item(id: "previous", title: "Previous", icon: "backward.fill") { coordinator.previous() },
            Item(id: "next", title: "Next", icon: "forward.fill") { coordinator.next() },
            Item(id: "random", title: "Random", icon: "shuffle") { coordinator.random() },
            Item(id: "presets", title: "Presets", icon: "list.bullet") {
                coordinator.showPresetBrowser = true
            },
            Item(id: "settings", title: "Settings", icon: "gearshape") { coordinator.showSettings = true },
        ]
    }
}
