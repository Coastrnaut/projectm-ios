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
import Foundation
import Observation
import Rendering
import UIKit

@MainActor
@Observable
final class AppCoordinator {
    enum Screen: Equatable { case notice, chooser, visualizer }

    static let noticeKey = "notice.photosensitivityAcknowledged"
    static let lastPresetKey = "lastPresetID"
    static let controlsAutoHide: Duration = .seconds(5)

    private(set) var screen: Screen
    let manager: CaptureManager
    let microphone: MicrophoneSource
    var showMicrophoneExplainer = false
    private(set) var renderer: (any VisualizerRenderer)?
    private(set) var rendererError: String?
    private(set) var presets: [Preset] = []
    private(set) var currentPreset: Preset?
    private(set) var presetFailed = false
    private(set) var controlsVisible = true
    private(set) var userPaused = false
    private(set) var appIsActive = true
    /// Number of source starts (UI tests check that rotation does not restart capture).
    private(set) var sourceStarts = 0
    var showPresetBrowser = false
    var showSettings = false

    private let defaults: UserDefaults
    private var hideTask: Task<Void, Never>?
    private let lifecycle: LifecycleObserver
    private let lifecycleForwarding: Task<Void, Never>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.noticeKey)
        }
        screen = defaults.bool(forKey: Self.noticeKey) ? .chooser : .notice
        microphone = MicrophoneSource(backend: AVMicrophoneBackend())
        let manager = CaptureManager(sources: [
            ScreenCaptureSource.makeDefault(),
            microphone,
            InAppPlaybackSource(backend: AVInAppPlaybackBackend()),
        ])
        self.manager = manager
        let lifecycle = LifecycleObserver()
        self.lifecycle = lifecycle
        lifecycleForwarding = Task { @MainActor in
            for await event in lifecycle.events { await manager.handle(event) }
        }
        loadPresets()
    }

    deinit {
        lifecycleForwarding.cancel()
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
        if let preset = currentPreset ?? presets.first { load(preset) }
    }

    func togglePause() {
        userPaused.toggle()
        userPaused ? renderer?.pause() : renderer?.resume()
        updateIdleTimer()
        showControls()
    }

    func next() { step(by: 1) }
    func previous() { step(by: -1) }

    func random() {
        guard presets.count > 1 else { return }
        var candidate = presets.randomElement()
        while candidate == currentPreset { candidate = presets.randomElement() }
        if let candidate { load(candidate) }
        showControls()
    }

    func choose(_ preset: Preset) {
        showPresetBrowser = false
        load(preset)
        showControls()
    }

    private func step(by delta: Int) {
        guard !presets.isEmpty else { return }
        let index = currentPreset.flatMap { presets.firstIndex(of: $0) } ?? 0
        load(presets[(index + delta + presets.count) % presets.count])
        showControls()
    }

    /// FR-045: a failed load keeps the previous preset and shows "Preset could not be loaded".
    private func load(_ preset: Preset) {
        guard let renderer else {
            currentPreset = preset
            return
        }
        Task {
            do {
                try await renderer.setPreset(preset)
                currentPreset = preset
                presetFailed = false
                defaults.set(preset.id, forKey: Self.lastPresetKey)
            } catch {
                presetFailed = true
            }
        }
    }

    private func loadPresets() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Presets"),
              let catalog = try? PresetRepository(presetsFolder: folder).load() else { return }
        presets = catalog.presets
        let last = defaults.string(forKey: Self.lastPresetKey)
        currentPreset = presets.first { $0.id == last } ?? presets.first
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

    func sceneBecame(active: Bool) {
        appIsActive = active
        if screen == .visualizer, !userPaused {
            active ? renderer?.resume() : renderer?.pause()
        }
        updateIdleTimer()
    }

    var visualizationState: VisualizationState {
        guard screen == .visualizer else { return .notVisualizing }
        return userPaused ? .paused : .running
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
