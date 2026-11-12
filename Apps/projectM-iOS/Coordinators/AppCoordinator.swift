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
// * PERF-011: while the app cannot present frames (background, device lock) the renderer's
//   presentation-bound resources are suspended through `presentation`: no frame loop, no window
//   surface, no preset warm-up. LifecycleCoordinator drives the registry.
// * Auto-lock (FR-084) follows IdleTimerPolicy.
// * Imported audio (AUD-001): the chooser's "Your Audio" section lists AudioLibraryCoordinator's
//   tracks. Tapping one selects that file on the In-App Playback source and starts it; the In-App
//   Playback row itself always plays the reference track.
import ANGLERendering
import AudioCore
import CaptureKit
import CaptureUI
import Diagnostics
import Foundation
import Observation
import PresentationLifecycle
import PresetLibrary
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
    /// The user's imported audio (AUD-001) and the Files picker for it.
    let audioLibrary: AudioLibraryCoordinator
    var showAudioImporter = false
    @ObservationIgnored private let inAppPlayback: InAppPlaybackSource
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
    /// The preset library finished loading (feature 002).
    private(set) var libraryReady = false
    /// The full-library purchase (feature 002 US2): StoreKit, or a fixed fake in UI tests.
    let entitlements: any EntitlementProviding
    var showSettings = false
    /// Performance overlay and Reduce flashing (T103).
    let settings: AppSettings

    private let defaults: UserDefaults
    #if DEBUG
    private(set) var fakeSource: UITestFakeSource?
    #endif
    private var hideTask: Task<Void, Never>?
    private let lifecycle: LifecycleObserver
    private var lifecycleForwarding: Task<Void, Never>?
    /// Presentation-bound resources (PERF-011): the renderer registers its own in prepareRenderer().
    @ObservationIgnored let presentation = PresentationResourceRegistry()
    @ObservationIgnored private var lifecycleCoordinator: LifecycleCoordinator!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.noticeKey)
            defaults.removeObject(forKey: FavoritesStore.favoritesKey)
            defaults.removeObject(forKey: FavoritesStore.lastPresetKey)
            AppSettings.allKeys.forEach(defaults.removeObject(forKey:))
        }
        settings = AppSettings(defaults: defaults, systemReduceMotion: UIAccessibility.isReduceMotionEnabled)
        screen = defaults.bool(forKey: Self.noticeKey) ? .chooser : .notice
        microphone = MicrophoneSource(backend: AVMicrophoneBackend())
        let inAppPlayback = InAppPlaybackSource(backend: AVInAppPlaybackBackend())
        self.inAppPlayback = inAppPlayback
        audioLibrary = AudioLibraryCoordinator.makeDefault()
        var sources: [any AudioSource] = [
            ScreenCaptureSource.makeDefault(),
            microphone,
            inAppPlayback,
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
        // Feature 002: the library (12,941 presets) loads off the main thread (SC-101).
        presets = PresetCoordinator(store: FavoritesStore(defaults: defaults), settings: settings, loader: presetLoader)
        #if DEBUG || PROJECTM_AUTOMATION
        entitlements = AutomationRunner.entitlementsOverride() ?? FakeEntitlements.fromLaunchArguments() ?? LibraryStore()
        #else
        entitlements = LibraryStore()
        #endif
        #if DEBUG
        fakeSource = fake
        #endif
        // Background/foreground/lock/unlock go through LifecycleCoordinator (T099): it suspends the
        // visualization and forwards to CaptureManager's per-adapter matrix.
        presentation.onTransition = { report in
            DiagnosticsLog.presentationTransition(canPresent: report.canPresent, registered: report.registered,
                                                  activeBefore: report.activeBefore, activeAfter: report.activeAfter)
        }
        let lifecycleCoordinator = LifecycleCoordinator(manager: manager, visualization: self, presentation: presentation)
        self.lifecycleCoordinator = lifecycleCoordinator
        lifecycleForwarding = Task { @MainActor in
            for await event in lifecycle.events { await lifecycleCoordinator.handle(event) }
        }
        loadLibrary()
        loadAudioLibrary()
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
        if mode == .inAppPlayback { inAppPlayback.track = .reference }   // the chooser row is the reference track (AUD-001-R21)
        start(mode)
    }

    // MARK: - Imported audio (AUD-001)

    /// "Import Audio…": opens the system Files picker (AUD-001-R1).
    func importAudio() {
        showAudioImporter = true
    }

    /// The Files picker returned.
    func audioPicked(_ result: Result<[URL], any Error>) {
        Task { await audioLibrary.importPicked(result) }
    }

    /// Plays an imported track as In-App Playback (AUD-001-R17, R18). The file is the library's
    /// own copy; if that copy is gone the source reports "In-App Playback failed" (AUD-001-R19).
    func play(_ track: ImportedTrack) {
        Task {
            guard screen == .chooser, let url = await audioLibrary.playbackURL(for: track), screen == .chooser else { return }
            inAppPlayback.track = .file(url)
            start(.inAppPlayback)
        }
    }

    func removeImported(_ track: ImportedTrack) {
        Task { await audioLibrary.remove(track) }
    }

    /// Reads the audio library record off the launch path; the chooser fills in when it is ready.
    private func loadAudioLibrary() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await audioLibrary.load()
            #if DEBUG
            // ImportedAudioUITests: `-uitestImportAudio <path>` imports that file through the same
            // code path as the Files picker's result.
            if let path = defaults.string(forKey: "uitestImportAudio") {
                await audioLibrary.importPicked(.success([URL(fileURLWithPath: path)]))
            }
            #endif
        }
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
        // PERF-011: a renderer created while the app cannot present starts suspended.
        renderer?.presentationResources.forEach(presentation.register)
        renderer?.attach(pcm: manager.normalizedOutput)
        applyReduceFlashing()
        if let textures = Bundle.main.resourceURL?.appendingPathComponent("PresetTextures") {
            renderer?.setTextureSearchPaths([textures])   // feature 002 T215
        }
        presetLoader.renderer = renderer
        selectInitialPresetIfReady()
    }

    /// Plays the last or first preset once both the renderer and the library are ready.
    private func selectInitialPresetIfReady() {
        guard renderer != nil, presets.current == nil, let preset = presets.initialPreset else { return }
        Task { await presets.select(preset) }
    }

    /// Loads the preset library off the main thread (feature 002 T217).
    private func loadLibrary() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                entitlements.onEntitlementChange = { [weak self] unlocked in
                    Task { @MainActor in await self?.presets.setUnlocked(unlocked) }
                }
                // The index is parsed off the main thread while StoreKit's local records are read
                // (SC-101); the price loads afterwards, since browsing does not need it.
                async let loaded = PresetLibrary.load(from: .main)
                await entitlements.start()
                let library = try await loaded
                presetLoader.library = library
                presets.attach(library)
                presets.onScopeChange { UIAccessibility.post(notification: .announcement, argument: $0) }   // FR-124
                await presets.setUnlocked(entitlements.isUnlocked)
                libraryReady = true
                Task { [weak self] in await self?.entitlements.loadProduct() }
                #if DEBUG || PROJECTM_AUTOMATION
                AutomationRunner.libraryReady(self)   // SC-101 (feature 002 T238)
                #endif
                selectInitialPresetIfReady()
            } catch {
                rendererError = "Preset library: \(error)"
            }
        }
    }

    /// FR-072: the renderer follows the setting (and Reduce Motion while the user has not chosen).
    func applyReduceFlashing() {
        renderer?.reduceFlashing = settings.reduceFlashing
    }

    /// The system Reduce Motion setting changed.
    func systemReduceMotionChanged(_ enabled: Bool) {
        settings.systemReduceMotion = enabled
        applyReduceFlashing()
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

    /// A preset chosen in the browser, from the list that becomes the scope (FR-116).
    func choose(_ preset: IndexedPreset, from scope: PresetScope) {
        showControls()
        Task {
            await presets.choose(preset, from: scope)
            if !presets.purchaseRequested { showPresetBrowser = false }
        }
    }

    // MARK: - Purchase (feature 002 US2)

    func buyLibrary() { Task { await entitlements.purchase() } }
    func restorePurchases() { Task { await entitlements.restore() } }

    // MARK: - Controls and lifecycle

    /// A tap on the visualization (FR-042).
    func toggleControls() {
        controlsVisible ? hideControls() : showControls()
    }

    /// Shows the controls and restarts the 5 s auto-hide. While VoiceOver runs they stay until the
    /// user hides them, so swiping through them never races the timer (FR-070, SC-012).
    func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        guard !UIAccessibility.isVoiceOverRunning else { return }
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
    var library: PresetLibrary?
    private var archive: PresetArchive?

    /// Included presets load from their bundled file; pack presets from PresetArchive.bin
    /// (feature 002 research R-30).
    func load(_ preset: IndexedPreset) async throws {
        guard let renderer, let resources = Bundle.main.resourceURL else { throw CocoaError(.featureUnsupported) }
        let fileURL = resources.appendingPathComponent(preset.path)
        var playable = Preset(id: preset.id, name: preset.name, fileURL: fileURL, packID: preset.source, author: preset.author)
        if !preset.isIncluded {
            playable.data = try packArchive(resources).contents(of: preset.id)
        }
        try await renderer.setPreset(playable)
    }

    /// SC-104: hands upcoming presets (with their archive data) to the renderer's warm-up.
    func prewarm(_ presets: [IndexedPreset]) {
        guard let renderer, let resources = Bundle.main.resourceURL else { return }
        let playable: [Preset] = presets.compactMap { preset in
            var item = Preset(id: preset.id, name: preset.name, fileURL: resources.appendingPathComponent(preset.path),
                              packID: preset.source, author: preset.author)
            if !preset.isIncluded {
                guard let data = try? packArchive(resources).contents(of: preset.id) else { return nil }
                item.data = data
            }
            return item
        }
        renderer.prewarm(playable)
    }

    private func packArchive(_ resources: URL) throws -> PresetArchive {
        if let archive { return archive }
        guard let library else { throw CocoaError(.featureUnsupported) }
        let opened = try PresetArchive(url: resources.appendingPathComponent("PresetArchive.bin"), packIds: library.archiveOrder)
        archive = opened
        return opened
    }
}
