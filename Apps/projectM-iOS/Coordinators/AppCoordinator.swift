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
// * Camera (CAM-001, ADR-0017): Settings' session-only "Camera" choice shows `CameraVisualHost` (the
//   camera layer under the circular spectrum layer). The host is created when Camera is chosen; the
//   camera runs only through resumeActiveVisual() while Camera is shown on the running visualizer,
//   and stops in pauseActiveVisual() (pause, Stop, background, lock) and when another visual is
//   chosen (the host is released). `cameraState` drives the non-blocking notice. While Camera is
//   shown the status bar is never hidden, so iOS's camera indicator stays visible (CAM-001-R10).
// * Camera privacy status (CAM-012): `cameraIndicator` (the "Camera on" badge) follows the feed
//   state only. `stopCamera()` stops the camera first (synchronously, in the host), then returns to
//   the visual chosen before Camera through the usual visual switch; the audio source is untouched.
// * Photo (MED-001): Settings' persisted "Photo" choice shows `PhotoVisualHost` (the imported photo
//   layer under the circular spectrum layer) with the same create/release and run rules as Camera,
//   without a sensor. `photos` (PhotoCoordinator) owns the stored copy; its changes set the layer's
//   content. A stored copy that cannot be loaded shows the photo notice.
// * Video (MED-002): Settings' persisted "Video" choice shows `VideoVisualHost` (the imported video
//   layer under the circular spectrum layer) with the same create/release and run rules as Photo.
//   `videos` (VideoCoordinator) owns the stored copy; its changes set the layer's content. A copy
//   that cannot be played shows the video notice. The video's soundtrack is never played (R16).
// * Memory pressure (PERF-006): `memoryPressure` (MemoryPressureCoordinator.shared) receives the system
//   memory warning. The app registers its cache steps there: the renderer's preset warm-up (its
//   context, and the warm-up itself as optional work), the preset archive's decompressed chunk, and
//   "idle native spectrum", a circular or linear spectrum host kept after the user chose another
//   visual (released; created again when a spectrum is chosen). The shown visual, the source and
//   the settings are never touched.
// * Text (MED-009): Settings' persisted "Text" choice shows `TextVisualHost` (the circular spectrum
//   with the text layer over it) with the same create/release and run rules as Photo. `texts`
//   (TextOverlayCoordinator) owns the saved message and style; its changes set the layer's spec.
// * Scene autosave (SCN-002): `sceneAutosave` restores the last committed scene before anything is
//   shown (before UI-test seeds), then debounces edits of `sceneInputs` into atomic saves; closing
//   Settings commits at once; restored bindings go to the native spectrum when it is created.
// * Session recovery (PERF-010): `recovery` decides at launch, before the OSC receiver exists, whether
//   the previous session ended abnormally. Then the stored OSC toggle is turned off (no listener without
//   consent), the committed scene is held instead of restored, the scene settings start fresh, and the
//   offer card asks Reopen or Start fresh. The camera is session only and never restarts by itself.
// * Show (SHOW-001): `show` (ShowCoordinator) owns the manual cue list; a step applies the cue's scene
//   through the Settings path (AppCoordinator+Show.swift), never touching the audio source.
// * Source switch (AUD-012): "Switch Source" in the controls lists `switchTargets` (the other
//   available modes); `switchSource(to:)` hands off through `CaptureManager.switchSource` without
//   leaving the visualizer or touching the visual. While `manager.switchingTo` is set the indicator
//   reads "Switching source…" and the route indicator is hidden; AUD-011's microphone flag follows
//   the manager's session callback at the switch point. Microphone with its explainer pending goes
//   back to the chooser, whose row shows the explainer (FR-005).
// * Guided first scene (UIX-001): `guide` offers the tutorial after the notice on a new install (not
//   while PERF-010's offer is pending); Play is AppCoordinator+Guide.swift.
import ANGLERendering
import CameraLayer
import ImageLayer
import VideoLayer
import TextLayer
import AudioCore
import CaptureKit
import Compositor
import CaptureUI
import Diagnostics
import Foundation
import Observation
import PresentationLifecycle
import PresetLibrary
import Rendering
import SceneFormat
import ShowStorage
import Metal
import UIKit
import VisualGenerators
import ParameterGraph
#if DEBUG
import VisualParameters
#endif

@MainActor
@Observable
final class AppCoordinator: VisualizationControlling, MemoryPressureResponder {
    enum Screen: Equatable { case notice, chooser, visualizer }

    static let noticeKey = "notice.photosensitivityAcknowledged"
    static let controlsAutoHide: Duration = .seconds(5)
    /// ACC-004: `-uitestKeepControls` keeps the controls up as VoiceOver does, so the accessibility
    /// audit (several seconds) never races the auto-hide. Always false in Release.
    #if DEBUG
    static let keepsControlsForAccessibilityTests = ProcessInfo.processInfo.arguments.contains("-uitestKeepControls")
    #else
    static let keepsControlsForAccessibilityTests = false
    #endif

    private(set) var screen: Screen {
        didSet { externalDisplay.visualizerActive(screen == .visualizer) }   // OUT-001: only the visualizer is shown externally
    }
    /// OUT-001: where the visualization is drawn (the device, or a connected external display).
    @ObservationIgnored let externalDisplay: ExternalDisplayCoordinator
    let manager: CaptureManager
    let microphone: MicrophoneSource
    var showMicrophoneExplainer = false
    /// The user's imported audio (AUD-001) and the Files picker for it.
    let audioLibrary: AudioLibraryCoordinator
    var showAudioImporter = false
    /// The queue sheet (AUD-003), over the chooser or the visualizer.
    var showQueue = false
    /// AUD-012: the "Switch Source" list over the visualizer.
    var showSourceSwitcher = false
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
    private(set) var controlsVisible = true {
        didSet {
            #if DEBUG
            // ACC-001-R9: the duration the controls transition was given (the view uses `motion`).
            if controlsVisible != oldValue { lastControlsTransitionSeconds = motion.controlsTransitionSeconds }
            #endif
        }
    }
    #if DEBUG
    /// ACC-001 (`motionProbe`): the last controls transition's duration; nil before the first.
    private(set) var lastControlsTransitionSeconds: Double?
    #endif
    private(set) var userPaused = false
    private(set) var appIsActive = true
    /// Number of source starts (UI tests check that rotation does not restart capture).
    private(set) var sourceStarts = 0
    var showPresetBrowser = false
    /// The preset library finished loading (feature 002).
    private(set) var libraryReady = false
    /// The full-library purchase (feature 002 US2): StoreKit, or a fixed fake in UI tests.
    let entitlements: any EntitlementProviding
    var showSettings = false {
        didSet {
            guard oldValue && !showSettings else { return }
            sceneHistory.endCoalescing()   // SCN-010-R4: closing Settings is a boundary
            sceneAutosave?.commitNow()     // SCN-002-R3
        }
    }
    /// SCN-010: undo and redo of scene edits (in memory only).
    @ObservationIgnored let sceneHistory = SceneHistoryCoordinator()
    /// SCN-002: the current scene's autosave (nil only if its folder cannot be made).
    @ObservationIgnored let sceneAutosave: SceneAutosaveCoordinator?
    /// PERF-010: abnormal-exit detection, the recovery offer and its consent rules.
    let recovery: SessionRecoveryCoordinator
    /// UIX-001: the guided first scene (stored state and whether it is shown).
    let guide: GuidedFirstSceneCoordinator
    /// Performance overlay and Reduce flashing (T103).
    let settings: AppSettings
    /// AUD-008: the analysis-only input trim (Settings → Audio Analysis).
    let inputTrim: InputTrimSetting
    /// AUD-009: the analysis-only channel selection (Settings → Analysis Channel).
    let channelSelection: ChannelSelectionSetting
    /// AUD-011: the analysis-only noise gate (Settings → Audio Analysis; microphone source only).
    let noiseGate: NoiseGateSetting
    /// AUD-013: the per-source visual delay (Settings → Visual Delay; analysis and projectM's feed).
    let latencyOffset: LatencyOffsetSetting
    /// The native spectra (VIS-001 circular, VIS-002 linear), created the first time one is needed.
    private(set) var nativeVisual: NativeSpectrumHost?
    /// The Camera visual (CAM-001), created when Camera is chosen and released when another visual is.
    private(set) var cameraVisual: CameraVisualHost?
    /// The camera feed's state while the Camera visual exists (`idle` otherwise; CAM-001-R5 to R8).
    private(set) var cameraState: CameraFeedState = .idle
    /// CAM-013: why the camera is interrupted or failed (nil otherwise), and whether a Retry waits.
    private(set) var cameraStopReason: CameraStopReason?
    private(set) var cameraRetryPending = false
    /// The imported photo (MED-001): the store, the pickers' results and the notice.
    let photos: PhotoCoordinator
    /// The Photo visual (MED-001), created when Photo is chosen and released when another visual is.
    private(set) var photoVisual: PhotoVisualHost?
    /// The photo layer's state while the Photo visual exists (`empty` otherwise).
    private(set) var photoState: ImageLayerState = .empty
    /// The imported video (MED-002): the store, the pickers' results and the notice.
    let videos: VideoCoordinator
    /// The Video visual (MED-002), created when Video is chosen and released when another visual is.
    private(set) var videoVisual: VideoVisualHost?
    /// The video layer's state while the Video visual exists (`empty` otherwise).
    private(set) var videoState: VideoLayerState = .empty
    /// The Text visual's message and style (MED-009): the editor's model and the saved value.
    let texts: TextOverlayCoordinator
    /// SHOW-001: the manual cue list.
    let show: ShowCoordinator
    /// SCN-012: the repair report before a show cue's scene or Reopen opens.
    let sceneRepair: SceneRepairCoordinator
    /// ACC-011: capture and recording status events (announcements and captions); owns ACC-004's announcer.
    let statusEvents = StatusEventRouter()
    /// ACC-004: user-caused state changes are announced through one rate-limited path.
    var announcer: AccessibilityAnnouncer { statusEvents.announcer }
    /// The Text visual (MED-009), created when Text is chosen and released when another visual is.
    private(set) var textVisual: TextVisualHost?
    /// The text layer's state while the Text visual exists (`empty` otherwise).
    private(set) var textState: TextLayerState = .empty
    /// The native visual could not be created on this launch; projectM is shown instead (VIS-001-R16).
    private(set) var nativeVisualUnavailable = false
    /// PERF-014 (AppCoordinator+RenderHealth.swift): bumped on every reported render health change.
    var renderHealthRevision = 0
    /// PERF-014-R11: VIS-001-R16 fallbacks, recorded as `visualUnavailable`.
    var visualCreationHealth = RenderHealth()
    /// PERF-014-R13: the counts last logged per visual kind.
    @ObservationIgnored var loggedRenderCounts: [String: [Int]] = [:]
    #if DEBUG
    /// PERF-014-R15: `clearRenderFaults()` was called (new visuals are not armed any more).
    @ObservationIgnored var renderFaultsCleared = false
    #endif
    /// The notice naming the chosen native visual (VIS-001-R16, VIS-002-R12).
    static func nativeVisualUnavailableMessage(for choice: VisualChoice) -> String {
        "\(choice.title) isn't available on this device. Showing projectM."
    }
    /// AUD-008-R1, R11: the analysis tap seen through the input trim. A new reader per consumer (the tap
    /// has one consumer at a time); every native host and the tempo's own analysis use it, so bands,
    /// the oscilloscope, MOD-002 bindings and tempo detection follow the trim. projectM reads
    /// `manager.normalizedOutput`, which the trim never touches.
    /// AUD-009-R5 (contract C4): the channel selection sits inside the trim (tap → selection → trim).
    /// AUD-011-R1 (contract C5): the noise gate sits after the trim (tap → selection → trim → gate).
    /// AUD-013-R2 (contract C4): the visual delay is outermost (tap → selection → trim → gate → delay),
    /// so every analysis consumer is shifted by the same amount.
    var trimmedAnalysisTap: (any NormalizedPCMReader)? {
        let gated: (any NormalizedPCMReader)? = noiseGate.gated(inputTrim.trimmed(channelSelection.selected(manager.analysisTap)))
        return latencyOffset.analysisDelayed(gated)
    }

    /// Tap tempo and the tempo estimate (SHOW-011).
    let tempo: TempoCoordinator
    /// The OSC receiver (OSC-001): off by default, listens only while enabled and active.
    let osc: OSCReceiverCoordinator
    /// REC-001: Save Frame (the shown visual's next frame, to the Files exporter).
    @ObservationIgnored private(set) lazy var frameCapture = FrameCaptureCoordinator { [weak self] () -> FrameCaptureCoordinator.Context in
        guard let self else { return FrameCaptureCoordinator.Context(source: nil, outputLive: false, paused: false) }
        return FrameCaptureCoordinator.Context(source: self.activeFrameCaptureSource,
                                               outputLive: self.externalDisplay.blackoutPhase == .live, paused: self.userPaused)
    }
    /// REC-012: Share… for an offered frame or recording; created with the app so its sweep of
    /// leftover share copies runs at launch (REC-012-R6).
    @ObservationIgnored let captureShare = CaptureShareCoordinator()
    /// REC-003: Record (the shown visual's frames into a video file, handed to the file mover).
    @ObservationIgnored private(set) lazy var videoRecording = VideoRecordingCoordinator { [weak self] () -> VideoRecordingCoordinator.Context in
        guard let self else { return VideoRecordingCoordinator.Context(source: nil, visualShown: false, outputLive: false, paused: false) }
        return VideoRecordingCoordinator.Context(source: self.activeVideoRecordingSource, visualShown: self.screen == .visualizer,
                                                 outputLive: self.externalDisplay.blackoutPhase == .live, paused: self.userPaused)
    }

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
    /// PERF-006: the one receiver of memory warnings; the app's recovery steps are registered there.
    @ObservationIgnored let memoryPressure: MemoryPressureCoordinator

    init(defaults: UserDefaults = .standard, externalDisplay: ExternalDisplayCoordinator? = nil,
         memoryPressure: MemoryPressureCoordinator? = nil) {
        self.defaults = defaults
        self.memoryPressure = memoryPressure ?? .shared
        self.externalDisplay = externalDisplay ?? .shared
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") {
            defaults.removeObject(forKey: Self.noticeKey)
            defaults.removeObject(forKey: FavoritesStore.favoritesKey)
            defaults.removeObject(forKey: FavoritesStore.lastPresetKey)
            AppSettings.allKeys.forEach(defaults.removeObject(forKey:))
            defaults.removeObject(forKey: InputTrimSetting.decibelsKey)   // AUD-008: 0 dB
            defaults.removeObject(forKey: ChannelSelectionSetting.modeKey)   // AUD-009: Mix
            defaults.removeObject(forKey: NoiseGateSetting.enabledKey)   // AUD-011: off
            defaults.removeObject(forKey: NoiseGateSetting.thresholdKey)   // AUD-011: −50 dBFS
            LatencyOffsetSetting.allKeys.forEach(defaults.removeObject(forKey:))   // AUD-013: 0 ms
            try? FileManager.default.removeItem(at: PresetCollectionStore.defaultDirectory())   // PRE-007: UI tests start without collections
            try? FileManager.default.removeItem(at: UserPresetStore.defaultDirectory())         // PRE-012: and without imported presets
            if let photos = try? PhotoStore.defaultDirectory() { try? FileManager.default.removeItem(at: photos) }   // MED-001: no photo
            if let videos = try? VideoStore.defaultDirectory() { try? FileManager.default.removeItem(at: videos) }   // MED-002: no video
            if let scenes = try? SceneAutosaveStore.defaultDirectory() { try? FileManager.default.removeItem(at: scenes) }   // SCN-002: no scene
            SessionRecoveryCoordinator.reset(defaults)   // PERF-010: no previous session
            GuidedFirstSceneCoordinator.reset(defaults)  // UIX-001: never offered
            if let shows = try? ShowStore.defaultDirectory() { try? FileManager.default.removeItem(at: shows) }   // SHOW-001: no show
        }
        settings = AppSettings(defaults: defaults, systemReduceMotion: Self.currentSystemReduceMotion())
        inputTrim = InputTrimSetting(defaults: defaults)
        channelSelection = ChannelSelectionSetting(defaults: defaults)
        noiseGate = NoiseGateSetting(defaults: defaults)
        latencyOffset = LatencyOffsetSetting(defaults: defaults)
        self.externalDisplay.reduceFlashing = settings.reduceFlashing   // OUT-010-R6
        // PERF-010 (contract C1): decide before the OSC receiver exists, so an abnormal exit never
        // reopens the listener; a pending offer holds the scene instead of restoring it.
        let recovery = SessionRecoveryCoordinator(defaults: defaults, suppressed: SessionRecoveryCoordinator.harnessSuppresses())
        let holdsScene = recovery.prepare(settings: settings)
        self.recovery = recovery
        let guide = GuidedFirstSceneCoordinator(defaults: defaults, suppressed: GuidedFirstScenePolicy.harnessSuppresses())
        self.guide = guide
        #if DEBUG
        osc = OSCReceiverCoordinator(settings: settings, receiver: UITestOSCFailure.receiverIfRequested() ?? .system())
        #else
        osc = OSCReceiverCoordinator(settings: settings)
        #endif
        photos = PhotoCoordinator.makeDefault(defaults: defaults)
        videos = VideoCoordinator.makeDefault(defaults: defaults)
        texts = TextOverlayCoordinator.makeDefault(defaults: defaults)
        // SCN-002: the last committed scene wins over the settings (research SCN-002-D2).
        let sceneAutosave = SceneAutosaveCoordinator.makeDefault(defaults: defaults)
        let stored = StoredMediaAvailability(photos: Set([photos.photo?.id.uuidString].compactMap { $0 }),
                                             videos: Set([videos.video?.id.uuidString].compactMap { $0 }))
        if holdsScene {
            recovery.hold(recovery.decision.isCrashLoop ? nil : sceneAutosave?.holdCommittedScene(assets: stored))
        } else if let values = sceneAutosave?.restore(assets: stored) {
            SceneAutosaveCapture.apply(values, to: settings)
            if let text = values.text { texts.spec = text }
        }
        self.sceneAutosave = sceneAutosave
        show = ShowCoordinator.makeDefault()   // SHOW-001
        sceneRepair = SceneRepairCoordinator(registry: try? SceneArchiveService.appRegistry())   // SCN-012
        #if DEBUG
        UITestPhotoFixture.seedIfRequested(photos)   // MED-001: PhotoLayerUITests (pickers cannot be automated)
        UITestVideoFixture.seedIfRequested(videos)   // MED-002: VideoLayerUITests
        UITestTextFixture.seedIfRequested(texts)     // MED-009: TextOverlayUITests
        #endif
        let initialScreen: Screen = defaults.bool(forKey: Self.noticeKey) ? .chooser : .notice
        screen = initialScreen
        // UIX-001-R1: a pending tutorial is offered again (not over PERF-010's offer).
        if initialScreen == .chooser { guide.presentAtLaunchIfDue(recoveryPending: recovery.offer == .pending) }
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
        let fakes = UITestFakeSource.fromLaunchArguments()   // AUD-012: one or more modes
        for fake in fakes {
            sources.removeAll { $0.mode == fake.mode }
            sources.append(fake)
        }
        #endif
        // Latency stages (T062, T114); the analysis tap feeds the native visual's bands (VIS-001-R14).
        let manager = CaptureManager(sources: sources, signposts: DiagnosticsLog.pipeline,
                                     analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        self.manager = manager
        manager.backgroundConfiguration = Self.backgroundConfiguration(infoDictionary: Bundle.main.infoDictionary)   // AUD-015-R3
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
        #if DEBUG
        // TempoConfidenceUITests: `-uitestTempoEstimate <bpm>:<confidence>[:<polls>:<confidence2>]` (ANL-006 D7).
        if let script = defaults.string(forKey: "uitestTempoEstimate").flatMap(TempoCoordinator.estimateScript) {
            tempo.estimateScript = script
        }
        #endif
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
        fakeSource = fakes.first
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
        photos.onPhotoChange = { [weak self] (stored: StoredPhoto?) in self?.photoVisual?.content = Self.photoContent(stored) }
        videos.onVideoChange = { [weak self] (stored: StoredVideo?) in self?.videoVisual?.content = Self.videoContent(stored) }
        texts.onSpecChange = { [weak self] (spec: TextOverlaySpec) in self?.textVisual?.spec = spec }   // MED-009
        routes.context = { [weak self] in self?.routeContext }   // AUD-007
        // AUD-012-R12: the noise gate's microphone flag changes when a session (or a switch) begins.
        manager.onSessionMode = { [weak self] (mode: AudioSourceMode) in
            self?.noiseGate.control.isMicrophoneSource = mode == .microphone
            self?.latencyOffset.activeMode = mode   // AUD-013-R8: the new session's delay
        }
        routes.isActive = { [weak self] in self?.appIsActive ?? true }
        self.memoryPressure.register(presetLoader)   // PERF-006-R11: the archive's decompressed chunk
        self.memoryPressure.register(self)           // PERF-006-R12: an idle native spectrum
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(UITestMemoryPanel.argument) {
            SharedTexturePool.relaxIdleEvictionForUITests()   // MemoryPressureUITests (research PERF-006-D7)
        }
        #endif
        sceneAutosave?.inputs = { [unowned self] () -> SceneInputs in self.sceneInputs }
        sceneAutosave?.liveBindings = { [weak self] () -> [AudioFeatureBinding]? in self?.nativeVisual?.bindings }
        sceneAutosave?.startTracking()
        // PERF-010-R9: in a crash loop the scene that crashed is replaced by the fresh one at once.
        if recovery.decision.isCrashLoop { sceneAutosave?.commitFreshScene() }
        recovery.startObservingLifecycle()
        connectShow()   // SHOW-001
        connectSceneHistory()   // SCN-010: starts from the restored (or fresh) scene
        #if DEBUG
        UITestShowFixture.seedIfRequested(self)   // SHOW-001: ShowCueUITests
        #endif
        connectStatusEvents()   // ACC-011
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
        guide.noticeAcknowledged(recoveryPending: recovery.offer == .pending)   // UIX-001-R1
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
        noiseGate.control.isMicrophoneSource = mode == .microphone   // AUD-011-R3
        latencyOffset.activeMode = mode   // AUD-013-R8
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

    /// AUD-012-R1: the modes "Switch Source" offers: available on this device, not the current one.
    var switchTargets: [AudioSourceMode] { Self.switchTargets(current: manager.activeMode, availability: availability) }

    static func switchTargets(current: AudioSourceMode?, availability: [AudioSourceMode: SourceAvailability]) -> [AudioSourceMode] {
        AudioSourceMode.allCases.filter { (mode: AudioSourceMode) -> Bool in
            mode != current && availability[mode] == .available
        }
    }

    /// AUD-012 (contract C5): switches the source in place with the bounded handoff.
    func switchSource(to mode: AudioSourceMode) {
        showSourceSwitcher = false
        guard screen == .visualizer, switchTargets.contains(mode) else { return }
        if mode == .microphone && microphone.needsExplainer {   // AUD-012-R13: FR-005 first
            stop()
            select(.microphone)
            return
        }
        if mode == .inAppPlayback { prepareReferenceTrack() }   // as the chooser row (AUD-001-R21)
        sourceStarts += 1
        showControls()
        Task { await manager.switchSource(to: mode) }
    }

    /// The indicator's text (FR-042) with AUD-012's switching label.
    var sourceStatusText: String {
        SourceStatusIndicator.text(mode: manager.activeMode, state: manager.state, signal: testSignalName,
                                   switching: manager.switchingTo != nil)
    }

    /// Stop (FR-007): stops the source and returns to the chooser.
    func stop() {
        noiseGate.control.isMicrophoneSource = false   // AUD-011-R3
        latencyOffset.activeMode = nil   // AUD-013-R8
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
            PermissionCatalog.openSettings()   // FILE-013-R4: the one opener
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
        if let angle = renderer as? ANGLERenderer {   // PERF-014: projectM's render health
            angle.onRenderHealthChange = observeRenderHealth(of: "projectM")
            #if DEBUG
            angle.faultInjection = armedRenderFaults
            #endif
        }
        // PERF-011: a renderer created while the app cannot present starts suspended.
        renderer?.presentationResources.forEach(presentation.register)
        renderer?.memoryPressureResponders.forEach(memoryPressure.register)   // PERF-006-R9, R10
        renderer?.attach(pcm: latencyOffset.rendererDelayed(manager.normalizedOutput))   // AUD-013-R2
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
                #if DEBUG
                UITestCollectionFixture.seedIfRequested(presets)   // PresetCollectionsUITests
                #endif
                presets.onScopeChange { UIAccessibility.post(notification: .announcement, argument: $0) }   // FR-124
                presets.announceFavorite = { [weak self] (text: String) in self?.announcer.announce(text, kind: .favorite) }   // ACC-004
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
        cameraVisual?.reduceFlashing = settings.reduceFlashing   // CAM-001: the composite flash guard
        photoVisual?.reduceFlashing = settings.reduceFlashing    // MED-001
        externalDisplay.reduceFlashing = settings.reduceFlashing // OUT-010-R6: the restore fade's length
        videoVisual?.reduceFlashing = settings.reduceFlashing    // MED-002
        textVisual?.reduceFlashing = settings.reduceFlashing     // MED-009
    }

    // MARK: - Visual choice (VIS-001)

    /// The native visual replaces projectM only when chosen, created and on the visualizer.
    static func nativeVisualShown(choice: VisualChoice, hostAvailable: Bool, onVisualizer: Bool) -> Bool {
        choice.isNative && hostAvailable && onVisualizer
    }

    var showsNativeVisual: Bool {
        Self.nativeVisualShown(choice: settings.visual, hostAvailable: nativeVisual != nil, onVisualizer: screen == .visualizer)
    }

    /// The Camera visual replaces projectM only when chosen, created and on the visualizer (CAM-001).
    var showsCameraVisual: Bool {
        settings.visual.usesCamera && cameraVisual != nil && screen == .visualizer
    }

    /// The Photo visual replaces projectM only when chosen, created and on the visualizer (MED-001).
    var showsPhotoVisual: Bool {
        settings.visual.usesPhoto && photoVisual != nil && screen == .visualizer
    }

    /// The Video visual replaces projectM only when chosen, created and on the visualizer (MED-002).
    var showsVideoVisual: Bool {
        settings.visual.usesVideo && videoVisual != nil && screen == .visualizer
    }

    /// The Text visual replaces projectM only when chosen, created and on the visualizer (MED-009).
    var showsTextVisual: Bool {
        settings.visual.usesText && textVisual != nil && screen == .visualizer
    }

    /// A native spectrum, the Camera, Photo, Video or Text visual is shown instead of projectM (preset controls hidden).
    var showsAlternateVisual: Bool {
        showsNativeVisual || showsCameraVisual || showsPhotoVisual || showsVideoVisual || showsTextVisual
    }

    private var circularSpectrumBarCount: SpectrumBarCount {
        SpectrumBarCount(rawValue: settings.circularSpectrumBars) ?? .b64
    }

    /// The native visual the settings ask for (VIS-002-R11, VIS-003-R10; circular for any other choice).
    private var nativeSpectrumStyle: NativeSpectrumStyle {
        switch settings.visual {
        case .linearSpectrum: .linear(settings.linearSpectrumOrientation, spacing: settings.linearSpectrumSpacing)
        case .oscilloscope: .oscilloscope(line: settings.oscilloscopeLine, windowMilliseconds: settings.oscilloscopeWindowMilliseconds)
        default: .circular
        }
    }

    private func markNativeVisualUnavailable(_ error: any Error) {
        nativeVisualUnavailable = true
        rendererError = "\(settings.visual.title): \(error)"
        recordVisualUnavailable()   // PERF-014-R11
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
            let host = try NativeSpectrumHost.make(device: device, reader: trimmedAnalysisTap, style: nativeSpectrumStyle,
                                                   barCount: circularSpectrumBarCount, glow: settings.glowParameters,
                                                   forceGlowFailure: forceGlowFailure)
            host.reduceFlashing = settings.reduceFlashing
            host.smoothing = settings.spectrumSmoothing   // ANL-003
            for binding in sceneAutosave?.bindings ?? [] { try? host.bind(binding) }   // SCN-002: restored bindings
            #if DEBUG
            bindGlowToLevelIfRequested(host)   // MOD-002: AudioFeatureBindingUITests
            #endif
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            nativeVisual = host
        } catch {
            markNativeVisualUnavailable(error)
        }
    }

    /// Creates the Camera visual when Camera is chosen (CAM-001-R1); on failure, falls back to
    /// projectM with the same notice as the native visuals (spec Edge Cases). The camera does not
    /// start here: only resumeActiveVisual() starts it.
    private func prepareCameraVisualIfNeeded() {
        guard settings.visual.usesCamera, cameraVisual == nil, !nativeVisualUnavailable else { return }
        do {
            var device = MTLCreateSystemDefaultDevice()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitestNativeVisualFailure") { device = nil }
            #endif
            let host = try CameraVisualHost.make(device: device, reader: trimmedAnalysisTap, barCount: circularSpectrumBarCount,
                                                 position: settings.cameraPosition, mirrored: settings.cameraMirrored,   // CAM-002
                                                 crop: settings.cameraCrop)   // CAM-007
            host.reduceFlashing = settings.reduceFlashing
            host.onRenderHealthChange = observeRenderHealth(of: "camera")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onFeedStateChange = { [weak self] state in self?.cameraStateChanged(state) }
            host.onRecoveryChange = { [weak self, weak host] () -> Void in   // CAM-013
                self?.cameraRetryPending = host?.retryPending ?? false
            }
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            cameraVisual = host
        } catch {
            markNativeVisualUnavailable(error)
        }
    }

    /// The photo layer's content for a stored photo.
    static func photoContent(_ stored: StoredPhoto?) -> ImageLayerContent {
        stored.map { .file($0.url) } ?? .none
    }

    /// Creates the Photo visual when Photo is chosen (MED-001-R1); on failure, falls back to projectM
    /// with the same notice as the native visuals. Its content is the stored photo.
    private func preparePhotoVisualIfNeeded() {
        guard settings.visual.usesPhoto, photoVisual == nil, !nativeVisualUnavailable else { return }
        do {
            var device = MTLCreateSystemDefaultDevice()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitestNativeVisualFailure") { device = nil }
            #endif
            let host = try PhotoVisualHost.make(device: device, reader: trimmedAnalysisTap, barCount: circularSpectrumBarCount)
            host.reduceFlashing = settings.reduceFlashing
            host.onRenderHealthChange = observeRenderHealth(of: "photo")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onImageStateChange = { [weak self] (state: ImageLayerState) in self?.photoStateChanged(state) }
            host.content = Self.photoContent(photos.photo)
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            photoVisual = host
        } catch {
            markNativeVisualUnavailable(error)
        }
    }

    /// Drops the Photo visual (another visual was chosen); the stored photo stays.
    private func releasePhotoVisual() {
        guard let host = photoVisual else { return }
        host.pause()
        photoVisual = nil   // the presentation registry holds it weakly
        photoState = .empty
    }

    private func photoStateChanged(_ state: ImageLayerState) {
        photoState = state
        switch state {
        case .ready(let width, let height): photos.loadedSize = (width, height)
        case .failed: photos.storedCopyFailed()   // MED-001-R11, R14
        case .empty, .loading: photos.loadedSize = nil
        }
    }

    /// The video layer's content for a stored video.
    static func videoContent(_ stored: StoredVideo?) -> VideoLayerContent {
        stored.map { .file($0.url) } ?? .none
    }

    /// Creates the Video visual when Video is chosen (MED-002-R1); on failure, falls back to projectM
    /// with the same notice as the native visuals. Its content is the stored video.
    private func prepareVideoVisualIfNeeded() {
        guard settings.visual.usesVideo, videoVisual == nil, !nativeVisualUnavailable else { return }
        do {
            var device = MTLCreateSystemDefaultDevice()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitestNativeVisualFailure") { device = nil }
            #endif
            let host = try VideoVisualHost.make(device: device, reader: trimmedAnalysisTap, barCount: circularSpectrumBarCount)
            host.reduceFlashing = settings.reduceFlashing
            host.onRenderHealthChange = observeRenderHealth(of: "video")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onVideoStateChange = { [weak self] (state: VideoLayerState) in self?.videoStateChanged(state) }
            host.content = Self.videoContent(videos.video)
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            videoVisual = host
        } catch {
            markNativeVisualUnavailable(error)
        }
    }

    /// Drops the Video visual (another visual was chosen): its decoder stops; the stored video stays.
    private func releaseVideoVisual() {
        guard let host = videoVisual else { return }
        host.pause()
        host.content = .none
        videoVisual = nil   // the presentation registry holds it weakly
        videoState = .empty
    }

    private func videoStateChanged(_ state: VideoLayerState) {
        videoState = state
        switch state {
        case .playing(let width, let height): videos.playingSize = (width, height)
        case .failed: videos.storedCopyFailed()   // MED-002-R14, R18
        case .empty, .loading: videos.playingSize = nil
        }
    }

    /// Creates the Text visual when Text is chosen (MED-009-R1); on failure, falls back to projectM
    /// with the same notice as the native visuals. It draws the saved spec.
    private func prepareTextVisualIfNeeded() {
        guard settings.visual.usesText, textVisual == nil, !nativeVisualUnavailable else { return }
        do {
            var device = MTLCreateSystemDefaultDevice()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitestNativeVisualFailure") { device = nil }
            #endif
            let host = try TextVisualHost.make(device: device, reader: trimmedAnalysisTap, barCount: circularSpectrumBarCount)
            host.reduceFlashing = settings.reduceFlashing
            host.onRenderHealthChange = observeRenderHealth(of: "text")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onTextStateChange = { [weak self] (state: TextLayerState) in self?.textState = state }
            host.spec = texts.spec
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            textVisual = host
        } catch {
            markNativeVisualUnavailable(error)
        }
    }

    /// Drops the Text visual (another visual was chosen); the saved text stays.
    private func releaseTextVisual() {
        guard let host = textVisual else { return }
        host.pause()
        textVisual = nil   // the presentation registry holds it weakly
        textState = .empty
    }

    /// Stops the camera and drops the Camera visual (another visual was chosen; CAM-001-R7, R9).
    private func releaseCameraVisual() {
        guard let host = cameraVisual else { return }
        host.pause()
        cameraVisual = nil   // the presentation registry holds it weakly
        cameraState = .idle
        cameraStopReason = nil   // CAM-013
        cameraRetryPending = false
    }

    /// CAM-012-R1, R2: the in-app camera badge, from the feed state only (hidden off the visualizer).
    var cameraIndicator: CameraIndicator {
        showsCameraVisual ? CameraIndicator(state: cameraState, position: settings.cameraPosition) : .hidden   // CAM-002-R8
    }

    /// CAM-012-R4 to R8: the user's Stop camera. The camera is stopped before anything else (the
    /// feed reports idle, the badge goes), then the visual chosen before Camera is shown and runs;
    /// the Camera visual is released. The audio source is not touched, nothing new is stored, and
    /// only choosing Camera again starts the camera.
    func stopCamera() {
        guard let host = cameraVisual else { return }
        host.stopCamera()
        statusEvents.post(StatusEventCatalog.camera(.idle))   // ACC-011 X18
        settings.visual = settings.visualBeforeCamera
        visualSettingsChanged()   // releases the Camera visual, resumes the fallback (VIS-001-R12)
    }

    private func cameraStateChanged(_ state: CameraFeedState) {
        let wasShown: Bool = CameraIndicator(state: cameraState).isShown
        cameraState = state
        cameraStopReason = cameraVisual?.stopReason   // CAM-013-R3
        let reason: CameraStopReason? = cameraStopReason
        // CAM-001-R14, CAM-002-R10, CAM-013-R12 (ACC-011 X17): the notice with its reason, through the router.
        if state.notice(position: settings.cameraPosition, reason: reason) != nil {
            statusEvents.post(StatusEventCatalog.camera(state, position: settings.cameraPosition, reason: reason))
        } else if !wasShown, CameraIndicator(state: state).isShown {   // ACC-011 X16: "Camera on"
            statusEvents.post(StatusEventCatalog.camera(state, position: settings.cameraPosition))
        }
    }

    /// CAM-013-R5, R6: the camera notice's Retry (backoff in the host).
    func retryCamera() {
        cameraVisual?.retryCamera()
    }

    /// CAM-002-R5, R7: Settings changed the camera or its mirror. Applied to the live Camera visual at
    /// once: a switch keeps the frame loop and the audio source running; the mirror shows from the next
    /// frame. Without the visual only the settings change (they never start the camera).
    func cameraSettingsChanged() {
        guard let host = cameraVisual else { return }
        host.cameraPosition = settings.cameraPosition
        host.mirrored = settings.cameraMirrored
        host.crop = settings.cameraCrop   // CAM-007-R5: from the next frame, the camera untouched
    }

    /// Runs whichever visual is shown and keeps the others paused.
    private func resumeActiveVisual() {
        prepareNativeVisualIfNeeded()
        prepareCameraVisualIfNeeded()
        preparePhotoVisualIfNeeded()
        prepareVideoVisualIfNeeded()
        prepareTextVisualIfNeeded()
        if showsCameraVisual {
            renderer?.pause()
            nativeVisual?.pause()
            photoVisual?.pause()
            videoVisual?.pause()
            textVisual?.pause()
            cameraVisual?.resume()   // starts the camera (CAM-001-R7)
            if let reader = cameraVisual?.tempoReader { tempo.follow(reader) } else { tempo.stopAnalysis() }
        } else if showsPhotoVisual {
            renderer?.pause()
            nativeVisual?.pause()
            cameraVisual?.pause()
            videoVisual?.pause()
            textVisual?.pause()
            photoVisual?.resume()
            if let reader = photoVisual?.tempoReader { tempo.follow(reader) } else { tempo.stopAnalysis() }
        } else if showsVideoVisual {
            renderer?.pause()
            nativeVisual?.pause()
            cameraVisual?.pause()
            photoVisual?.pause()
            textVisual?.pause()
            videoVisual?.resume()
            if let reader = videoVisual?.tempoReader { tempo.follow(reader) } else { tempo.stopAnalysis() }
        } else if showsTextVisual {
            renderer?.pause()
            nativeVisual?.pause()
            cameraVisual?.pause()
            photoVisual?.pause()
            videoVisual?.pause()
            textVisual?.resume()
            if let reader = textVisual?.tempoReader { tempo.follow(reader) } else { tempo.stopAnalysis() }
        } else if showsNativeVisual {
            renderer?.pause()
            cameraVisual?.pause()
            photoVisual?.pause()
            videoVisual?.pause()
            textVisual?.pause()
            nativeVisual?.resume()
            if let reader = nativeVisual?.tempoReader { tempo.follow(reader) } else { tempo.stopAnalysis() }
        } else {
            nativeVisual?.pause()
            cameraVisual?.pause()
            photoVisual?.pause()
            videoVisual?.pause()
            textVisual?.pause()
            renderer?.resume()
            tempo.runOwnAnalysis(on: trimmedAnalysisTap)
        }
    }

    /// REC-001: the shown visual's capture source (the same choice as `activeVisualMetrics`).
    var activeFrameCaptureSource: (any FrameCaptureSource)? {
        guard screen == .visualizer else { return nil }
        if showsCameraVisual { return cameraVisual }
        if showsPhotoVisual { return photoVisual }
        if showsVideoVisual { return videoVisual }
        if showsTextVisual { return textVisual }
        if showsNativeVisual { return nativeVisual }
        return renderer as? ANGLERenderer
    }

    /// REC-003: the shown visual's recording source; nil for projectM (not recordable in this row,
    /// ADR-0027) and when no visual is shown.
    var activeVideoRecordingSource: (any VideoRecordingSource)? {
        guard screen == .visualizer else { return nil }
        if showsCameraVisual { return cameraVisual }
        if showsPhotoVisual { return photoVisual }
        if showsVideoVisual { return videoVisual }
        if showsTextVisual { return textVisual }
        if showsNativeVisual { return nativeVisual }
        return nil
    }

    /// Frame statistics of the shown visual (FR-048 overlay).
    var activeVisualMetrics: RenderMetrics {
        if showsCameraVisual { return cameraVisual?.metrics ?? .zero }
        if showsPhotoVisual { return photoVisual?.metrics ?? .zero }
        if showsVideoVisual { return videoVisual?.metrics ?? .zero }
        if showsTextVisual { return textVisual?.metrics ?? .zero }
        return showsNativeVisual ? (nativeVisual?.metrics ?? .zero) : (renderer?.metrics ?? .zero)
    }

    private func pauseActiveVisual() {
        renderer?.pause()
        nativeVisual?.pause()
        cameraVisual?.pause()   // stops the camera (CAM-001-R7)
        photoVisual?.pause()
        videoVisual?.pause()
        textVisual?.pause()
        tempo.stopAnalysis()   // SHOW-011: the estimate's analysis runs only while a visual runs
    }

    // MARK: - Tap tempo (SHOW-011). Every use restarts the controls' hide delay (SHOW-011-R17).

    func tapTempo() { showControls(); tempo.tap() }
    func resetTempo() { showControls(); tempo.reset() }

    /// Settings changed the visual, its bar count or the linear spectrum's options: switch without
    /// touching the audio source (VIS-001-R12, VIS-002-R12).
    func visualSettingsChanged() {
        if !settings.visual.usesCamera { releaseCameraVisual() }   // CAM-001-R7: leaving Camera stops it
        if !settings.visual.usesPhoto { releasePhotoVisual() }     // MED-001
        if !settings.visual.usesVideo { releaseVideoVisual() }     // MED-002: leaving Video stops its decoder
        if !settings.visual.usesText { releaseTextVisual() }       // MED-009
        nativeVisual?.barCount = circularSpectrumBarCount
        nativeVisual?.smoothing = settings.spectrumSmoothing   // ANL-003: from the next frame, no snap
        cameraVisual?.barCount = circularSpectrumBarCount
        photoVisual?.barCount = circularSpectrumBarCount
        videoVisual?.barCount = circularSpectrumBarCount
        textVisual?.barCount = circularSpectrumBarCount
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
            prepareCameraVisualIfNeeded()
            preparePhotoVisualIfNeeded()
            prepareVideoVisualIfNeeded()
            prepareTextVisualIfNeeded()
            pauseActiveVisual()
        }
    }

    // MARK: - Session recovery (PERF-010, contract C3)

    /// Reopen: the held committed scene and visual (never Camera). OSC and the camera stay off until
    /// the user turns them on. The autosave records the change.
    /// SCN-012-R10: when the held scene has problems the user should see, the repair report comes first;
    /// Cancel keeps the offer.
    func reopenLastScene() {
        guard recovery.offersReopen, let held = recovery.heldScene else { return }
        if let registry = try? SceneArchiveService.appRegistry(),
           let report = Self.reopenReport(for: held, registry: registry, assets: storedMediaAvailability) {
            sceneRepair.present(SceneRepairRequest(title: "Last scene", report: report, document: held.document,
                                                   open: { [weak self] (document: SceneDocument) in
                                                       self?.finishReopen(Self.held(document, replacing: held, registry: registry))
                                                   }))
            return
        }
        finishReopen(nil)
    }

    /// The report Reopen shows first, or nil when the held scene opens without one.
    static func reopenReport(for held: SceneAutosaveHeldScene, registry: ParameterRegistry,
                             assets availability: StoredMediaAvailability) -> SceneRepairReport? {
        let report = SceneRepairReport(document: held.document, registry: registry, assets: availability)
        return report.needsReview ? report : nil
    }

    /// The held scene for a (repaired) document; the original when it does not load (it did at launch).
    static func held(_ document: SceneDocument, replacing held: SceneAutosaveHeldScene,
                     registry: ParameterRegistry) -> SceneAutosaveHeldScene {
        guard let loaded = try? document.liveState(registry: registry) else { return held }
        return SceneAutosaveHeldScene(document: document, live: loaded.state, source: held.source)
    }

    /// Which photo and video the stores hold now (SCN-001 asset availability).
    var storedMediaAvailability: StoredMediaAvailability {
        StoredMediaAvailability(photos: Set([photos.photo?.id.uuidString].compactMap { $0 }),
                                videos: Set([videos.video?.id.uuidString].compactMap { $0 }))
    }

    private func finishReopen(_ replacement: SceneAutosaveHeldScene?) {
        let visual = recovery.heldVisual
        guard let marked = recovery.markReopened() else { return }
        let held = replacement ?? marked
        if let values = sceneAutosave?.reopen(held) {
            SceneAutosaveCapture.apply(values, to: settings)
            if let text = values.text { texts.spec = text }
        }
        if let visual { settings.visual = visual }
        sceneHistory.restart()   // SCN-010-R9: Reopen is not an edit
        statusEvents.post(StatusEventCatalog.lastSceneReopened())   // ACC-011 X25
    }

    /// Start fresh: keeps the fresh scene and commits it, replacing the held one.
    func startFresh() {
        guard recovery.offer == .pending else { return }
        recovery.markStartedFresh()
        sceneAutosave?.commitFreshScene()
    }

    // MARK: - Scene autosave (SCN-002)

    /// What the current scene captures (research SCN-002-D1). Camera is session only: the visual
    /// chosen before it is recorded (CAM-001-R11).
    var sceneInputs: SceneInputs {
        SceneInputs(visual: SceneAutosaveCapture.recordedVisual(settings.visual, beforeCamera: settings.visualBeforeCamera),
                    bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                    spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                    glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                    text: texts.spec, photoID: photos.photo?.id, videoID: videos.video?.id)
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

    #if DEBUG
    // MARK: - Audio feature binding test path (MOD-002-R12; DEBUG only)

    /// Launch argument of AudioFeatureBindingUITests: bind the mean band level to the glow intensity
    /// (track-independent: the reference track leaves the lowest band below the floor).
    static let bindGlowToLevelArgument = "-uitestBindGlowToLevel"

    private func bindGlowToLevelIfRequested(_ host: NativeSpectrumHost) {
        guard ProcessInfo.processInfo.arguments.contains(Self.bindGlowToLevelArgument) else { return }
        try? host.bind(AudioFeatureBinding(source: .bandMean, target: VisualParameterIDs.bloomIntensity,
                                           outputStart: 0, outputEnd: 1))
    }

    /// "bound, manual 0.50, effective 0.73", or a note when no native visual exists.
    var glowModulationReadout: String { nativeVisual?.glowModulationReadout ?? "no native visual" }

    func unbindGlowTest() { nativeVisual?.unbind(VisualParameterIDs.bloomIntensity) }
    #endif

    /// The system Reduce Motion setting changed.
    func systemReduceMotionChanged(_ enabled: Bool) {
        settings.systemReduceMotion = enabled
        applyReduceFlashing()
    }

    // MARK: - Reduce Motion (ACC-001)

    /// ACC-001-R2: the policy every decorative UI animation goes through; it follows
    /// `settings.systemReduceMotion`, so views re-render as soon as the system setting changes.
    var motion: MotionPolicy { MotionPolicy(settings: settings) }

    /// The system Reduce Motion state, or in DEBUG the `-uitestReduceMotion YES|NO` override.
    static func currentSystemReduceMotion() -> Bool {
        #if DEBUG
        if let override = reduceMotionOverride { return override }
        #endif
        return UIAccessibility.isReduceMotionEnabled
    }

    /// ACC-001-R3: the system notification (observed at the app root) and scene activation land here.
    func syncSystemReduceMotion() {
        let current = Self.currentSystemReduceMotion()
        if current != settings.systemReduceMotion { systemReduceMotionChanged(current) }
    }

    #if DEBUG
    static let reduceMotionArgument = "-uitestReduceMotion"
    /// The UI-test override (contract C2); while set, the real setting is ignored.
    static var reduceMotionOverride: Bool? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: reduceMotionArgument), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "YES": return true
        case "NO": return false
        default: return nil   // `system`: the real setting, with the probe panel (research D5)
        }
    }()
    /// The probe panel is shown whenever the argument is present.
    static let reduceMotionPanelRequested = ProcessInfo.processInfo.arguments.contains(reduceMotionArgument)

    /// `motionProbe` (contract C2): "reduce=<on|off> controls=<seconds|none>".
    var motionProbe: String {
        let seconds = lastControlsTransitionSeconds.map { String(format: "%.2f", $0) } ?? "none"
        return "reduce=\(motion.reduceMotion ? "on" : "off") controls=\(seconds)"
    }

    /// `simulateReduceMotionToggle`: flips the override and takes the notification's path.
    func simulateSystemReduceMotionToggle() {
        Self.reduceMotionOverride = !Self.currentSystemReduceMotion()
        syncSystemReduceMotion()
    }
    #endif

    func togglePause() {
        userPaused.toggle()
        userPaused ? pauseActiveVisual() : resumeActiveVisual()
        updateIdleTimer()
        showControls()
        announcer.announce(AccessibilityAnnouncer.pausedText(userPaused), kind: .playback)   // ACC-004-R5
    }

    func next() { showControls(); Task { await announcingPresetChange { await presets.next() } } }
    func previous() { showControls(); Task { await announcingPresetChange { await presets.previous() } } }
    func random() { showControls(); Task { await announcingPresetChange { await presets.random() } } }

    /// ACC-004-R5, R6: a user's Previous, Next, Random or browser choice announces the preset it
    /// showed; nothing is announced when the preset did not change (a failed load, an empty scope, a
    /// warning still waiting). No other path announces a preset.
    func announcingPresetChange(_ change: () async -> Void) async {
        let before = presets.current
        await change()
        guard let shown = presets.current, shown != before else { return }
        announcer.announce(AccessibilityAnnouncer.presetText(shown.name), kind: .preset)
    }

    /// A preset chosen in the browser, from the list that becomes the scope (FR-116).
    func choose(_ preset: IndexedPreset, from scope: PresetScope) {
        showControls()
        Task {
            await announcingPresetChange { await presets.choose(preset, from: scope) }   // ACC-004-R5
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
        guard manager.switchingTo == nil else { return nil }   // AUD-012-R7: no source to describe yet
        return AudioRouteContext.make(mode: manager.activeMode, state: manager.state, isPausedByUser: manager.isPausedByUser)
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
        guard !UIAccessibility.isVoiceOverRunning, !Self.keepsControlsForAccessibilityTests else { return }
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
        if active { syncSystemReduceMotion() }   // ACC-001-R3: a change made while in the background
        osc.sceneBecame(active: active)   // OSC-001-R3: no listener outside the foreground
        updateIdleTimer()
    }

    // MARK: - Memory pressure (PERF-006-R12): the idle native spectrum

    let memoryPressureName = "idle native spectrum"
    let memoryPressureTier = MemoryPressureTier.cache
    /// The spectrum's images have no measured size; the step reports items only (research PERF-006-D5).
    var reclaimableBytes: Int { 0 }

    /// Releases a native spectrum host that is not the chosen visual (it is paused: its frame loop has
    /// stopped and in-flight command buffers keep their own references). A chosen one is kept; it is
    /// created again the next time a spectrum is chosen.
    func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease {
        guard let host = nativeVisual, Self.releasesIdleNativeSpectrum(choice: settings.visual, hostExists: true) else { return .none }
        host.pause()
        nativeVisual = nil   // the presentation registry holds it weakly
        return MemoryPressureRelease(bytes: 0, items: 1)
    }

    /// A spectrum host is idle (and may be freed) only while the chosen visual is not a native spectrum.
    static func releasesIdleNativeSpectrum(choice: VisualChoice, hostExists: Bool) -> Bool {
        hostExists && !choice.isNative
    }

    #if DEBUG
    /// Frames presented by the shown visual (MemoryPressureUITests).
    var activeVisualFrames: Int {
        if showsCameraVisual { return cameraVisual?.framesShown ?? 0 }
        if showsPhotoVisual { return photoVisual?.framesShown ?? 0 }
        if showsVideoVisual { return videoVisual?.framesShown ?? 0 }
        if showsNativeVisual { return nativeVisual?.presentedFrameCount ?? 0 }
        return renderer?.presentedFrameCount ?? 0
    }

    /// The preset warm-up holds its thread or context now (its cache step could free something).
    var warmUpHoldsContext: Bool { (renderer?.memoryPressureResponders.first?.reclaimableBytes ?? 0) > 0 }
    #endif

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
        Self.systemOverlaysHidden(onVisualizer: screen == .visualizer, controlsVisible: controlsVisible,
                                  mode: manager.activeMode, cameraShown: showsCameraVisual)
    }

    /// CAM-001-R10: never hidden while the Camera visual is shown, so iOS's camera indicator stays.
    static func systemOverlaysHidden(onVisualizer: Bool, controlsVisible: Bool, mode: AudioSourceMode?, cameraShown: Bool) -> Bool {
        guard onVisualizer, !controlsVisible, !cameraShown else { return false }
        return mode == .inAppPlayback
    }
}

/// Loads presets into whichever renderer the app created (PresetLoading for PresetCoordinator).
@MainActor
final class RendererPresetLoader: PresetLoading, MemoryPressureResponder {
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

    // MARK: - Memory pressure (PERF-006-R11)

    let memoryPressureName = "preset archive cache"
    let memoryPressureTier = MemoryPressureTier.cache
    var reclaimableBytes: Int { archive?.cachedBytes ?? 0 }

    /// Drops the archive's decompressed chunk (measured); the archive stays open (its file is mapped).
    func releaseForMemoryPressure(_ level: MemoryPressureLevel) -> MemoryPressureRelease {
        let bytes = archive?.dropCache() ?? 0
        return MemoryPressureRelease(bytes: bytes, items: bytes > 0 ? 1 : 0)
    }

    private func packArchive(_ resources: URL) throws -> PresetArchive {
        if let archive { return archive }
        guard let library else { throw CocoaError(.featureUnsupported) }
        let opened = try PresetArchive(url: resources.appendingPathComponent("PresetArchive.bin"), packIds: library.archiveOrder)
        archive = opened
        return opened
    }
}
