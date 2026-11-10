// VisualizerView.swift — the full-screen visualization (task T084; FR-040, FR-041, FR-042, FR-083,
// FR-085, FR-086, FR-089). The renderer's view fills the window in portrait, landscape and iPad
// split view; a tap toggles the controls; the source-and-state indicator is always visible.
import CaptureUI
import Rendering
import SwiftUI

struct VisualizerView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let renderer = coordinator.renderer {
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
            if coordinator.settings.showsPerformanceOverlay, let renderer = coordinator.renderer {
                VStack { HStack { Spacer(); PerformanceOverlay(renderer: renderer, manager: coordinator.manager) }; Spacer() }
                    .padding(.top, 2)
                    .padding(.trailing, 8)
            }
            #if DEBUG
            if let fake = coordinator.fakeSource {
                VStack { HStack { FakeSourcePanel(fake: fake); Spacer() }; Spacer() }
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
            PresetBrowserView(presets: coordinator.presets) { coordinator.choose($0) }
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView(settings: coordinator.settings,
                         reduceFlashingAvailable: coordinator.renderer?.supportsReduceFlashing ?? true)
        }
        .onChange(of: coordinator.settings.reduceFlashing) { coordinator.applyReduceFlashing() }
        .onChange(of: coordinator.manager.state) { _, state in
            SourceStatusIndicator.announce(mode: coordinator.manager.activeMode, state: state)   // FR-070
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)) { _ in
            coordinator.systemReduceMotionChanged(UIAccessibility.isReduceMotionEnabled)
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
        if let failure = coordinator.presets.failureMessage {
            Text(failure)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier("presetFailedBanner")
        }
    }
}

/// Hosts the renderer's UIView.
struct RendererHost: UIViewRepresentable {
    let renderer: any VisualizerRenderer
    func makeUIView(context: Context) -> UIView { renderer.view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
