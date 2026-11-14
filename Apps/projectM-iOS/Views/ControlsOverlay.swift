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
//
// SHOW-011: the tap tempo group (TempoControls: readout, Tap, Reset tempo) sits beside the indicator
// in the compact layout and after the buttons in the regular one, for both visuals.
// AUD-007: the audio route indicator ("Output: Speaker", "Input: iPhone Microphone") sits next to
// the source-and-state indicator (its own row in compact width) while In-App Playback or Microphone runs.
// OUT-010: "Black out output" / "Restore output" blacks out the current output (the external display
// while the visualization is on one, else the device's visualization) with one tap; its
// accessibility value says the output's state (OUT-010-R1, R10). Shown for every visual.
// REC-003: "Record" / "Stop recording" records the visual's frames into a video for Files.
// REC-001: "Save Frame" asks for PNG or HEIF and saves the visual's next frame through the Files
// exporter (REC-001-R1); shown for every visual.
// SHOW-001: when the show has cues, its row (Previous cue, "Cue 2 of 5 · Intro", Next cue) sits above
// the buttons in both layouts (ShowCueRow).
// AUD-012: "Switch Source" (after Stop) opens the list of the other available sources.
// UIX-004: the favorite parameter shelf (pinned controls) sits above the buttons while it has pins.
import CameraLayer
import CaptureKit
import CaptureUI
import PresentationLifecycle
import PresetLibrary
import SwiftUI

struct ControlsOverlay: View {
    let coordinator: AppCoordinator
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    /// ACC-006: the content's height, so the scroll view at accessibility sizes is no taller than it.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        // ACC-006-R2: at accessibility sizes the controls can be taller than the screen (AX5 with the
        // transport, a route and a notice above them: audit 2026-11-13). They then scroll inside their
        // backing: one scroll view as tall as the content (measured), at most the height left above the
        // controls (layout priority), so it scrolls only when the content does not fit. Standard sizes
        // keep the original tree exactly (ACC-004's contrast audit is sensitive to where the backing sits).
        if typeSize.isAccessibilitySize {
            ScrollView {
                content
                    // The `controls` element is the content inside the scroll view, so it stays an "other"
                    // element for every suite (`otherElements["controls"]`).
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("controls")
                    .onGeometryChange(for: CGFloat.self) { (proxy: GeometryProxy) -> CGFloat in proxy.size.height }
                        action: { (height: CGFloat) in contentHeight = height }
            }
            .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)
            // Opens at the bottom, where the buttons are (as before ACC-006, when the overflow went off the
            // top); the transport and status above are one drag away.
            .defaultScrollAnchor(.bottom)
            .scrollBounceBehavior(.basedOnSize)
            // Scrolling counts as use: restart the auto-hide (a scroll-phase observer, not a drag gesture,
            // which would take accessibility hit-testing from the buttons).
            .onScrollPhaseChange { (_: ScrollPhase, phase: ScrollPhase) in
                if phase.isScrolling { coordinator.showControls() }
            }
            .modifier(ControlsBacking())
            .layoutPriority(1)
        } else {
            content
                .modifier(ControlsBacking())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("controls")
        }
    }

    /// The controls' dark backing.
    /// ACC-004 (audit, 2026-11-13): the controls float over a moving, often bright visualization. With
    /// the ultra-thin material in light mode, black and grey text over a bright preset failed the
    /// contrast audit (titles, times, scope, route, tempo). Like a video player's controls they are
    /// now always dark, on a thick material darkened further, so a white preset behind them cannot
    /// lift the background enough to fail small captions (scope line) either.
    private struct ControlsBacking: ViewModifier {
        func body(content: Content) -> some View {
            // ACC-008-R2: the shared overlay surface; its scrim (was 45% black) meets 4.5:1 over white by itself.
            content.overlaySurface(RoundedRectangle(cornerRadius: 16), material: .thickMaterial)
        }
    }

    /// One line of text at standard sizes; up to three at accessibility sizes, so a long name wraps
    /// instead of losing its middle (ACC-006-R1).
    private var nameLines: Int? { typeSize.isAccessibilitySize ? 3 : 1 }

    private var content: some View {
        // A real container, not a Group: a Group would pass the identifiers below to every button.
        VStack(spacing: 10) {
            if coordinator.transport.isAvailable {
                transport
                Divider()
            }
            if coordinator.show.hasCues {   // SHOW-001-R13
                ShowCueRow(coordinator: coordinator)
                Divider()
            }
            ParameterShelfStrip(shelf: coordinator.parameterShelf, settings: coordinator.settings,   // UIX-004-R3
                                endCoalescing: { coordinator.sceneHistory.endCoalescing() }, touched: { coordinator.showControls() })
                .disabled(coordinator.settings.sceneLock.isLocked)   // SCN-015-R6
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
        if coordinator.showsAlternateVisual {
            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.settings.visual.title)   // VIS-001-R13, VIS-002
                    .font(.subheadline)
                    .lineLimit(nameLines)
                    .accessibilityIdentifier("currentVisual")
                Text(alternateVisualSubtitle)   // CAM-001, CAM-002, MED-001, MED-002
                    .font(.caption)
                    .lineLimit(nameLines)
            }
        } else {
            presetRow
        }
    }

    /// The line under the visual's name: which camera (CAM-002), your photo or video, or native.
    private var alternateVisualSubtitle: String {
        if coordinator.showsCameraVisual {
            let front: Bool = coordinator.settings.cameraPosition == .front
            return front ? "Front camera" : "Rear camera"
        }
        if coordinator.showsPhotoVisual { return "Your photo" }
        if coordinator.showsVideoVisual { return "Your video" }
        return "Native visual"
    }

    /// ACC-006-R1: at accessibility sizes the name gets the full width and Duplicate sits below it.
    /// (Beside a three-line name inside the scrolling controls, UI tests found Duplicate not hittable.)
    /// Standard sizes keep the original row (an `if`, not `AnyLayout`, so their tree is unchanged).
    @ViewBuilder private var presetRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                presetTitle
                duplicateButton
            }
        } else {
            HStack(spacing: 8) {
                presetTitle
                duplicateButton
            }
        }
    }

    /// PRE-015-R1: Duplicate to My Presets, for a built-in preset only.
    @ViewBuilder private var duplicateButton: some View {
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

    private var presetTitle: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(coordinator.presets.current?.name ?? "No preset")
                .font(.subheadline)
                .lineLimit(nameLines)
                .truncationMode(.middle)
                .accessibilityIdentifier("currentPreset")
            // Feature 002 FR-120: the scope Next/Previous/Random walk, and its playable count.
            Text(coordinator.presets.scopeLine)
                .font(.caption)
                .lineLimit(nameLines)
                .accessibilityIdentifier("scopeLine")
        }
    }

    /// AUD-007: the audio route while In-App Playback or Microphone runs; never for System/App Capture.
    private var routeIndicator: AudioRouteIndicator? {
        coordinator.routeContext.map { AudioRouteIndicator(route: coordinator.routes.route, context: $0) }
    }

    /// One row of icon buttons (FR-087).
    /// The compact grid's minimum cell width, scaled with Dynamic Type (32 pt at the default size).
    @ScaledMetric(relativeTo: .title3) private var buttonCellWidth: CGFloat = 32

    private var compact: some View {
        // ACC-006-R1: at accessibility sizes the status and the tempo group stack; side by side the
        // tempo readout ("120 BPM", "Detected") was clipped to a 63 pt column at AX5 (audit 2026-11-13).
        VStack(spacing: 8) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    SourceStatusIndicator(coordinator: coordinator)
                    TempoControls(coordinator: coordinator, compact: true)   // SHOW-011
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    SourceStatusIndicator(coordinator: coordinator)
                    Spacer(minLength: 0)
                    TempoControls(coordinator: coordinator, compact: true)   // SHOW-011
                }
            }
            if let route = routeIndicator {   // AUD-007: own row, the iPhone is narrow
                HStack { route; Spacer(minLength: 0) }
            }
            presetName.frame(maxWidth: .infinity, alignment: .leading)
            // A grid that wraps instead of one row (2026-11-13): with Save Frame, Record and Black out
            // the row had about 11 buttons, and at the largest text sizes it ran off the screen (the
            // Presets button sat at x 412 on a 402 pt iPhone). Cells keep a minimum width that scales
            // with the text, so every control stays on screen and tappable at any size.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: buttonCellWidth), spacing: 0)], spacing: 4) {
                ForEach(buttons, id: \.id) { item in
                    Button(action: item.action) {
                        Image(systemName: item.icon).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item.value ?? "")
                    .accessibilityHint(item.hint ?? "")
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
                routeIndicator          // AUD-007
                Spacer()
                presetName
            }
            HStack(spacing: 10) {
                ForEach(buttons, id: \.id) { item in
                    Button(action: item.action) {
                        Label(item.title, systemImage: item.icon)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityValue(item.value ?? "")
                    .accessibilityHint(item.hint ?? "")
                    .accessibilityIdentifier(item.id)
                }
                TempoControls(coordinator: coordinator)   // SHOW-011
            }
        }
    }

    private struct Item {
        let id: String
        let title: String
        let icon: String
        var value: String? = nil
        /// ACC-004-R4: what a short label acts on, for VoiceOver.
        var hint: String? = nil
        let action: () -> Void
    }

    private var buttons: [Item] {
        let presetIDs: Set<String> = ["previous", "next", "random", "presets"]
        return allButtons.filter { !coordinator.showsAlternateVisual || !presetIDs.contains($0.id) }
    }

    /// OUT-010: one tap blacks out, one tap restores (spec Clarifications: no confirmation).
    private var blackoutItem: Item {
        let external = coordinator.externalDisplay
        let requested = external.isBlackoutRequested
        return Item(id: "blackout", title: requested ? "Restore output" : "Black out output",
                    icon: requested ? "eye" : "eye.slash", value: external.blackoutPhase.accessibilityValue,
                    hint: requested ? "Shows the visualization on the output again" : "Makes the output black") {
            external.toggleBlackout()
        }
    }

    /// REC-003: Record / Stop recording; for projectM a tap refuses with the reason (REC-003-R12).
    private var recordItem: Item {
        let recording = coordinator.videoRecording
        if let remaining = recording.state.countdownRemaining { return countdownItem(recording, remaining: remaining) }
        let active = recording.state == .recording
        return Item(id: "record", title: active ? "Stop recording" : "Record", icon: active ? "stop.circle" : "record.circle",
                    value: active ? "Recording, \(recording.indicatorAccessibilityText)" : (recording.isRecordable ? nil : "Unavailable for projectM"),
                    hint: recording.audioStatusText) {   // REC-004-R9: the audio the recording holds
            coordinator.showControls()
            recording.toggle()
        }
    }

    /// REC-007-R7: while counting down, Record reads "Cancel countdown" (a tap cancels, REC-007-R4).
    private func countdownItem(_ recording: VideoRecordingCoordinator, remaining: Int) -> Item {
        Item(id: "record", title: "Cancel countdown", icon: "xmark.circle", value: StatusEventCatalog.countdownText(remaining),
             hint: "Stops the countdown; nothing is recorded") {
            coordinator.showControls()
            recording.toggle()
        }
    }

    /// SCN-015-R2, R8: one tap locks; unlocking asks first (the badge presents the confirmation).
    private var lockItem: Item {
        let lock: SceneLock = coordinator.settings.sceneLock
        let locked: Bool = lock.isLocked
        return Item(id: "lockScene", title: locked ? "Unlock scene" : "Lock scene", icon: locked ? "lock.fill" : "lock.open",
                    value: lock.accessibilityValue,
                    hint: locked ? "Asks before allowing edits again" : "Stops edits to the scene; cues still play") {
            coordinator.showControls()
            if locked { lock.isConfirmingUnlock = true } else { lock.lock() }
        }
    }

    private var allButtons: [Item] {
        [
            Item(id: "stop", title: "Stop", icon: "stop.fill") { coordinator.stop() },
            Item(id: "switchSource", title: UIStrings.switchSource, icon: "arrow.left.arrow.right",
                 hint: "Changes the audio source without leaving the visualizer") {   // AUD-012-R1
                coordinator.showControls()
                coordinator.showSourceSwitcher = true
            },
            Item(id: "pauseResume", title: coordinator.userPaused ? "Resume" : "Pause",
                 icon: coordinator.userPaused ? "play.fill" : "pause.fill") { coordinator.togglePause() },
            blackoutItem,
            lockItem,   // SCN-015
            Item(id: "saveFrame", title: "Save Frame", icon: "camera.viewfinder") {   // REC-001
                coordinator.showControls()
                coordinator.frameCapture.requestSave()
            },
            recordItem,
            Item(id: "previous", title: "Previous", icon: "backward.fill", hint: "Plays the previous preset in the list") {
                coordinator.previous()
            },
            Item(id: "next", title: "Next", icon: "forward.fill", hint: "Plays the next preset in the list") { coordinator.next() },
            Item(id: "random", title: "Random", icon: "shuffle", hint: "Plays a random preset from the list") { coordinator.random() },
            Item(id: "presets", title: "Presets", icon: "list.bullet", hint: "Opens the preset browser") {
                coordinator.showPresetBrowser = true
            },
            Item(id: "settings", title: "Settings", icon: "gearshape") { coordinator.showSettings = true },
        ]
    }
}
