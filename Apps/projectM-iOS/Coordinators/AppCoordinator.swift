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
// * Transport (AUD-006): `transport` controls In-App Playback while it is the active source: play,
//   pause, stop playback, seek, next and previous track. The reference track is an order of one.
//   The existing Stop (back to the chooser) and Pause (freeze the picture) are unchanged.
// * Queue (AUD-003): imported tracks play in the user's queue (`audioLibrary.queue`), which the
//   transport follows as it is edited. The queue opens as a sheet from "Your Audio" (with Play
//   Queue) and from the transport while an imported track plays; edits never move playback.
// * Test signals (AUD-016): the chooser's Diagnostics section starts a generated reference tone as
//   In-App Playback, alone in its play order; nothing about the choice is stored.
// * Visual (VIS-001, ADR-0009): Settings chooses projectM (default) or the native Circular Spectrum.
//   The capture manager's analysis tap is on so the circular spectrum's band analysis can read the
//   normalized audio without touching projectM's reader. While the circular spectrum is shown,
//   projectM is paused (not torn down) and its preset controls are hidden; every pause/resume goes
//   through pauseActiveVisual()/resumeActiveVisual(). If the native visual cannot be created it
//   falls back to projectM with a notice (VIS-001-R16).
// * Tap tempo (SHOW-011): `tempo` owns the manual tempo and the estimate. Its analysis follows the
//   shown visual (own pipeline for projectM, the circular spectrum's pipeline otherwise) through
//   resumeActiveVisual()/pauseActiveVisual(), and PERF-011 through `presentation`.
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
import Metal
import UIKit
import VisualGenerators

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
    /// The queue sheet (AUD-003), over the chooser or the visualizer.
    var showQueue = false
    @ObservationIgnored private let inAppPlayback: InAppPlaybackSource
    /// Play, pause, stop playback, seek, next and previous for In-App Playback (AUD-006).
    let transport: PlaybackTransport
    /// AUD-007: the audio route indicator and its explanations.
    let routes = RouteCoordinator.makeDefault()
    private(set) var renderer: (any VisualizerRenderer)?
    private(set) var rendererError: String?
    /// Preset browsing and switching (T090, T091).
    let presets: PresetCoordinator
    /// Presets the user imported, their quarantine and their trial (PRE-012).
    let userPresets: UserPresetsCoordinator
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
    /// The native spectra (VIS-001 circular, VIS-002 linear), created the first time one is needed.
    private(set) var nativeVisual: NativeSpectrumHost?
    /// The native visual could not be created on this launch; projectM is shown instead (VIS-001-R16).
    private(set) var nativeVisualUnavailable = false
    /// The notice naming the chosen native visual (VIS-001-R16, VIS-002-R12).
    static func nativeVisualUnavailableMessage(for choice: VisualChoice) -> String {
        "\(choice.title) isn't available on this device. Showing projectM."
    }
    /// Tap tempo and the tempo estimate (SHOW-011).
    let tempo: TempoCoordinator

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
            try? FileManager.default.removeItem(at: PresetCollectionStore.defaultDirectory())   // PRE-007: UI tests start without collections
            try? FileManager.default.removeItem(at: UserPresetStore.defaultDirectory())         // PRE-012: and without imported presets
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
        // Latency stages (T062, T114); the analysis tap feeds the native visual's bands (VIS-001-R14).
        let manager = CaptureManager(sources: sources, signposts: DiagnosticsLog.pipeline,
                                     analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        self.manager = manager
        transport = PlaybackTransport(manager: manager, source: inAppPlayback)
        let lifecycle = LifecycleObserver()
        self.lifecycle = lifecycle
        var tempoClock: () -> UInt64 = { MonotonicClock.nowNanoseconds() }
        #if DEBUG
        // TapTempoUITests: `-uitestTapInterval <ms>` spaces every tap exactly (SHOW-011 research D6).
        if let step = defaults.string(forKey: "uitestTapInterval").flatMap(Double.init) {
            tempoClock = TempoCoordinator.syntheticClock(stepMilliseconds: step)
        }
        #endif
        tempo = TempoCoordinator(clock: tempoClock)
        // Feature 002: the library (12,941 presets) loads off the main thread (SC-101).
        presets = PresetCoordinator(store: FavoritesStore(defaults: defaults), settings: settings, loader: presetLoader,
                                    collections: PresetCollectionStore(directory: PresetCollectionStore.defaultDirectory()))
        userPresets = UserPresetsCoordinator.makeDefault()
        userPresets.connect(presets: presets, loader: presetLoader)   // PRE-012
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
        presentation.register(tempo)   // SHOW-011: the tempo analysis stops with the presentation
        presentation.onTransition = { report in
            DiagnosticsLog.presentationTransition(canPresent: report.canPresent, registered: report.registered,
                                                  activeBefore: report.activeBefore, activeAfter: report.activeAfter)
        }
        let lifecycleCoordinator = LifecycleCoordinator(manager: manager, visualization: self, presentation: presentation)
        self.lifecycleCoordinator = lifecycleCoordinator
        lifecycleForwarding = Task { @MainActor in
            for await event in lifecycle.events { await lifecycleCoordinator.handle(event) }
        }
        routes.context = { [weak self] in self?.routeContext }   // AUD-007
        routes.isActive = { [weak self] in self?.appIsActive ?? true }
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
            Task { @MainActor in
                if mode == .inAppPlayback { self.prepareReferenceTrack() }
                self.start(mode)
            }
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
        if mode == .inAppPlayback { prepareReferenceTrack() }   // the chooser row is the reference track (AUD-001-R21)
        start(mode)
    }

    /// The reference track, alone in its play order: it repeats (AUD-006-R14, R17).
    private func prepareReferenceTrack() {
        let reference = AudioLibraryCoordinator.referenceItem
        transport.prepare(order: ListPlayOrder([reference]), current: reference)
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
            guard screen == .chooser, await audioLibrary.playbackURL(for: track) != nil, screen == .chooser else { return }
            // The play order is the queue (AUD-003-R4): a track that is not queued joins at the end.
            let queue = audioLibrary.queue
            let id = track.id.uuidString
            if !queue.contains(id) { queue.addToEnd(id) }
            guard let item = queue.items.first(where: { $0.id == id }) else { return }
            playQueued(item)
        }
    }

    // MARK: - Queue (AUD-003)

    /// Opens the queue sheet; over the visualizer the controls stay while it is open.
    func openQueue() {
        showControls()
        showQueue = true
    }

    func closeQueue() {
        showQueue = false
        if screen == .visualizer { showControls() }
    }

    /// "Play Queue": the stored current track (or the first queued one) at 0:00 (AUD-003-R15).
    func playQueue() {
        guard let item = audioLibrary.queue.startItem else { return }
        playQueued(item)
    }

    /// Plays a queued track from the chooser, with the queue as the order.
    func playQueued(_ item: PlaybackItem) {
        guard screen == .chooser else { return }
        showQueue = false
        transport.prepare(order: audioLibrary.queue, current: item)
        start(.inAppPlayback)
    }

    /// The transport offers the queue while an imported track is the current item.
    var transportShowsQueue: Bool {
        guard case .file = transport.current?.track else { return false }
        return transport.isAvailable
    }

    // MARK: - Test signals (AUD-016)

    /// Plays a reference-tone fixture as In-App Playback (AUD-016-R14, R15, R17). Not stored.
    func playTestSignal(_ fixture: ReferenceToneFixture) {
        guard screen == .chooser else { return }
        let (order, item) = Self.testSignalPlayback(fixture)
        transport.prepare(order: order, current: item)
        start(.inAppPlayback)
    }

    /// A test signal alone in its order: it repeats, and Next and Previous track start it again.
    static func testSignalPlayback(_ fixture: ReferenceToneFixture) -> (order: ListPlayOrder, item: PlaybackItem) {
        let item = PlaybackItem.tone(fixture)
        return (ListPlayOrder([item]), item)
    }

    /// The test signal's name for the indicator while one plays as In-App Playback (AUD-016-R16).
    var testSignalName: String? { Self.signalName(mode: manager.activeMode, item: transport.current) }

    static func signalName(mode: AudioSourceMode?, item: PlaybackItem?) -> String? {
        guard mode == .inAppPlayback else { return nil }
        return item?.toneFixture?.name
    }

    // MARK: - Transport (AUD-006). Every use restarts the controls' hide delay (AUD-006-R25).

    func transportPlayPause() { showControls(); Task { await transport.togglePlayPause() } }
    func transportStop() { showControls(); Task { await transport.stop() } }
    func transportNext() { showControls(); Task { await transport.next() } }
    func transportPrevious() { showControls(); Task { await transport.previous() } }
    func transportSeek(to seconds: Double) { showControls(); transport.seek(to: seconds) }

    func removeImported(_ track: ImportedTrack) {
        Task { await audioLibrary.remove(track) }
    }

    /// Reads the audio library record off the launch path; the chooser fills in when it is ready.
    private func loadAudioLibrary() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await audioLibrary.load()
            #if DEBUG
            // ImportedAudioUITests and TransportUITests: `-uitestImportAudio <path>[|<path>…]` imports
            // those files, in that order, through the same code path as the Files picker's result.
            if let paths = defaults.string(forKey: "uitestImportAudio") {
                for path in paths.split(separator: "|") {
                    await audioLibrary.importPicked(.success([URL(fileURLWithPath: String(path))]))
                }
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
        resumeActiveVisual()
        showControls()
        updateIdleTimer()
        Task { await manager.select(mode) }
    }

    /// Stop (FR-007): stops the source and returns to the chooser.
    func stop() {
        hideTask?.cancel()
        pauseActiveVisual()
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
        startUserPresetTrials()
        selectInitialPresetIfReady()
    }

    /// PRE-012: imported presets are tried on the renderer's second engine before they can play.
    private func startUserPresetTrials() {
        let trial = renderer?.presetTrial.map { RendererPresetTrial(trial: $0) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await userPresets.rendererReady(trial: trial, presentedFrames: { [weak self] in self?.renderer?.presentedFrameCount ?? 0 })
            #if DEBUG
            // UserPresetsUITests: `-uitestImportPreset <path>` imports that file through the same
            // code path as the Files picker's result.
            if let path = defaults.string(forKey: "uitestImportPreset") {
                await userPresets.importPicked(.success(URL(fileURLWithPath: path)))
            }
            #endif
        }
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
                // PRE-012: the imported presets are read first (a preset that ended the last launch
                // is quarantined there), so the library never lists one that must not play.
                await userPresets.load()
                await userPresets.prepare(library: library, bundle: .main)
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
        nativeVisual?.reduceFlashing = settings.reduceFlashing   // VIS-001-R10
    }

    // MARK: - Visual choice (VIS-001)

    /// The native visual replaces projectM only when chosen, created and on the visualizer.
    static func nativeVisualShown(choice: VisualChoice, hostAvailable: Bool, onVisualizer: Bool) -> Bool {
        choice.isNative && hostAvailable && onVisualizer
    }

    var showsNativeVisual: Bool {
        Self.nativeVisualShown(choice: settings.visual, hostAvailable: nativeVisual != nil, onVisualizer: screen == .visualizer)
    }

    private var circularSpectrumBarCount: SpectrumBarCount {
        SpectrumBarCount(rawValue: settings.circularSpectrumBars) ?? .b64
    }

    /// The native spectrum the settings ask for (VIS-002-R11; circular for any other choice).
    private var nativeSpectrumStyle: NativeSpectrumStyle {
        settings.visual == .linearSpectrum
            ? .linear(settings.linearSpectrumOrientation, spacing: settings.linearSpectrumSpacing) : .circular
    }

    private func markNativeVisualUnavailable(_ error: any Error) {
        nativeVisualUnavailable = true
        rendererError = "\(settings.visual.title): \(error)"
        UIAccessibility.post(notification: .announcement, argument: Self.nativeVisualUnavailableMessage(for: settings.visual))
    }

    /// Creates the native spectrum the first time one is chosen; on failure, falls back to projectM
    /// with a notice (VIS-001-R16). The stored choice is kept.
    private func prepareNativeVisualIfNeeded() {
        guard settings.visual.isNative, nativeVisual == nil, !nativeVisualUnavailable else { return }
        do {
            var device = MTLCreateSystemDefaultDevice()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitestNativeVisualFailure") { device = nil }   // NativeVisualUITests
            #endif
            var forceGlowFailure = false
            #if DEBUG
            forceGlowFailure = ProcessInfo.processInfo.arguments.contains("-uitestGlowFailure")   // GlowUITests (FX-001-R13)
            #endif
            let host = try NativeSpectrumHost.make(device: device, reader: manager.analysisTap, style: nativeSpectrumStyle,
                                                   barCount: circularSpectrumBarCount, glow: settings.glowParameters,
                                                   forceGlowFailure: forceGlowFailure)
            host.reduceFlashing = settings.reduceFlashing
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            nativeVisual = host
        } catch {
            markNativeVisualUnavailable(error)
        }
    }

    /// Runs whichever visual is shown and keeps the other paused.
    private func resumeActiveVisual() {
        prepareNativeVisualIfNeeded()
        if showsNativeVisual {
            renderer?.pause()
            nativeVisual?.resume()
            if let reader = nativeVisual?.tempoReader { tempo.follow(reader) } else { tempo.stopAnalysis() }
        } else {
            nativeVisual?.pause()
            renderer?.resume()
            tempo.runOwnAnalysis(on: manager.analysisTap)
        }
    }

    /// Frame statistics of the shown visual (FR-048 overlay).
    var activeVisualMetrics: RenderMetrics {
        showsNativeVisual ? (nativeVisual?.metrics ?? .zero) : (renderer?.metrics ?? .zero)
    }

    private func pauseActiveVisual() {
        renderer?.pause()
        nativeVisual?.pause()
        tempo.stopAnalysis()   // SHOW-011: the estimate's analysis runs only while a visual runs
    }

    // MARK: - Tap tempo (SHOW-011). Every use restarts the controls' hide delay (SHOW-011-R17).

    func tapTempo() { showControls(); tempo.tap() }
    func resetTempo() { showControls(); tempo.reset() }

    /// Settings changed the visual, its bar count or the linear spectrum's options: switch without
    /// touching the audio source (VIS-001-R12, VIS-002-R12).
    func visualSettingsChanged() {
        nativeVisual?.barCount = circularSpectrumBarCount
        if settings.visual.isNative, let host = nativeVisual {
            do {
                try host.apply(style: nativeSpectrumStyle)
            } catch {
                host.pause()
                nativeVisual = nil   // the presentation registry holds it weakly
                markNativeVisualUnavailable(error)
            }
        }
        if visualizationState == .running {
            resumeActiveVisual()
        } else {
            prepareNativeVisualIfNeeded()
            pauseActiveVisual()
        }
    }

    // MARK: - Glow (FX-001)

    static let glowUnavailableMessage = "Glow isn't available on this device."

    /// The circular spectrum's glow could not be built; it renders without it (FX-001-R13).
    var glowUnavailable: Bool { nativeVisual?.glowUnavailable ?? false }

    /// A glow setting changed: the running visual uses it from the next frame (FX-001-R12).
    func glowSettingsChanged() {
        nativeVisual?.glow = settings.glowParameters
        if settings.glowEnabled && glowUnavailable {
            UIAccessibility.post(notification: .announcement, argument: Self.glowUnavailableMessage)
        }
    }

    /// The system Reduce Motion setting changed.
    func systemReduceMotionChanged(_ enabled: Bool) {
        settings.systemReduceMotion = enabled
        applyReduceFlashing()
    }

    func togglePause() {
        userPaused.toggle()
        userPaused ? pauseActiveVisual() : resumeActiveVisual()
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
            // ACC-002: the browser stays open while a flagged preset's warning waits for an answer.
            if !presets.purchaseRequested && presets.flashWarning == nil { showPresetBrowser = false }
        }
    }

    // MARK: - Purchase (feature 002 US2)

    func buyLibrary() { Task { await entitlements.purchase() } }
    func restorePurchases() { Task { await entitlements.restore() } }

    // MARK: - Controls and lifecycle

    /// AUD-007: what the route indicator shows (outputs for In-App Playback, inputs for
    /// Microphone); nil hides it.
    var routeContext: AudioRouteContext? {
        AudioRouteContext.make(mode: manager.activeMode, state: manager.state, isPausedByUser: manager.isPausedByUser)
    }

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
        guard !showPresetBrowser, !showSettings, !showQueue else { return }
        controlsVisible = false
    }

    /// Scene activity drives the idle timer (FR-084); rendering follows the lifecycle events.
    func sceneBecame(active: Bool) {
        appIsActive = active
        updateIdleTimer()
    }

    // MARK: - VisualizationControlling (LifecycleCoordinator)

    func suspendVisualization() {
        Task { await userPresets.abandonProving() }   // PRE-012-R18: leaving the screen is not the preset's fault
        pauseActiveVisual()
        updateIdleTimer()
    }

    func resumeVisualization() {
        resumeActiveVisual()
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
    /// The stored bytes of a playable imported preset (PRE-012); set by UserPresetsCoordinator.
    var userPresetData: ((String) async -> Data?)?
    private var archive: PresetArchive?

    /// Included presets load from their bundled file; pack presets from PresetArchive.bin
    /// (feature 002 research R-30).
    func load(_ preset: IndexedPreset) async throws {
        guard let renderer, let resources = Bundle.main.resourceURL else { throw CocoaError(.featureUnsupported) }
        let fileURL = resources.appendingPathComponent(preset.path)
        var playable = Preset(id: preset.id, name: preset.name, fileURL: fileURL, packID: preset.source, author: preset.author)
        if preset.source == PresetLibrary.userSource {
            // PRE-012: an imported preset loads from the user library's stored copy, which hands
            // out playable presets only (never one that is waiting or quarantined).
            guard let data = await userPresetData?(preset.id) else { throw CocoaError(.fileNoSuchFile) }
            playable.data = data
        } else if !preset.isIncluded {
            playable.data = try packArchive(resources).contents(of: preset.id)
        }
        try await renderer.setPreset(playable)
    }

    /// A built-in preset's bytes, read-only, for "Duplicate to My Presets" (PRE-015-R2): Included
    /// presets from their bundle file, pack presets from PresetArchive.bin.
    func bundledData(for preset: IndexedPreset) throws -> Data {
        guard preset.source != PresetLibrary.userSource, let resources = Bundle.main.resourceURL else { throw CocoaError(.featureUnsupported) }
        if preset.isIncluded { return try Data(contentsOf: resources.appendingPathComponent(preset.path)) }
        return try packArchive(resources).contents(of: preset.id)
    }

    /// SC-104: hands upcoming presets (with their archive data) to the renderer's warm-up.
    func prewarm(_ presets: [IndexedPreset]) {
        guard let renderer, let resources = Bundle.main.resourceURL else { return }
        // Imported presets are not warmed: the warm-up engine is outside their guarded path (PRE-012).
        let playable: [Preset] = presets.filter { $0.source != PresetLibrary.userSource }.compactMap { preset in
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
