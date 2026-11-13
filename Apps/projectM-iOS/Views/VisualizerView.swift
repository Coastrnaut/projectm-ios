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
// AUD-007: a route change's explanation shows above the source-and-state indicator for about 4 s.
// OUT-001: every visual is hosted through a `VisualSlotHost`; while a connected external display shows
// the visualization, the device's slot is empty (black) with a short note, and everything else here
// (controls, badges, banners, sheets) stays on the device.
// OUT-010: while the output is blacked out (or restoring) a persistent badge with Restore stays at
// the top, with or without the controls, and the external display note says the display is black.
import CaptureKit
import CaptureUI
import PresentationLifecycle
import PresetLibrary
import Rendering
import SwiftUI
import UIKit

struct VisualizerView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            visual
            if coordinator.externalDisplay.showsVisualExternally {
                // OUT-001-R2: the visualization is drawn on the external display only (no device preview, R3).
                externalDisplayNote
            }
            if coordinator.userPaused {
                // FR-085: the last frame stays, dimmed, with "Paused".
                Color.black.opacity(0.5).ignoresSafeArea().allowsHitTesting(false)
                Text("Paused")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("pausedLabel")
            }
            // A full-screen tap target above the renderer (the renderer's UIView takes no taps).
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { coordinator.toggleControls() }
                .accessibilityIdentifier("visualizerTapArea")
                .accessibilityLabel("Visualization")
                .accessibilityHint("Shows or hides the controls")
            VStack(spacing: 8) {
                // Top status stack. OSC-007-R2, R6: the OSC listener badge, with or without the
                // controls; then CAM-012's "Camera on" badge.
                OSCListenerBadge(osc: coordinator.osc)
                let indicator = coordinator.cameraIndicator
                if indicator.isShown {   // CAM-012-R1 to R3: never hidden with the controls
                    CameraIndicatorBadge(indicator: indicator) { coordinator.stopCamera() }
                        .transition(.opacity)
                }
                if coordinator.externalDisplay.blackoutPhase != .live {   // OUT-010-R9: never hidden with the controls
                    OutputBlackoutBadge(external: coordinator.externalDisplay)
                        .transition(.opacity)
                }
                banners
                Spacer()
                // AUD-007: the short explanation of a route change, with or without the controls.
                if let explanation = coordinator.routes.explanation, coordinator.routeContext != nil {
                    Text(explanation)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.opacity)
                        .accessibilityIdentifier("routeExplanation")
                }
                if coordinator.controlsVisible {
                    ControlsOverlay(coordinator: coordinator)
                        .transition(.opacity)
                } else {
                    SourceStatusIndicator(coordinator: coordinator)
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: coordinator.controlsVisible)
            if coordinator.settings.showsPerformanceOverlay, coordinator.renderer != nil || coordinator.showsAlternateVisual {
                VStack { HStack { Spacer(); PerformanceOverlay(metrics: { coordinator.activeVisualMetrics }, manager: coordinator.manager) }; Spacer() }
                    .padding(.top, 2)
                    .padding(.trailing, 8)
            }
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
                }
            }
        }
        .statusBarHidden(coordinator.hidesSystemOverlays)
        .persistentSystemOverlays(coordinator.hidesSystemOverlays ? .hidden : .automatic)
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
                         videos: coordinator.videos)
        }
        .onChange(of: coordinator.settings.reduceFlashing) { coordinator.applyReduceFlashing() }
        .onChange(of: coordinator.settings.visual) { coordinator.visualSettingsChanged() }                 // VIS-001
        .onChange(of: coordinator.settings.circularSpectrumBars) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.settings.linearSpectrumOrientation) { coordinator.visualSettingsChanged() }   // VIS-002
        .onChange(of: coordinator.settings.linearSpectrumSpacing) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.settings.glowParameters) { coordinator.glowSettingsChanged() }          // FX-001
        .onChange(of: coordinator.manager.state) { _, state in
            coordinator.routes.refresh()   // AUD-007-R3: a source started or changed state
            SourceStatusIndicator.announce(mode: coordinator.manager.activeMode, state: state, signal: coordinator.testSignalName)   // FR-070, AUD-016-R16
        }
        .onChange(of: coordinator.manager.stopReason) { _, reason in
            // AUD-014-R18: In-App Playback went on hold (interrupted, or the output was disconnected).
            let manager = coordinator.manager
            if let text = SourceStatusIndicator.holdAnnouncement(mode: manager.activeMode, state: manager.state, reason: reason,
                                                                 signal: coordinator.testSignalName) {
                UIAccessibility.post(notification: .announcement, argument: text)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
            coordinator.systemReduceMotionChanged(UIAccessibility.isReduceMotionEnabled)
        }
    }

    private var purchaseSheet: some View {
        PurchaseSheet(packs: coordinator.presets.library?.packs ?? [], price: coordinator.entitlements.displayPrice,
                      state: coordinator.entitlements.state, onBuy: coordinator.buyLibrary,
                      onRestore: coordinator.restorePurchases)
    }

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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        // VIS-001-R16: the chosen native visual could not be created.
        if coordinator.nativeVisualUnavailable && coordinator.settings.visual.replacesProjectM {
            Text(AppCoordinator.nativeVisualUnavailableMessage(for: coordinator.settings.visual))
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier("nativeVisualUnavailable")
        }
        // CAM-001-R5, R6, R8: never blocks; stays while the camera cannot show pictures.
        if coordinator.showsCameraVisual, let notice = coordinator.cameraState.notice {
            HStack(spacing: 10) {
                Image(systemName: "video.slash")
                    .accessibilityHidden(true)
                Text(notice)
                    .font(.footnote)
                    .accessibilityIdentifier("cameraNoticeText")
                if coordinator.cameraState.offersSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("cameraOpenSettings")
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cameraNotice")
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("videoNotice")
        }
        if let failure = coordinator.presets.failureMessage {
            Text(failure)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier("presetFailedBanner")
        }
    }
}


/// OUT-010-R9, R10: the output blackout's persistent badge: "Output blacked out" with Restore, or
/// "Restoring output" while the restore waits or fades in.
struct OutputBlackoutBadge: View {
    let external: ExternalDisplayCoordinator

    var body: some View {
        let requested = external.isBlackoutRequested
        HStack(spacing: 10) {
            Label(requested && external.blackoutPhase == .blackedOut ? "Output blacked out" : "Restoring output",
                  systemImage: "eye.slash")
                .font(.footnote.bold())
                .accessibilityIdentifier("blackoutBadgeText")
            if external.blackoutPhase == .blackedOut {
                Button("Restore") { external.setBlackout(false) }
                    .font(.footnote)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Restore output")
                    .accessibilityIdentifier("blackoutRestore")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityValue(external.blackoutPhase.accessibilityValue)
        .accessibilityIdentifier("blackoutBadge")
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
