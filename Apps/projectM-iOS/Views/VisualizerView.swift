// VisualizerView.swift — the full-screen visualization (task T084; FR-040, FR-041, FR-042, FR-083,
// FR-085, FR-086, FR-089). The renderer's view fills the window in portrait, landscape and iPad
// split view; a tap toggles the controls; the source-and-state indicator is always visible.
// VIS-001: when Settings chooses Circular Spectrum, its Metal view replaces the renderer's view
// (projectM is paused meanwhile); if it cannot be created a notice says projectM is shown instead.
import CaptureKit
import CaptureUI
import PresetLibrary
import Rendering
import SwiftUI

struct VisualizerView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if coordinator.showsNativeVisual, let native = coordinator.nativeVisual {
                NativeVisualHost(view: native.view)
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel("Circular Spectrum visualization")
                    .accessibilityIdentifier("circularSpectrum")
            } else if let renderer = coordinator.renderer {
                RendererHost(renderer: renderer)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("visualizer")
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
                banners
                Spacer()
                if coordinator.controlsVisible {
                    ControlsOverlay(coordinator: coordinator)
                        .transition(.opacity)
                } else {
                    SourceStatusIndicator(coordinator: coordinator)
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: coordinator.controlsVisible)
            if coordinator.settings.showsPerformanceOverlay, coordinator.renderer != nil || coordinator.showsNativeVisual {
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
            #endif
            if ProcessInfo.processInfo.arguments.contains("-uitestDiagnostics") {
                Text("\(coordinator.sourceStarts)")
                    .font(.caption2)
                    .opacity(0.01)
                    .accessibilityIdentifier("sourceStarts")
                    .accessibilityValue("\(coordinator.sourceStarts)")
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
        // AUD-003: the queue over the visualizer; edits never interrupt playback.
        .sheet(isPresented: $coordinator.showQueue, onDismiss: { coordinator.closeQueue() }) {
            NavigationStack {
                PlayQueueView(queue: coordinator.audioLibrary.queue, isPlaying: coordinator.transport.state == .playing,
                              onDone: { coordinator.closeQueue() })
            }
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView(settings: coordinator.settings,
                         reduceFlashingAvailable: coordinator.renderer?.supportsReduceFlashing ?? true,
                         nativeVisualUnavailable: coordinator.nativeVisualUnavailable)
        }
        .onChange(of: coordinator.settings.reduceFlashing) { coordinator.applyReduceFlashing() }
        .onChange(of: coordinator.settings.visual) { coordinator.visualSettingsChanged() }                 // VIS-001
        .onChange(of: coordinator.settings.circularSpectrumBars) { coordinator.visualSettingsChanged() }
        .onChange(of: coordinator.manager.state) { _, state in
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

    @ViewBuilder private var banners: some View {
        let manager = coordinator.manager
        if manager.stopReason != nil || manager.state == .noAudioReceived || manager.prolongedSilenceHint {
            StatusBanner(mode: manager.activeMode, state: manager.state, reason: manager.stopReason,
                         prolongedSilence: manager.prolongedSilenceHint) { coordinator.handle($0) }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        // VIS-001-R16: the chosen native visual could not be created.
        if coordinator.nativeVisualUnavailable && coordinator.settings.visual == .circularSpectrum {
            Text(AppCoordinator.nativeVisualUnavailableMessage)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier("nativeVisualUnavailable")
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
