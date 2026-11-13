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
// AUD-007: a route change's explanation shows above the source-and-state indicator for about 4 s.
import CaptureKit
import CaptureUI
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
            #endif
            if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
                Text("\(coordinator.sourceStarts)")
                    .font(.caption2)
                    .opacity(0.01)
                    .accessibilityIdentifier("sourceStarts")
                    .accessibilityValue("\(coordinator.sourceStarts)")
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
                         glowUnavailable: coordinator.glowUnavailable, photos: coordinator.photos)
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
            NativeVisualHost(view: camera.view)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Camera visualization")
                .accessibilityValue(coordinator.cameraState.accessibilityValue)   // CAM-001-R14
                .accessibilityIdentifier("cameraVisual")
        } else if coordinator.showsPhotoVisual, let photo = coordinator.photoVisual {
            NativeVisualHost(view: photo.view)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Photo visualization")
                .accessibilityValue(PhotoVisualHost.accessibilityValue(coordinator.photoState))   // MED-001-R15
                .accessibilityIdentifier("photoVisual")
        } else if coordinator.showsNativeVisual, let native = coordinator.nativeVisual {
            NativeVisualHost(view: native.view)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("\(native.style.title) visualization")
                .accessibilityValue(NativeSpectrumHost.accessibilityValue(style: native.style,
                                                                          glowEnabled: coordinator.settings.glowEnabled,
                                                                          glowUnavailable: coordinator.glowUnavailable))   // FX-001, VIS-002-R13
                .accessibilityIdentifier(native.style.accessibilityIdentifier)
        } else if let renderer = coordinator.renderer {
            RendererHost(renderer: renderer)
                .ignoresSafeArea()
                .accessibilityIdentifier("visualizer")
        }
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
        if let failure = coordinator.presets.failureMessage {
            Text(failure)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier("presetFailedBanner")
        }
    }
}

/// Hosts the native visual's UIView (VIS-001).
struct NativeVisualHost: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Hosts the renderer's UIView.
struct RendererHost: UIViewRepresentable {
    let renderer: any VisualizerRenderer
    func makeUIView(context: Context) -> UIView { renderer.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
