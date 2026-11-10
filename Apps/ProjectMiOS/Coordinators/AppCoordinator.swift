// AppCoordinator.swift — the visualizer app's flow and state (tasks T082, T084-T086).
//
// * Launch (FR-081): the photosensitivity notice on first launch (FR-071, persisted under
//   `notice.photosensitivityAcknowledged`), then the source chooser. No source starts until the user
//   picks one (FR-002); Microphone shows its explainer first (FR-005).
// * Visualizer: CaptureManager's normalized output feeds the renderer (ANGLE on Metal, ADR-0003);
//   GLESRenderer is the fallback if an EGL context cannot be created.
// * Controls (FR-042): a tap toggles them; they hide after 5 s without interaction. The compact
//   source-and-state indicator stays visible.
// * Pause (FR-046, FR-085) stops rendering only; capture keeps running. Leaving the foreground
//   pauses rendering too (FR-050) and resumes it on return unless the user paused.
// * Auto-lock (FR-084) follows IdleTimerPolicy.
import ANGLERendering
import AudioCore
import CaptureKit
import CaptureUI
import Diagnostics
import Foundation
import Observation
import Rendering
import UIKit

@MainActor
@Observable
final class AppCoordinator: VisualizationControlling {
    enum Screen: Equatable { case notice, chooser, visualizer }

    static let noticeKey = "notice.photosensitivityAcknowledged"
    static let controlsAutoHide: Duration = .seconds(5)

    private(set) var screen: Screen
    let manager: CaptureManager
    let microphone: MicrophoneSource
    var showMicrophoneExplainer = false
    private(set) var renderer: (any VisualizerRenderer)?
    private(set) var rendererError: String?
    /// Preset browsing and switching (T090, T091).
    let presets: PresetCoordinator
    @ObservationIgnored private let presetLoader = RendererPresetLoader()
    private(set) var controlsVisible = true
    private(set) var userPaused = false
    private(set) var appIsActive = true
    /// Number of source starts (UI tests check that rotation does not restart capture).
    private(set) var sourceStarts = 0
    var showPresetBrowser = false
    var showSettings = false

    private let defaults: UserDefaults
    #if DEBUG
    private(set) var fakeSource: UITestFakeSource?
    #endif
    private var hideTask: Task<Void, Never>?
    private let lifecycle: LifecycleObserver
    private var lifecycleForwarding: Task<Void, Never>?
    @ObservationIgnored private var lifecycleCoordinator: LifecycleCoordinator!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.noticeKey)
            defaults.removeObject(forKey: FavoritesStore.favoritesKey)
            defaults.removeObject(forKey: FavoritesStore.lastPresetKey)
        }
        screen = defaults.bool(forKey: Self.noticeKey) ? .chooser : .notice
        microphone = MicrophoneSource(backend: AVMicrophoneBackend())
        var sources: [any AudioSource] = [
            ScreenCaptureSource.makeDefault(),
            microphone,
            InAppPlaybackSource(backend: AVInAppPlaybackBackend()),
        ]
        #if DEBUG
        // StatusUITests (T093): a scriptable fake replaces one mode's real source.
        let fake = UITestFakeSource.fromLaunchArguments()
        if let fake {
            sources.removeAll { $0.mode == fake.mode }
            sources.append(fake)
        }
        #endif
        let manager = CaptureManager(sources: sources, signposts: DiagnosticsLog.pipeline)   // latency stages (T062, T114)
        self.manager = manager
        let lifecycle = LifecycleObserver()
        self.lifecycle = lifecycle
        var bundled: [Preset] = []
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("Presets"),
           let catalog = try? PresetRepository(presetsFolder: folder).load() {
            bundled = catalog.presets
        }
        presets = PresetCoordinator(presets: bundled, store: FavoritesStore(defaults: defaults), loader: presetLoader)
        #if DEBUG
        fakeSource = fake
        #endif
        // Background/foreground/lock/unlock go through LifecycleCoordinator (T099): it suspends the
        // visualization and forwards to CaptureManager's per-adapter matrix.
        let lifecycleCoordinator = LifecycleCoordinator(manager: manager, visualization: self)
        self.lifecycleCoordinator = lifecycleCoordinator
        lifecycleForwarding = Task { @MainActor in
            for await event in lifecycle.events { await lifecycleCoordinator.handle(event) }
        }
        #if DEBUG || PROJECTM_AUTOMATION
        AutomationRunner.startIfRequested(self)   // Gate 4 device runs (PROJECTM_AUTORUN)
        #endif
        #if DEBUG
        // Debug builds only, for traces and test runs: `-autostart inAppPlayback` (or another
        // AudioSourceMode raw value) skips the notice and starts that source.
        if let raw = defaults.string(forKey: "autostart"), let mode = AudioSourceMode(rawValue: raw) {
            screen = .chooser
            Task { @MainActor in self.start(mode) }
        }
        #endif
    }

    isolated deinit {
        lifecycleForwarding?.cancel()
    }

    // MARK: - Launch flow

    func acknowledgeNotice() {
        defaults.set(true, forKey: Self.noticeKey)
        screen = .chooser
    }

    var availability: [AudioSourceMode: SourceAvailability] {
        Dictionary(uniqueKeysWithValues: AudioSourceMode.allCases.map { ($0, manager.availability(of: $0)) })
    }

    func select(_ mode: AudioSourceMode) {
        if mode == .microphone && microphone.needsExplainer {
            showMicrophoneExplainer = true
            return
        }
        start(mode)
    }

    func microphoneExplainerContinue() {
        showMicrophoneExplainer = false
        microphone.acknowledgeExplainer()
        start(.microphone)
    }

    private func start(_ mode: AudioSourceMode) {
        prepareRenderer()
        sourceStarts += 1
        screen = .visualizer
        lifecycleCoordinator.visualizationStarted()
        userPaused = false
        renderer?.resume()
        showControls()
        updateIdleTimer()
        Task { await manager.select(mode) }
    }

    /// Stop (FR-007): stops the source and returns to the chooser.
    func stop() {
        hideTask?.cancel()
        renderer?.pause()
        screen = .chooser
        lifecycleCoordinator.visualizationEnded()
        updateIdleTimer()
        Task { await manager.stop() }
    }

    func handle(_ action: BannerAction) {
        switch action {
        case .chooseSource: stop()
        case .openSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .restart:
            sourceStarts += 1
            Task { await manager.restart() }
        case .resume:
            Task { await manager.resume() }
        }
        showControls()
    }

    // MARK: - Visualization

    private func prepareRenderer() {
        guard renderer == nil else { return }
        do {
            renderer = try ANGLERenderer.make()
        } catch {
            rendererError = "ANGLE: \(error)"
            renderer = try? GLESRenderer.make()
        }
        renderer?.attach(pcm: manager.normalizedOutput)
        presetLoader.renderer = renderer
        if let preset = presets.current ?? presets.initialPreset {
            Task { await presets.select(preset) }
        }
    }

    func togglePause() {
        userPaused.toggle()
        userPaused ? renderer?.pause() : renderer?.resume()
        updateIdleTimer()
        showControls()
    }

    func next() { showControls(); Task { await presets.next() } }
    func previous() { showControls(); Task { await presets.previous() } }
    func random() { showControls(); Task { await presets.random() } }

    func choose(_ preset: Preset) {
        showPresetBrowser = false
        showControls()
        Task { await presets.select(preset) }
    }

    // MARK: - Controls and lifecycle

    /// A tap on the visualization (FR-042).
    func toggleControls() {
        controlsVisible ? hideControls() : showControls()
    }

    /// Shows the controls and restarts the 5 s auto-hide.
    func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.controlsAutoHide)
            guard !Task.isCancelled else { return }
            self?.hideControls()
        }
    }

    private func hideControls() {
        hideTask?.cancel()
        guard !showPresetBrowser, !showSettings else { return }
        controlsVisible = false
    }

    /// Scene activity drives the idle timer (FR-084); rendering follows the lifecycle events.
    func sceneBecame(active: Bool) {
        appIsActive = active
        updateIdleTimer()
    }

    // MARK: - VisualizationControlling (LifecycleCoordinator)

    func suspendVisualization() {
        renderer?.pause()
        updateIdleTimer()
    }

    func resumeVisualization() {
        renderer?.resume()
        updateIdleTimer()
    }

    /// VisualizationState (data-model): independent of the audio state.
    var visualizationState: VisualizationState {
        guard screen == .visualizer else { return .notVisualizing }
        if userPaused { return .paused }
        return appIsActive ? .running : .suspended
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            IdleTimerPolicy.suppressAutoLock(visualization: visualizationState, appIsActive: appIsActive)
    }

    /// FR-086 / FR-089: hide the status bar and home indicator with the controls, except while
    /// System/App Capture or Microphone runs, so the system's capture or microphone indicator stays visible.
    var hidesSystemOverlays: Bool {
        guard screen == .visualizer, !controlsVisible else { return false }
        return manager.activeMode == .inAppPlayback
    }
}

/// Loads presets into whichever renderer the app created (PresetLoading for PresetCoordinator).
@MainActor
final class RendererPresetLoader: PresetLoading {
    var renderer: (any VisualizerRenderer)?

    func load(_ preset: Preset) async throws {
        guard let renderer else { throw CocoaError(.featureUnsupported) }
        try await renderer.setPreset(preset)
    }
}
