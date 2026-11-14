// VisualizerView.swift — the full-screen visualization (task T084; FR-040, FR-041, FR-042, FR-083,
// FR-085, FR-086, FR-089). The renderer's view fills the window in portrait, landscape and iPad
// split view; a tap toggles the controls; the source-and-state indicator is always visible.
// VIS-001, VIS-002: when Settings chooses a native spectrum (Circular or Linear), its Metal view
// replaces the renderer's view (projectM is paused meanwhile); if it cannot be created a notice says
// projectM is shown instead.
// CAM-001: the Camera visual (camera layer under the circular spectrum) replaces the renderer's view
// the same way; a non-blocking banner explains a denied, restricted, missing or paused camera, with
// "Open Settings" when access is off.
// CAM-012: while the camera runs, a "Camera on" badge with Stop camera stays at the top, with or
// without the controls.
// MED-001: the Photo visual (imported photo under the circular spectrum) replaces the renderer's view
// the same way; the photo notice (an import refused, the stored copy unreadable) is a non-blocking
// banner with Dismiss.
// MED-002: the Video visual (imported video under the circular spectrum) replaces it the same way,
// with its own non-blocking notice; DEBUG diagnostics expose the shown picture's index.
// MED-009: the Text visual (circular spectrum with the saved text over it) replaces it the same way;
// DEBUG diagnostics expose the text rendering's size and pixel checksum (`textRendering`).
// AUD-007: a route change's explanation shows above the source-and-state indicator for about 4 s.
// OUT-001: every visual is hosted through a `VisualSlotHost`; while a connected external display shows
// the visualization, the device's slot is empty (black) with a short note, and everything else here
// (controls, badges, banners, sheets) stays on the device.
// OUT-010: while the output is blacked out (or restoring) a persistent badge with Restore stays at
// the top, with or without the controls, and the external display note says the display is black.
// SHOW-014: the persistent emergency Black out button (bottom trailing, with or without the
// controls) and the B key on it and on the badge's Restore.
// REC-001: Save Frame's format choice, the Files exporter and its notice; DEBUG `frameCaptureProbe`.
// REC-003: the recording indicator, the system file mover for a finished recording, its notice;
// DEBUG `videoRecordingProbe`.
// REC-012: the ready panels (Save…, Share…, Discard) and the share notice (`CaptureResultPanels`).
// SHOW-001: the show's keyboard shortcuts (arrows, Page Up/Down; with or without the controls), its
// step notice, Settings → Show, and the DEBUG probe `showAppliedScene` (applied scene ID | visual).
// ACC-003: status symbols on the recording and blackout badges, opaque bordered badges with Increase
// Contrast, the visualization ignores Smart Invert; DEBUG probe `statusAppearanceProbe`.
import AudioCore
import CaptureKit
import CaptureUI
import FrameCapture
import PresentationLifecycle
import PresetLibrary
import Rendering
import SwiftUI
import TextLayer
import VideoLayer
import UIKit

struct VisualizerView: View {
    @Bindable var coordinator: AppCoordinator

    // Split into separately type-checked parts (2026-11-14): as one expression this body made
    // Xcode 26 on CI give up ("unable to type-check this expression in reasonable time", run
    // 43557257624). Order of modifiers is unchanged: layers, system overlays, presentations, changes.
    var body: some View {
        withChangeHandlers(withPresentations(layers))
    }

    // Split into @ViewBuilder parts with explicit types (2026-11-14): as one ZStack this getter took
    // 314-396 ms to type-check (budget 300 ms). The layers and their modifiers are unchanged and in
    // the same order; ZStack and VStack flatten each part's children as before.
    private var layers: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            visual
                .accessibilityIgnoresInvertColors()   // ACC-003-R10: Smart Invert leaves the visualization alone
            // PERF-014-R10: a visual that can show nothing fades to the placeholder (0.5 s, linear).
            RenderPlaceholderView(shown: coordinator.showsRenderPlaceholder)
            externalDisplayLayer
            pausedLayer
            tapArea
            statusStack
            keyCommandLayers
            SceneSwitcherLayer(coordinator: coordinator)   // UIX-002: the quick scene switcher
            performanceLayer
            diagnostics
        }
        .statusBarHidden(coordinator.hidesSystemOverlays)
        .persistentSystemOverlays(coordinator.hidesSystemOverlays ? .hidden : .automatic)
    }

    @ViewBuilder private var externalDisplayLayer: some View {
        if coordinator.externalDisplay.showsVisualExternally {
            // OUT-001-R2: the visualization is drawn on the external display only (no device preview, R3).
            externalDisplayNote
        }
    }

    @ViewBuilder private var pausedLayer: some View {
        if coordinator.userPaused {
            // FR-085: the last frame stays, dimmed, with "Paused".
            Color.black.opacity(0.5).ignoresSafeArea().allowsHitTesting(false)
            Text("Paused")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .accessibilityIdentifier("pausedLabel")
        }
    }

    /// A full-screen tap target above the renderer (the renderer's UIView takes no taps).
    private var tapArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { () -> Void in coordinator.toggleControls() }
            .accessibilityIdentifier("visualizerTapArea")
            .accessibilityLabel("Visualization")
            .accessibilityHint("Shows or hides the controls")
            .modifier(MIDIPanicVisualizerCommands(coordinator: coordinator))   // MIDI-013-R7: ⌘⇧M, VoiceOver action
    }

    private var statusStack: some View {
        VStack(spacing: 8) {
            topStatus
            banners
            Spacer()
            bottomStatus
        }
        .padding()
        // ACC-001-R2: the controls and the badges riding on them are instant with Reduce Motion.
        .reduceMotionAware(MotionPolicy.controlsFade, value: coordinator.controlsVisible, policy: coordinator.motion)
    }

    /// Top status stack. OSC-007-R2, R6: the OSC listener badge, with or without the controls; then
    /// CAM-012's "Camera on" badge.
    @ViewBuilder private var topStatus: some View {
        OSCListenerBadge(osc: coordinator.osc) { () -> Void in coordinator.statusEvents.post(StatusEventCatalog.osc(port: nil)) }
        // PERF-010-R4: the recovery offer after an abnormal exit (non-blocking).
        SessionRecoveryOfferCard(recovery: coordinator.recovery, onReopen: { () -> Void in coordinator.reopenLastScene() },
                                 onStartFresh: { () -> Void in coordinator.startFresh() },
                                 onShown: { () -> Void in coordinator.announceRecoveryOffer() })
        let indicator: CameraIndicator = coordinator.cameraIndicator
        if indicator.isShown {   // CAM-012-R1 to R3: never hidden with the controls
            CameraIndicatorBadge(indicator: indicator) { () -> Void in coordinator.stopCamera() }
                .transition(.opacity)
        }
        if coordinator.externalDisplay.blackoutPhase != .live {   // OUT-010-R9: never hidden with the controls
            OutputBlackoutBadge(external: coordinator.externalDisplay)
                .transition(.opacity)
        }
        StatusCaptionView(router: coordinator.statusEvents)   // ACC-011-R7: camera off, OSC off, restored, reopened
    }

    @ViewBuilder private var bottomStatus: some View {
        // AUD-007: the short explanation of a route change, with or without the controls.
        if let explanation = coordinator.routes.explanation, coordinator.routeContext != nil {
            Text(explanation)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlaySurface(Capsule())   // ACC-008-R2
                .transition(.opacity)
                .accessibilityIdentifier("routeExplanation")
        }
        if let notice = coordinator.show.notice {   // SHOW-001-R9
            ShowNotice(text: notice).transition(.opacity)
        }
        if coordinator.externalDisplay.blackoutPhase.offersEmergencyBlackout {   // SHOW-014-R1: with or without the controls
            HStack { Spacer(); EmergencyBlackoutButton(external: coordinator.externalDisplay) }
                .transition(.opacity)
        }
        if coordinator.controlsVisible {
            ControlsOverlay(coordinator: coordinator)
                .transition(.opacity)
        } else {
            SourceStatusIndicator(coordinator: coordinator)
        }
    }

    @ViewBuilder private var keyCommandLayers: some View {
        if coordinator.show.hasCues && !coordinator.showSettings {   // SHOW-001-R15
            ShowKeyCommands(coordinator: coordinator)
        }
        // SCN-010-R10; UIX-002: ⌘Z belongs to the scene switcher's field while it is open.
        if !coordinator.showSettings && !coordinator.sceneSwitcher.isOpen { SceneHistoryKeyCommands(coordinator: coordinator) }
    }

    @ViewBuilder private var performanceLayer: some View {
        if coordinator.settings.showsPerformanceOverlay, coordinator.renderer != nil || coordinator.showsAlternateVisual {
            performanceOverlay
        }
    }

    /// FR-048 overlay, top trailing; PERF-001: its stage lines, and no stage timing once it is gone (R8).
    private var performanceOverlay: some View {
        let overlay = PerformanceOverlay(metrics: { coordinator.activeVisualMetrics }, manager: coordinator.manager,
                                         renderHealth: { coordinator.renderHealthOverlayLine },
                                         stageLines: { () -> [String] in coordinator.frameStageLines() })
        return VStack { HStack { Spacer(); overlay }; Spacer() }
            .padding(.top, 2)
            .padding(.trailing, 8)
            .onDisappear { coordinator.stopFrameStageTiming() }
    }

    /// The DEBUG panels and the UI-test probes (all invisible or DEBUG-only).
    @ViewBuilder private var diagnostics: some View {
        #if DEBUG
        if let fake = coordinator.fakeSource {
            VStack { HStack { FakeSourcePanel(fake: fake); Spacer() }; Spacer() }
                .padding(.top, 2)
        }
        if UITestSessionEventPanel.isRequested {   // AUD-014: InterruptionUITests
            VStack { HStack { UITestSessionEventPanel(); Spacer() }; Spacer() }
                .padding(.top, 2)
        }
        if UITestRouteProvider.isRequested {       // AUD-007: RouteIndicatorUITests
            VStack { HStack { UITestRoutePanel(); Spacer() }; Spacer() }
                .padding(.top, 40)
        }
        if UITestModulationPanel.isRequested {     // MOD-002: AudioFeatureBindingUITests
            VStack { HStack { UITestModulationPanel(coordinator: coordinator); Spacer() }; Spacer() }
                .padding(.top, 70)
        }
        if UITestMemoryPanel.isRequested {         // PERF-006: MemoryPressureUITests
            VStack { HStack { UITestMemoryPanel(coordinator: coordinator); Spacer() }; Spacer() }
                .padding(.top, 130)
        }
        if UITestCameraEventPanel.isRequested {    // CAM-013: CameraRecoveryUITests
            VStack { HStack { UITestCameraEventPanel(coordinator: coordinator); Spacer() }; Spacer() }
                .padding(.top, 220)
        }
        if UITestRenderFaultPanel.isRequested {    // PERF-014: RenderFaultUITests
            VStack { HStack { UITestRenderFaultPanel(coordinator: coordinator); Spacer() }; Spacer() }
                .padding(.top, 160)
        }
        if FrameCaptureCoordinator.debugDirectoryFromArguments() != nil {   // REC-001: FrameCaptureUITests
            Text(coordinator.frameCapture.probe)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("frameCaptureProbe")
                .accessibilityValue(coordinator.frameCapture.probe)
        }
        if VideoRecordingCoordinator.debugDirectoryFromArguments() != nil
            || VideoRecordingCoordinator.debugStorageRequested {   // REC-003, REC-015: recording UI tests
            Text(coordinator.videoRecording.probe)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("videoRecordingProbe")
                .accessibilityValue(coordinator.videoRecording.probe)
        }
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {   // SHOW-001: ShowCueUITests
            let value = "\(coordinator.show.appliedSceneID ?? "none")|\(coordinator.settings.visual.rawValue)"
            Text(value)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("showAppliedScene")
                .accessibilityValue(value)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") { UITestCueTransitionProbe(stage: coordinator.cueTransitions) }   // XFADE
        #endif
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {   // ACC-004-R9: the last announcement
            let spoken = coordinator.announcer.lastSpoken
            Text(spoken)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("announcementProbe")
                .accessibilityValue(spoken)
        }
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {   // ACC-003 contract C3; ACC-008 C4
            StatusAppearanceProbe()
            OverlaySurfaceProbe()
        }
        if AppCoordinator.reduceMotionPanelRequested {   // ACC-001: ReduceMotionUITests (contract C2)
            VStack { HStack { reduceMotionPanel; Spacer() }; Spacer() }
                .padding(.top, 190)
        }
        if UITestExternalDisplay.isRequested {     // OUT-001: ExternalDisplayUITests
            VStack { HStack { UITestExternalDisplayPanel(coordinator: coordinator.externalDisplay); Spacer() }; Spacer() }
                .padding(.top, 100)
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
            Text("\(coordinator.sourceStarts)")
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("sourceStarts")
                .accessibilityValue("\(coordinator.sourceStarts)")
            // OUT-010: whether the slot holding the visual is black, and whether the visual still draws.
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let external = coordinator.externalDisplay
                let state = external.isOutputBlack ? "black" : external.blackoutPhase.rawValue
                let running = coordinator.activeVisualMetrics.framesPerSecond > 0 ? "yes" : "no"
                Text(state)
                    .font(.caption2)
                    .opacity(0.01)
                    .accessibilityIdentifier("outputBlackout")
                    .accessibilityValue(state)
                Text(running)
                    .font(.caption2)
                    .opacity(0.01)
                    .accessibilityIdentifier("visualRunning")
                    .accessibilityValue(running)
            }
            if let camera = coordinator.cameraVisual {   // CAM-001: frames that showed a camera picture
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text("\(camera.framesShown)")
                        .font(.caption2)
                        .opacity(0.01)
                        .accessibilityIdentifier("cameraFramesShown")
                        .accessibilityValue("\(camera.framesShown)")
                }
            }
            if let photo = coordinator.photoVisual {   // MED-001: frames that showed the photo
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text("\(photo.framesShown)")
                        .font(.caption2)
                        .opacity(0.01)
                        .accessibilityIdentifier("photoFramesShown")
                        .accessibilityValue("\(photo.framesShown)")
                }
            }
            #if DEBUG
            MediaProbes(coordinator: coordinator)   // MED-006-R15 slideshow, MED-010-R14 logo (own view: keeps `layers` quick to type-check)
            #endif
            if let video = coordinator.videoVisual {   // MED-002: frames shown and the shown picture's index
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let index = video.shownFrameIndex().map(String.init) ?? "none"
                    VStack {
                        Text("\(video.framesShown)")
                            .accessibilityIdentifier("videoFramesShown")
                            .accessibilityValue("\(video.framesShown)")
                        Text(index)
                            .accessibilityIdentifier("videoFrameIndex")
                            .accessibilityValue(index)
                    }
                    .font(.caption2)
                    .opacity(0.01)
                }
                VideoLoopProbe(video: video)   // MED-003
            }
            #if DEBUG
            // PERF-010-R12: the recovery decision and whether the OSC transport listens.
            let recoveryProbe = coordinator.recovery.probe(oscListening: coordinator.osc.isListenerOpen)
            Text(recoveryProbe)
                .font(.caption2)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityIdentifier("sessionRecovery")
                .accessibilityValue(recoveryProbe)
            if let autosave = coordinator.sceneAutosave {   // SCN-002-R12: the committed revision
                Text(autosave.probe)
                    .font(.caption2)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("sceneAutosave")
                    .accessibilityValue(autosave.probe)
            }
            if coordinator.textVisual != nil {   // MED-009-R14: the rendering's size and checksum
                let value = Self.textRenderingValue(coordinator.textState)
                Text(value)
                    .font(.caption2)
                    .opacity(0.01)
                    .accessibilityIdentifier("textRendering")
                    .accessibilityValue(value)
            }
            #endif
        }
    }

    /// Sheets, dialogs and the Files exporter and mover.
    private func withPresentations(_ content: some View) -> some View {
        withDialogsAndFiles(withSheets(content))
    }

    /// Sheets (presets, purchase, queue, Settings, repair) and their alerts.
    private func withSheets(_ content: some View) -> some View {
        content
        .sheet(isPresented: $coordinator.showPresetBrowser) {
            PresetBrowserView(presets: coordinator.presets, userPresets: coordinator.userPresets) { coordinator.choose($0, from: $1) }
                .sheet(isPresented: Binding(get: { coordinator.presets.purchaseRequested },
                                            set: { coordinator.presets.purchaseRequested = $0 })) { purchaseSheet }
        }
        // A locked pack reached from the controls (Next/Random with no playable preset).
        .sheet(isPresented: Binding(get: { coordinator.presets.purchaseRequested && !coordinator.showPresetBrowser },
                                    set: { coordinator.presets.purchaseRequested = $0 })) { purchaseSheet }
        // PRE-015: "Duplicate to My Presets" from the controls (the browser shows its own).
        .duplicateResultAlert(coordinator.userPresets, isPresented: !coordinator.showPresetBrowser)
        // ACC-002-R6: a flagged preset chosen after a purchase from the controls (the browser shows its own).
        .flashWarningAlert(coordinator.presets, isPresented: !coordinator.showPresetBrowser)
        // AUD-003: the queue over the visualizer; edits never interrupt playback.
        .sheet(isPresented: $coordinator.showQueue, onDismiss: { coordinator.closeQueue() }) {
            NavigationStack {
                PlayQueueView(queue: coordinator.audioLibrary.queue, isPlaying: coordinator.transport.state == .playing,
                              onDone: { coordinator.closeQueue() })
            }
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView(settings: coordinator.settings, osc: coordinator.osc,
                         reduceFlashingAvailable: coordinator.renderer?.supportsReduceFlashing ?? true,
                         nativeVisualUnavailable: coordinator.nativeVisualUnavailable,
                         glowUnavailable: coordinator.glowUnavailable, photos: coordinator.photos,
                         slideshow: coordinator.slideshow,   // MED-006
                         logo: coordinator.logo,   // MED-010
                         videos: coordinator.videos, texts: coordinator.texts,
                         show: coordinator.show, addCurrentScene: { coordinator.addCurrentSceneToShow() },
                         libraryBackup: coordinator.libraryBackup,   // FILE-005
                         cacheFilesInUse: { () -> Set<String> in coordinator.cacheFilesInUse() },
                         missingMedia: coordinator.missingMedia,   // MED-013
                         openGuide: { coordinator.openGuidedFirstScene() },
                         history: coordinator.sceneHistory,      // UIX-001, SCN-010
                         layerInspector: coordinator,            // CMP-015
                         inputTrim: coordinator.inputTrim,       // AUD-008
                         channelSelection: coordinator.channelSelection,   // AUD-009
                         playbackBalance: coordinator.playbackBalance,   // AUD-010
                         playbackBalanceAvailable: coordinator.playbackBalanceAvailable,
                         noiseGate: coordinator.noiseGate,   // AUD-011
                         latencyOffset: coordinator.latencyOffset,   // AUD-013
                         colorGrade: coordinator.colorGrade,   // FX-003
                         motionFeedback: coordinator.motionFeedback,   // FX-009
                         midi: coordinator.midi,   // MIDI-001
                         recordingAudio: coordinator.recordingAudio,   // REC-004
                         recordingAudioStatus: { () -> String in coordinator.videoRecording.audioStatusText },
                         recordingQuality: coordinator.recordingQuality,   // REC-005
                         recordingCountdown: coordinator.recordingCountdown,   // REC-007
                         externalOutput: coordinator.externalOutput,   // OUT-004
                         recordingTimedStop: coordinator.recordingTimedStop,   // REC-008
                         explainers: coordinator.explainers,   // UIX-015
                         cameraStatus: { () -> PermissionState? in coordinator.cameraPermissionStatus },
                         recentPresets: coordinator.presets.recent,   // PRE-006
                         announcer: coordinator.announcer)   // ACC-005-R7
                .environment(\.parameterShelf, coordinator.parameterShelf)   // UIX-004-R1: Pin to Shelf in Inspect
                .sceneRepairSheet(coordinator.sceneRepair, active: true)   // SCN-012: a show editor step's report
        }
        // SCN-012: the repair report before a cue's scene or Reopen opens (over Settings while it is shown).
        .sceneRepairSheet(coordinator.sceneRepair, active: !coordinator.showSettings)
    }

    /// Confirmation dialogs and the Files exporter and mover.
    private func withDialogsAndFiles(_ content: some View) -> some View {
        content
        // AUD-012: the other available sources; the handoff keeps the visual running.
        .confirmationDialog(UIStrings.switchSource, isPresented: Binding(get: { coordinator.showSourceSwitcher },
                                                                        set: { coordinator.showSourceSwitcher = $0 }),
                            titleVisibility: .visible) {
            ForEach(coordinator.switchTargets, id: \.self) { (mode: AudioSourceMode) in
                Button(UIStrings.label(mode)) { coordinator.switchSource(to: mode) }
                    .accessibilityIdentifier("switchSource:\(mode.rawValue)")
            }
            Button("Cancel", role: .cancel) {}
        }
        // REC-001: the format choice (HEIF only where it can be encoded) and the system Files exporter.
        .confirmationDialog("Save Frame", isPresented: Binding(get: { coordinator.frameCapture.showFormatChoice },
                                                              set: { coordinator.frameCapture.showFormatChoice = $0 }),
                            titleVisibility: .visible) {
            ForEach(coordinator.frameCapture.availableFormats, id: \.self) { (format: FrameCaptureFormat) in
                Button(format.title) { coordinator.frameCapture.save(format) }
                    .accessibilityIdentifier("saveFrame\(format.title)")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The next frame of the visualization is saved where you choose in Files.")
        }
        .fileExporter(isPresented: Binding(get: { coordinator.frameCapture.showExporter },
                                           set: { (shown: Bool) in
                                               coordinator.frameCapture.showExporter = shown
                                               if !shown { coordinator.frameCapture.exportDismissed() }   // R10: no copy kept
                                           }),
                      document: coordinator.frameCapture.document,
                      contentType: coordinator.frameCapture.document?.contentType ?? .png,
                      defaultFilename: coordinator.frameCapture.offeredBaseName) { (result: Result<URL, any Error>) in
            coordinator.frameCapture.exportFinished(result)
        }
        // REC-003: the finished recording is moved (not copied) to the folder the user picks in Files.
        .fileMover(isPresented: Binding(get: { coordinator.videoRecording.showMover },
                                        set: { coordinator.videoRecording.showMover = $0 }),
                   file: coordinator.videoRecording.fileToMove) { (result: Result<URL, any Error>) in
            coordinator.videoRecording.moverFinished(result)
        } onCancellation: {
            coordinator.videoRecording.moverCancelled()   // REC-003-R13: the temporary file is deleted
        }
    }

    /// Settings and state changes forwarded to the coordinator. Split into short chains (2026-11-14):
    /// one chain of 17 `.onChange` modifiers made CI's Xcode 26 give up type-checking (run 43564700735).
    private func withChangeHandlers(_ content: some View) -> some View {
        withSourceChanges(withVisualChanges(withCameraChanges(content)))
    }

    private func withCameraChanges(_ content: some View) -> some View {
        content
        .onChange(of: coordinator.settings.cameraPosition) { coordinator.cameraSettingsChanged() }         // CAM-002
        .onChange(of: coordinator.settings.cameraMirrored) { coordinator.cameraSettingsChanged() }
        .onChange(of: coordinator.settings.cameraCropMode) { coordinator.cameraSettingsChanged() }         // CAM-007
        .onChange(of: coordinator.settings.cameraCropAnchor) { coordinator.cameraSettingsChanged() }
        .onChange(of: coordinator.settings.cameraZoom) { coordinator.cameraSettingsChanged() }
    }

    private func withVisualChanges(_ content: some View) -> some View {
        withSpectrumChanges(content
            .onChange(of: coordinator.settings.reduceFlashing) { coordinator.applyReduceFlashing() }
            .onChange(of: coordinator.settings.sensorySafety.profile) { coordinator.applyReduceFlashing() }   // ACC-012
            .onChange(of: coordinator.settings.visual) { coordinator.visualSettingsChanged() }                 // VIS-001
            .onChange(of: coordinator.settings.glowParameters) { coordinator.glowSettingsChanged() }          // FX-001
            .onChange(of: coordinator.settings.colorBlindSafePalette) { coordinator.spectrumPaletteChanged() }) // ACC-003-R13
    }

    private func withSpectrumChanges(_ content: some View) -> some View {
        content
        .onChange(of: coordinator.settings.circularSpectrumBars) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.settings.linearSpectrumOrientation) { coordinator.visualSettingsChanged() }   // VIS-002
        .onChange(of: coordinator.settings.linearSpectrumSpacing) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.settings.oscilloscopeLine) { coordinator.visualSettingsChanged() }   // VIS-003
        .onChange(of: coordinator.settings.oscilloscopeWindowMilliseconds) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.settings.lissajousMode) { coordinator.visualSettingsChanged() }   // VIS-004
        .onChange(of: coordinator.settings.lissajousPersistence) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.settings.radialWaveformRing) { coordinator.visualSettingsChanged() }   // VIS-005
        .onChange(of: coordinator.settings.radialWaveformAmplitude) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.settings.spectrumSmoothing) { coordinator.visualSettingsChanged() }   // ANL-003
    }

    private func withSourceChanges(_ content: some View) -> some View {
        content
        .onChange(of: coordinator.manager.state) {
            coordinator.routes.refresh()   // AUD-007-R3: a source started or changed state
            coordinator.announceSourceStatus()   // FR-070, AUD-016-R16, AUD-012-R7 (ACC-011 X1-X3)
        }
        .onChange(of: coordinator.manager.stopReason) { _, reason in
            // AUD-014-R18: In-App Playback went on hold; ACC-011-R5: one text per change.
            if reason != nil { coordinator.announceSourceStatus() }
        }
        .modifier(StatusEventChanges(coordinator: coordinator))   // ACC-011: recording, capture, blackout
    }

    #if DEBUG
    /// ACC-001-R9: the last controls transition's duration and a simulated system toggle.
    private var reduceMotionPanel: some View {
        HStack(spacing: 6) {
            Button("Toggle Reduce Motion") { coordinator.simulateSystemReduceMotionToggle() }
                .font(.caption2)
                .accessibilityIdentifier("simulateReduceMotionToggle")
            Text(coordinator.motionProbe)
                .font(.caption2)
                .accessibilityIdentifier("motionProbe")
                .accessibilityValue(coordinator.motionProbe)
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
    }
    #endif

    private var purchaseSheet: some View {
        PurchaseSheet(packs: coordinator.presets.library?.packs ?? [], price: coordinator.entitlements.displayPrice,
                      state: coordinator.entitlements.state, onBuy: coordinator.buyLibrary,
                      onRestore: coordinator.restorePurchases)
    }

    #if DEBUG
    /// "none", "drawing", "failed" or "<width>x<height> <16 hex digits>" (TextOverlayUITests).
    static func textRenderingValue(_ state: TextLayerState) -> String {
        switch state {
        case .empty: "none"
        case .drawing: "drawing"
        case .failed: "failed"
        case .ready(let width, let height, let checksum):
            "\(width)x\(height) " + String(repeating: "0", count: 16 - String(checksum, radix: 16).count) + String(checksum, radix: 16)
        }
    }
    #endif

    /// The shown visual: Camera, Photo, a native spectrum or projectM.
    @ViewBuilder private var visual: some View {
        if coordinator.showsCameraVisual, let camera = coordinator.cameraVisual {
            VisualSlotHost(visual: camera.view, external: coordinator.externalDisplay)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Camera visualization")
                .accessibilityValue(coordinator.cameraState.accessibilityValue)   // CAM-001-R14
                .accessibilityIdentifier("cameraVisual")
        } else if coordinator.showsPhotoVisual, let photo = coordinator.photoVisual {
            VisualSlotHost(visual: photo.view, external: coordinator.externalDisplay)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Photo visualization")
                .accessibilityValue(PhotoVisualHost.accessibilityValue(coordinator.photoState))   // MED-001-R15
                .accessibilityIdentifier("photoVisual")
        } else if coordinator.showsVideoVisual, let video = coordinator.videoVisual {
            VisualSlotHost(visual: video.view, external: coordinator.externalDisplay)   // OUT-001: like Photo
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Video visualization")
                .accessibilityValue(VideoVisualHost.accessibilityValue(coordinator.videoState))   // MED-002-R19
                .accessibilityIdentifier("videoVisual")
        } else if coordinator.showsTextVisual, let text = coordinator.textVisual {
            VisualSlotHost(visual: text.view, external: coordinator.externalDisplay)   // OUT-001: like Photo
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Text visualization")
                .accessibilityValue(TextOverlayCoordinator.accessibilityValue(coordinator.texts.spec))   // MED-009-R13
                .accessibilityIdentifier("textVisual")
        } else if coordinator.showsNativeVisual, let native = coordinator.nativeVisual {
            VisualSlotHost(visual: native.view, external: coordinator.externalDisplay)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("\(native.style.title) visualization")
                .accessibilityValue(NativeSpectrumHost.accessibilityValue(style: native.style,
                                                                          glowEnabled: coordinator.settings.glowEnabled,
                                                                          glowUnavailable: coordinator.glowUnavailable))   // FX-001, VIS-002-R13
                .accessibilityIdentifier(native.style.accessibilityIdentifier)
        } else if let renderer = coordinator.renderer {
            VisualSlotHost(visual: renderer.view, external: coordinator.externalDisplay)
                .ignoresSafeArea()
                .accessibilityIdentifier("visualizer")
        }
    }

    /// OUT-001: shown on the device while the visualization is on the external display; OUT-010-R9:
    /// it says when that display is blacked out.
    private var externalDisplayNote: some View {
        let black = coordinator.externalDisplay.isBlackoutRequested
        return Label(black ? "External display blacked out" : "Showing on external display", systemImage: black ? "tv.slash" : "tv")
            .font(.callout)
            .foregroundStyle(.white.opacity(0.8))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(black ? "The external display is blacked out" : "The visualization is showing on the external display")
            .accessibilityIdentifier("externalDisplayNote")
    }

    @ViewBuilder private var banners: some View {
        let manager = coordinator.manager
        if manager.stopReason != nil || manager.state == .noAudioReceived || manager.prolongedSilenceHint {
            StatusBanner(mode: manager.activeMode, state: manager.state, reason: manager.stopReason,
                         prolongedSilence: manager.prolongedSilenceHint) { coordinator.handle($0) }
                .padding(12)
                .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
        }
        // AUD-015-R7: what happened to the source while the app was away.
        if let notice = coordinator.visibleBackgroundNotice {
            BackgroundNoticeView(text: notice, announce: { coordinator.statusEvents.post(StatusEventCatalog.background($0)) }) {
                coordinator.dismissBackgroundNotice()
            }
        }
        // VIS-001-R16: the chosen native visual could not be created.
        if coordinator.nativeVisualUnavailable && coordinator.settings.visual.replacesProjectM {
            Text(AppCoordinator.nativeVisualUnavailableMessage(for: coordinator.settings.visual))
                .padding(10)
                .overlaySurface(Capsule())   // ACC-008-R2
                .accessibilityIdentifier("nativeVisualUnavailable")
        }
        MissingMediaTile(model: coordinator.missingMedia)   // MED-013-R2: a scene's media is missing
        // CAM-001-R5, R6, R8: never blocks; stays while the camera cannot show pictures.
        // FILE-013-R3: denied and restricted come from the permission catalog; the other states
        // (no camera, paused) keep CAM-001's notice without Open Settings. One notice view for both.
        // CAM-013-R2, R3: interrupted or failed name the reason and offer Retry.
        // UIX-015-R7: denied and restricted add the fallback and Dismiss (hidden for this attempt).
        if coordinator.showsCameraVisual, let notice = PermissionCatalog.cameraNotice(for: coordinator.cameraState, position: coordinator.settings.cameraPosition, reason: coordinator.cameraStopReason),
           !(notice.offersDismiss && coordinator.cameraNoticeDismissed) {
            PermissionNoticeView(notice: notice, symbol: "video.slash", identifierPrefix: "camera",
                                 retryPending: coordinator.cameraRetryPending,
                                 onRetry: { coordinator.retryCamera() },
                                 onDismiss: { coordinator.dismissCameraNotice() })
        }
        // MED-001-R11: never blocks; clears itself after a few seconds.
        if coordinator.showsPhotoVisual, !coordinator.showSettings, let notice = coordinator.photos.notice {
            HStack(spacing: 10) {
                Image(systemName: "photo")
                    .accessibilityHidden(true)
                Text(notice)
                    .font(.footnote)
                    .accessibilityIdentifier("photoNoticeText")
                Button("Dismiss") { coordinator.photos.clearNotice() }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("photoNoticeDismiss")
            }
            .padding(10)
            .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("photoNotice")
        }
        // MED-002-R14: never blocks; clears itself after a few seconds.
        if coordinator.showsVideoVisual, !coordinator.showSettings, let notice = coordinator.videos.notice {
            HStack(spacing: 10) {
                Image(systemName: "film")
                    .accessibilityHidden(true)
                Text(notice)
                    .font(.footnote)
                    .accessibilityIdentifier("videoNoticeText")
                Button("Dismiss") { coordinator.videos.clearNotice() }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("videoNoticeDismiss")
            }
            .padding(10)
            .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("videoNotice")
        }
        // REC-001: Save Frame's refusal, failure or "Frame saved." (FR-070: a labeled element).
        if let notice = coordinator.frameCapture.notice {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .accessibilityHidden(true)
                Text(notice)
                    .font(.footnote)
                    .accessibilityIdentifier("frameCaptureNoticeText")
                Button("Dismiss") { coordinator.frameCapture.clearNotice() }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("frameCaptureNoticeDismiss")
            }
            .padding(10)
            .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("frameCaptureNotice")
        }
        // REC-012: "Frame ready" / "Recording ready" with Save…, Share…, Discard; the share notice.
        CaptureResultPanels(frameCapture: coordinator.frameCapture, videoRecording: coordinator.videoRecording,
                            share: coordinator.captureShare)
        // REC-003: the recording indicator (app UI, never part of the recorded picture; REC-003-R16).
        RecordingCountdownView(recording: coordinator.videoRecording)   // REC-007-R7: the number and Cancel
        if coordinator.videoRecording.state.hasRecording {
            let finishing = coordinator.videoRecording.state == .finishing
            // ACC-003-R3: the record symbol, or an hourglass while finishing (was a red or grey dot).
            StatusCueLabel(cue: StatusCueCatalog.recording(finishing: finishing, elapsed: coordinator.videoRecording.indicatorText),   // REC-008-R8
                           font: .footnote.monospacedDigit().bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .statusBadgeBackground(Capsule())   // ACC-003-R9
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(finishing ? "Finishing the recording" : "Recording, \(coordinator.videoRecording.indicatorAccessibilityText)")
            .accessibilityIdentifier("recordingIndicator")
            RecordingAudioLine(recording: coordinator.videoRecording)   // REC-004-R9
        }
        // REC-003: refusals, stop reasons, failures and "Recording saved." (FR-070: a labeled element).
        if let notice = coordinator.videoRecording.notice {
            HStack(spacing: 10) {
                Image(systemName: "record.circle")
                    .accessibilityHidden(true)
                Text(notice)
                    .font(.footnote)
                    .accessibilityIdentifier("videoRecordingNoticeText")
                Button("Dismiss") { coordinator.videoRecording.clearNotice() }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("videoRecordingNoticeDismiss")
            }
            .padding(10)
            .overlaySurface(RoundedRectangle(cornerRadius: 12))   // ACC-008-R2
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("videoRecordingNotice")
        }
        if let failure = coordinator.presets.failureMessage {
            Text(failure)
                .padding(10)
                .overlaySurface(Capsule())   // ACC-008-R2
                .accessibilityIdentifier("presetFailedBanner")
        }
    }
}


/// OUT-010-R9, R10: the output blackout's persistent badge: "Output blacked out" with Restore, or
/// "Restoring output" while the restore waits or fades in.
struct OutputBlackoutBadge: View {
    let external: ExternalDisplayCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // ACC-006-R1: label over Restore at accessibility sizes; side by side both were cut to "Out…"
        // and "Rest…" at AX5 (audit 2026-11-13). A rounded rectangle there, as a capsule clips two rows.
        // Standard sizes keep the original one-row capsule.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { label; restore }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .statusBadgeBackground(RoundedRectangle(cornerRadius: 12))   // ACC-003-R9
                .modifier(BadgeAccessibility(external: external))
        } else {
            HStack(spacing: 10) { label; restore }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .statusBadgeBackground(Capsule())   // ACC-003-R9
                .modifier(BadgeAccessibility(external: external))
        }
    }

    private var label: some View {
        // ACC-003-R3: eye.slash while blacked out, eye while restoring (the words are unchanged).
        let cue: StatusCue = StatusCueCatalog.blackout(blackedOut: external.isBlackoutRequested && external.blackoutPhase == .blackedOut)
        return StatusCueLabel.text(cue)
            .font(.footnote.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(cue.text)
            .accessibilityIdentifier("blackoutBadgeText")   // the identified static text, as before
    }

    @ViewBuilder private var restore: some View {
        if external.blackoutPhase.offersRestore {
            Button("Restore") { external.setBlackout(false) }
                .font(.footnote)
                .buttonStyle(.borderedProminent)
                .overlayProminentTint()   // ACC-008-R5
                .keyboardShortcut("b", modifiers: [])   // SHOW-014-R6: B again restores

                .accessibilityLabel("Restore output")
                .accessibilityIdentifier("blackoutRestore")
        }
    }

    private struct BadgeAccessibility: ViewModifier {
        let external: ExternalDisplayCoordinator

        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .contain)
                .accessibilityValue(external.blackoutPhase.accessibilityValue)
                .accessibilityIdentifier("blackoutBadge")
        }
    }
}

extension OutputBlackout.Phase {
    /// OUT-010-R10: the output's state for VoiceOver.
    var accessibilityValue: String {
        switch self {
        case .live: "Live"
        case .blackedOut: "Blacked out"
        case .restoreWaiting: "Restore waiting"
        case .fadingIn: "Fading in"
        }
    }
}

/// MED-003-R12 (diagnostics only): the shown picture's index in the file, the applied loop region and
/// the loop counters, for VideoLoopUITests; MED-004-R11: the speed and its measured ratio (VideoSpeedUITests).
private struct VideoLoopProbe: View {
    let video: VideoVisualHost

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            probes
        }
    }

    private var probes: some View {
        let index: String = video.shownMediaFrameIndex().map { (i: Int) -> String in String(i) } ?? "none"
        let region: String = video.loopRegion.map { (r: VideoLoopRegion) -> String in
            String(r.inMilliseconds) + "-" + String(r.outMilliseconds)
        } ?? "whole"
        let stats: String = video.loopStatistics()
        let speed: String = video.speedProbe()   // MED-004-R11
        return VStack {
            Text(index).accessibilityIdentifier("videoMediaFrameIndex").accessibilityValue(index)
            Text(region).accessibilityIdentifier("videoLoopRegion").accessibilityValue(region)
            Text(stats).accessibilityIdentifier("videoLoopStats").accessibilityValue(stats)
            Text(speed).accessibilityIdentifier("videoSpeed").accessibilityValue(speed)
        }
        .font(.caption2)
        .opacity(0.01)
        .allowsHitTesting(false)
    }
}
