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
import Metal
import CameraLayer
import ImageLayer
import VideoLayer
import TextLayer
import AudioCore
import CaptureKit
import Compositor
import FrameRecording   // REC-005: the capability source type
import CaptureUI
import Diagnostics
import FlashSafety
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
import PerformanceControl   // OSC-003: the receiver, its routes and the shared live values
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
    /// PERF-009: the startup warm cache (prepared library snapshot, native pipeline archive).
    @ObservationIgnored let warmStart: WarmStartCache = WarmStartCache.standard()
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
    /// PRE-006: the recent presets over their stored history.
    private static func makeRecentPresets(defaults: UserDefaults) -> RecentPresetsCoordinator {
        let store: RecentPresetsStore = RecentPresetsStore(defaults: defaults)
        return RecentPresetsCoordinator(store: store)
    }

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
    /// SCN-008: named parameter snapshots of the current scene (AppCoordinator+SceneSnapshots.swift).
    @ObservationIgnored let sceneSnapshots = SceneSnapshotCoordinator()
    /// SCN-009: A/B compare of two scene states (AppCoordinator+SceneCompare.swift).
    @ObservationIgnored let sceneCompare = SceneCompareCoordinator()
    /// REC-002: render selected snapshots to PNG files (AppCoordinator+SnapshotBatch.swift).
    @ObservationIgnored let snapshotBatch = SnapshotBatchExportCoordinator()
    /// REC-013: deterministic offline video export (AppCoordinator+OfflineExport.swift).
    @ObservationIgnored let offlineExport = OfflineExportCoordinator()
    /// CMP-015: the layer inspector's composites (a scene input) and transient solo/mute.
    let layers = LayerInspectorCoordinator()
    /// SCN-002: the current scene's autosave (nil only if its folder cannot be made).
    @ObservationIgnored let sceneAutosave: SceneAutosaveCoordinator?
    /// PERF-010: abnormal-exit detection, the recovery offer and its consent rules.
    let recovery: SessionRecoveryCoordinator
    /// UIX-001: the guided first scene (stored state and whether it is shown).
    let guide: GuidedFirstSceneCoordinator
    /// UIX-015: the explainer shown before the camera and local network prompts.
    let explainers: PermissionExplainerCoordinator
    /// Performance overlay and Reduce flashing (T103).
    let settings: AppSettings
    /// AUD-008: the analysis-only input trim (Settings → Audio Analysis).
    let inputTrim: InputTrimSetting
    /// AUD-009: the analysis-only channel selection (Settings → Analysis Channel).
    let channelSelection: ChannelSelectionSetting
    /// AUD-010: the monitoring balance of In-App Playback (Settings → Playback Balance).
    let playbackBalance: PlaybackBalanceSetting
    /// AUD-011: the analysis-only noise gate (Settings → Audio Analysis; microphone source only).
    let noiseGate: NoiseGateSetting
    /// AUD-013: the per-source visual delay (Settings → Visual Delay; analysis and projectM's feed).
    let latencyOffset: LatencyOffsetSetting
    /// FX-003: the colour grade (Settings → Color) of the compositor-backed visuals.
    let colorGrade: ColorGradeSetting
    /// FX-009: Trails (Settings → Trails) of the compositor-backed visuals.
    let motionFeedback: MotionFeedbackSetting
    /// FX-020: the order of Trails and Color, and the chain presets.
    let effectChain: EffectChainSetting
    /// FX-006: the chromatic split (Settings → Chromatic split) of the compositor-backed visuals.
    let chromaticSplit: ChromaticSplitSetting
    /// FX-007: the directional blur (Settings → Directional blur) of the compositor-backed visuals.
    let directionalBlur: DirectionalBlurSetting
    /// FX-008: the radial blur (Settings → Radial blur) of the compositor-backed visuals.
    let radialBlur: RadialBlurSetting
    /// FX-010: Echo (Settings → Echo) of the compositor-backed visuals.
    let echoFeedback: EchoSetting
    /// FX-012: the mosaic (Settings → Mosaic) of the compositor-backed visuals.
    let mosaic: MosaicSetting
    /// FX-014: the edge outline (Settings → Edge outline) of the compositor-backed visuals.
    let edgeOutline: EdgeOutlineSetting
    /// FX-016: the lens distortion (Settings → Lens distortion) of the compositor-backed visuals.
    let lensDistortion: LensDistortionSetting
    /// FX-015: the vignette (Settings → Vignette) of the compositor-backed visuals.
    let vignette: VignetteSetting
    /// FX-011: the pixel sort (Settings → Pixel sort) of the compositor-backed visuals.
    let pixelSort: PixelSortSetting
    /// FX-018: the scanlines (Settings → Scanlines) of the compositor-backed visuals.
    let scanlines: ScanlinesSetting
    /// FX-017: the film grain (Settings → Film grain) of the compositor-backed visuals.
    let filmGrain: FilmGrainSetting
    /// The native spectra (VIS-001 circular, VIS-002 linear), created the first time one is needed.
    private(set) var nativeVisual: NativeSpectrumHost?
    /// MIDI-003 and OSC-003 live values, merged (newest change wins per parameter; OSC-003-R5).
    @ObservationIgnored private(set) var externalLiveValues = ExternalLiveValues()
    /// PERF-001: the stage timer while the performance overlay is shown (AppCoordinator+FrameStages.swift).
    @ObservationIgnored let frameStages = FrameStageAttachment()
    @ObservationIgnored let frameDrops = FrameDropAttachment()   // PERF-007
    @ObservationIgnored let featureAges = FeatureAgeAttachment()   // PERF-013
    /// PERF-012: the session's state timeline and memory peak, and the Export performance report action.
    @ObservationIgnored let performanceRecorder = PerformanceStateRecorder()
    @ObservationIgnored private(set) lazy var performanceReport = PerformanceReportExport { [unowned self] (date: Date) throws -> Data in
        try self.performanceReportData(exportedAt: date)
    }
    /// The Camera visual (CAM-001), created when Camera is chosen and released when another visual is.
    private(set) var cameraVisual: CameraVisualHost?
    /// The camera feed's state while the Camera visual exists (`idle` otherwise; CAM-001-R5 to R8).
    private(set) var cameraState: CameraFeedState = .idle
    /// CAM-003: the device's back lenses (the stand-in's in DEBUG UI tests); listing starts no camera.
    @ObservationIgnored let cameraLensInventory: any CameraLensInventory = CameraVisualHost.makeLensInventory()
    /// CAM-004: the camera's exposure, read back (session state; CameraExposureRow.swift).
    private(set) var cameraExposure: CameraExposureState = .notRunning(canLock: false)
    /// CAM-005: the camera's focus, read back, and the ring/explanation shown after a focus tap (CameraFocusRing.swift).
    private(set) var cameraFocus: CameraFocusState = .notRunning(canFocus: false)
    /// CAM-006: the camera's white balance, read back (session state; CameraWhiteBalanceRow.swift).
    private(set) var cameraWhiteBalance: CameraWhiteBalanceState = .notRunning(canLock: false)
    /// CAM-008: whether the person mask can be drawn (session state; CameraPersonMaskRow.swift).
    var cameraPersonMaskAvailability: PersonMaskAvailability = .available
    @ObservationIgnored let cameraFocusFeedback = CameraFocusFeedback()
    /// CAM-003-R6: a lens the user chose waits for the switch's end (CameraLensRow.swift).
    @ObservationIgnored var cameraLensChoicePending = false
    /// CAM-013: why the camera is interrupted or failed (nil otherwise), and whether a Retry waits.
    private(set) var cameraStopReason: CameraStopReason?
    private(set) var cameraRetryPending = false
    /// UIX-015-R7: the user dismissed the camera's denied or restricted notice for this attempt
    /// (reset whenever the Camera visual is created or released).
    private(set) var cameraNoticeDismissed = false
    /// The imported photo (MED-001): the store, the pickers' results and the notice.
    let photos: PhotoCoordinator
    /// The image slideshow (MED-006): pictures, order, timing and the schedule; drives the Photo visual.
    let slideshow: SlideshowCoordinator
    /// MED-007: the photo's Ken Burns pan and zoom (shared by every slide).
    let kenBurns: KenBurnsCoordinator
    /// The logo overlay (MED-010): the stored logo, its placement and the compositor visuals' logo layers.
    let logo: LogoCoordinator
    /// MED-011: the clock overlay's settings, its ticking and the compositor visuals' clock layers.
    let clock: ClockOverlayCoordinator
    /// MED-012: the countdown overlay's settings, its timer and the compositor visuals' countdown layers.
    let countdown: CountdownOverlayCoordinator
    /// UIX-011: palettes and the scene's palette link.
    let palettes: PaletteCoordinator
    /// MOD-010: the current scene's parameter macros (Settings › Macros).
    let macros: MacroCoordinator
    /// MOD-012: the current scene's routes (Settings › Modulation; AppCoordinator+ModulationMatrix.swift).
    let modulationMatrix = ModulationMatrixCoordinator()
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
    /// SHOW-002: the timed cue advance (created in `connectShow`; AppCoordinator+Show.swift).
    @ObservationIgnored private(set) lazy var showAutoAdvance: ShowAutoAdvanceCoordinator = makeShowAutoAdvance()
    /// UIX-005-R1: the performance layout (large cue, tempo and blackout targets); session only, off at launch.
    var performanceLayout = AppCoordinator.startsInPerformanceLayout
    /// UIX-007-R7: the iPad split editor's remembered width (SplitEditorSetting.swift).
    @ObservationIgnored private(set) lazy var splitEditor = SplitEditorSetting(defaults: defaults)
    /// UIX-008: scene editor windows (one editor per saved scene) and the one performing main window (ADR-0105).
    @ObservationIgnored private(set) lazy var sceneEditors = SceneEditorWindowRouter(library: show)
    @ObservationIgnored let performanceWindows = PerformanceWindowClaim()
    /// SCN-007, XFADE: the cues' resolved transitions, blended out on the shown compositor visual.
    @ObservationIgnored let cueTransitions = CueTransitionStage()
    /// UIX-002: the quick scene switcher's overlay state (AppCoordinator+SceneSwitcher.swift).
    let sceneSwitcher = SceneSwitcherModel()
    /// SCN-006: scene preview pictures for the switcher and Scene Folders (AppCoordinator+ScenePreviews.swift).
    @ObservationIgnored private(set) lazy var scenePreviews: ScenePreviewModel = makeScenePreviews()
    /// SCN-012: the repair report before a show cue's scene or Reopen opens.
    let sceneRepair: SceneRepairCoordinator
    /// MED-013: missing imported media (Settings › Storage › Missing Media) and the visualizer's placeholder.
    let missingMedia = MissingMediaCoordinator()
    /// REC-010: Settings › Storage › Recordings (announces on the `library` lane).
    @ObservationIgnored private(set) lazy var recordingLibrary: RecordingLibraryModel = makeRecordingLibrary()
    /// ACC-011: capture and recording status events (announcements and captions); owns ACC-004's announcer.
    let statusEvents = StatusEventRouter()
    /// ANL-013: the native visual's stereo phase-inversion warning (source indicator, overlay, X3a/X3b).
    let stereoPhase = StereoPhaseWarningPresenter()
    /// FILE-005: Settings › Storage › Backup (announces on the `library` lane, set in init).
    @ObservationIgnored let libraryBackup = LibraryBackupCoordinator()
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
    /// MIDI endpoint discovery (MIDI-001): off by default, runs only while enabled and active.
    let midi: MIDIDiscoveryCoordinator
    /// MIDI-002: the shared MIDI input (receives only while a feature needs it and discovery listens).
    let midiInput: MIDIInputCoordinator
    /// MIDI-002: the MIDI Monitor (opened from the MIDI section; `midi.monitor` points here).
    let midiMonitor: MIDIMonitorCoordinator
    /// MIDI-003: MIDI learn and the mapping list (opened from the MIDI section; `midi.mappings` points here).
    let midiMappings: MIDIMappingCoordinator
    /// MIDI-010: Follow MIDI clock (Settings → MIDI; off by default); feeds `tempo` while a clock is locked.
    let midiClock: MIDIClockCoordinator
    /// REC-001: Save Frame (the shown visual's next frame, to the Files exporter).
    @ObservationIgnored private(set) lazy var frameCapture = FrameCaptureCoordinator { [weak self] () -> FrameCaptureCoordinator.Context in
        guard let self else { return FrameCaptureCoordinator.Context(source: nil, outputLive: false, paused: false) }
        return FrameCaptureCoordinator.Context(source: self.activeFrameCaptureSource,
                                               outputLive: self.externalDisplay.blackoutPhase == .live, paused: self.userPaused)
    }
    /// UIX-012: the touch colour sampler (AppCoordinator+ColorSampler.swift).
    @ObservationIgnored private(set) lazy var colorSampler: ColorSamplerCoordinator = makeColorSampler()
    /// REC-012: Share… for an offered frame or recording; created with the app so its sweep of
    /// leftover share copies runs at launch (REC-012-R6).
    @ObservationIgnored let captureShare = CaptureShareCoordinator()
    /// REC-011: Save to Photos (add-only access, asked only on the user's tap; ADR-0059).
    @ObservationIgnored let photosSave = PhotosSaveCoordinator.forCurrentLaunch()
    /// REC-003: Record (the shown visual's frames into a video file, handed to the file mover).
    @ObservationIgnored private(set) lazy var videoRecording: VideoRecordingCoordinator = makeVideoRecording()
    /// REC-004: "Include microphone audio" for recordings (Settings → Recording; off by default).
    let recordingAudio: RecordingAudioSetting
    /// REC-005: the record quality profile (Settings → Recording quality; Standard by default). The rows
    /// describe the shown visual's drawable, else the screen (REC-005-R12). Its `-uitestResetNotice` reset is in
    /// its initializer (keeps this initializer within the type-check budget).
    @ObservationIgnored private(set) lazy var recordingQuality = RecordingQualitySetting(
        defaults: defaults, capabilities: { () -> any RecordingEncoderCapabilities in RecordingQualitySetting.deviceCapabilities() },
        rowSize: { [weak self] () -> CGSize in
            self?.activeVideoRecordingSource?.recordingDrawableSize ?? RecordingQualitySetting.screenPixelSize()
        })
    /// REC-007: the recording countdown (Settings → Recording countdown; Off by default).
    @ObservationIgnored private(set) lazy var recordingCountdown = RecordingCountdownSetting(defaults: defaults)
    /// UIX-013: the scene performance HUD preference (Settings → Show HUD; off by default).
    @ObservationIgnored private(set) lazy var sceneHUD = SceneHUDSetting(defaults: defaults)
    /// UIX-006: gesture shortcuts on the visualization (Settings → Gesture shortcuts; off by default). Edits are
    /// refused while the scene is locked.
    @ObservationIgnored private(set) lazy var gestureShortcuts: GestureShortcutsSetting = makeGestureShortcutsSetting(defaults: defaults)
    /// UIX-006-R7: runs resolved gesture shortcuts through the existing controls' paths.
    @ObservationIgnored private(set) lazy var gestureShortcutPerformer: GestureShortcutPerformer = makeGestureShortcutPerformer()
    /// UIX-006: the last action a gesture shortcut ran and how many ran (tests and the DEBUG probe, contract G5).
    var lastGestureShortcut: GestureAction = .none
    var gestureShortcutCount = 0
    /// OUT-005: the safe-area guides preference (Settings → Safe-area guides; off by default; device only).
    @ObservationIgnored private(set) lazy var safeAreaGuides = SafeAreaGuideSetting(defaults: defaults)
    /// ACC-009: the one-handed layout preference (Settings → One-handed layout; Off by default; iPhone only).
    @ObservationIgnored private(set) lazy var oneHanded = OneHandedSetting(defaults: defaults)
    /// SHOW-006: cue rehearsal (session only; device-only panel).
    @ObservationIgnored private(set) lazy var cueRehearsal: CueRehearsalCoordinator = makeCueRehearsal()
    /// SHOW-007: the show timeline transport (Play/Pause over SHOW-005's Hold, seek, scrub, Loop).
    @ObservationIgnored private(set) lazy var showTransport: ShowTransportCoordinator = makeShowTransport(defaults: defaults)
    /// SHOW-008: keyframe tracks along the show timeline (a live layer under MIDI/OSC values; Visual Colour).
    @ObservationIgnored private(set) lazy var showKeyframes: ShowKeyframeCoordinator = makeShowKeyframes()
    /// SHOW-013: auto scene rotation (session on/off; settings in `settings.show.rotation`).
    @ObservationIgnored private(set) lazy var sceneRotation: SceneRotationCoordinator = makeSceneRotation(defaults: defaults)
    /// PERF-008: the power profile (made in `init`, so the first frame loop already runs under it).
    @ObservationIgnored private(set) lazy var powerProfile = PowerProfileSetting(defaults: defaults)
    /// CAM-011: device tilt and shake as modulation sources (Settings › Motion; the sensor runs only while used).
    @ObservationIgnored private(set) lazy var motionModulation: MotionModulationCoordinator = makeMotionModulation(defaults: defaults)
    /// CAM-009: opt-in face tracking on the Camera visual's pictures (Settings › Camera; consent first).
    @ObservationIgnored private(set) lazy var faceTracking: FaceTrackingCoordinator = makeFaceTracking(defaults: defaults)
    /// CAM-010: opt-in hand tracking on the same pictures (Settings › Camera; its own consent).
    @ObservationIgnored private(set) lazy var handTracking: HandTrackingCoordinator = makeHandTracking(defaults: defaults)
    /// ACC-007: haptic beat pulses (Settings → Haptics; off by default), fed by the tempo poll while on.
    @ObservationIgnored private(set) lazy var hapticBeat = HapticBeatCoordinator(
        defaults: defaults, tempo: tempo, clamp: { [unowned self] () -> SafetyClamp in self.settings.safetyClamp })
    /// OUT-004: the external display's output correction (Settings › External Display).
    @ObservationIgnored private(set) lazy var externalOutput = ExternalOutputSetting(defaults: defaults, external: externalDisplay)
    /// REC-008: the recording length (Settings → Stop recording after; Off by default).
    @ObservationIgnored private(set) lazy var recordingTimedStop = RecordingTimedStopSetting(defaults: defaults)
    /// UIX-004: the favorite parameter shelf (pinned controls in the visualizer's controls).
    let parameterShelf: ParameterShelf
    /// REC-004: reads the microphone permission (never asks for it).
    @ObservationIgnored private lazy var microphonePermissionProbe = AVMicrophoneBackend()

    private let defaults: UserDefaults
    #if DEBUG
    private(set) var fakeSource: UITestFakeSource?
    #endif
    private var hideTask: Task<Void, Never>?
    private let lifecycle: LifecycleObserver
    private var lifecycleForwarding: Task<Void, Never>?
    /// Presentation-bound resources (PERF-011): the renderer registers its own in prepareRenderer().
    @ObservationIgnored let presentation = PresentationResourceRegistry()
    /// PERF-005: the next cues' media decoded ahead (AppCoordinator+Prewarm).
    @ObservationIgnored let mediaPrewarm = MediaPrewarmCoordinator.makeDefault()
    @ObservationIgnored private var lifecycleCoordinator: LifecycleCoordinator!
    /// PERF-006: the one receiver of memory warnings; the app's recovery steps are registered there.
    @ObservationIgnored let memoryPressure: MemoryPressureCoordinator

    init(defaults: UserDefaults = .standard, externalDisplay: ExternalDisplayCoordinator? = nil,
         memoryPressure: MemoryPressureCoordinator? = nil) {
        self.defaults = defaults
        self.memoryPressure = memoryPressure ?? .shared
        self.externalDisplay = externalDisplay ?? .shared
        Self.prepareStoredState(defaults: defaults)   // UI-test reset, FILE-005 restore, FILE-008 reconcile
        #if DEBUG
        Self.applyUITestDefaults(defaults)   // QA-011 device acceptance: typed settings from a launch argument
        #endif
        let settings: AppSettings = AppSettings(defaults: defaults, systemReduceMotion: Self.currentSystemReduceMotion())
        self.settings = settings
        inputTrim = InputTrimSetting(defaults: defaults)
        channelSelection = ChannelSelectionSetting(defaults: defaults)
        noiseGate = NoiseGateSetting(defaults: defaults)
        recordingAudio = RecordingAudioSetting(defaults: defaults)
        parameterShelf = ParameterShelf(defaults: defaults)   // UIX-004
        playbackBalance = PlaybackBalanceSetting(defaults: defaults)   // AUD-010
        latencyOffset = LatencyOffsetSetting(defaults: defaults)
        let effects: EffectSettings = EffectSettings(defaults: defaults)   // FX-003 to FX-020, read in the same order
        colorGrade = effects.colorGrade
        motionFeedback = effects.motionFeedback
        effectChain = effects.chain
        chromaticSplit = effects.chromaticSplit
        directionalBlur = effects.directionalBlur
        radialBlur = effects.radialBlur
        echoFeedback = effects.echo
        mosaic = effects.mosaic
        edgeOutline = effects.edgeOutline
        lensDistortion = effects.lensDistortion
        vignette = effects.vignette
        pixelSort = effects.pixelSort
        scanlines = effects.scanlines
        filmGrain = effects.filmGrain
        self.externalDisplay.reduceFlashing = settings.effectiveReduceFlashing   // OUT-010-R6, ACC-012-R7
        // PERF-010 (contract C1): decide before the OSC receiver exists, so an abnormal exit never
        // reopens the listener; a pending offer holds the scene instead of restoring it.
        let recovery: SessionRecoveryCoordinator = SessionRecoveryCoordinator(
            defaults: defaults, suppressed: SessionRecoveryCoordinator.harnessSuppresses())
        let holdsScene: Bool = recovery.prepare(settings: settings)
        self.recovery = recovery
        let guide: GuidedFirstSceneCoordinator = GuidedFirstSceneCoordinator(
            defaults: defaults, suppressed: GuidedFirstScenePolicy.harnessSuppresses())
        self.guide = guide
        let osc: OSCReceiverCoordinator = Self.makeOSC(settings: settings, defaults: defaults)
        self.osc = osc
        explainers = Self.makeExplainers(settings: settings, osc: osc, defaults: defaults)
        let midiStack: MIDIStack = Self.makeMIDI(settings: settings, defaults: defaults, announcer: statusEvents.announcer)
        midi = midiStack.discovery
        midiInput = midiStack.input
        midiMonitor = midiStack.monitor
        midiMappings = midiStack.mappings
        let media: MediaStores = MediaStores(defaults: defaults, settings: settings)
        photos = media.photos
        slideshow = media.slideshow
        kenBurns = media.kenBurns
        logo = media.logo
        clock = media.clock
        countdown = media.countdown
        palettes = media.palettes
        macros = media.macros
        videos = media.videos
        texts = media.texts
        // SCN-002: the last committed scene wins over the settings (research SCN-002-D2).
        let sceneAutosave: SceneAutosaveCoordinator? = SceneAutosaveCoordinator.makeDefault(defaults: defaults)
        Self.restoreScene(from: sceneAutosave, holdsScene: holdsScene, recovery: recovery, settings: settings,
                          effects: effects, media: media, layers: layers)
        self.sceneAutosave = sceneAutosave
        show = ShowCoordinator.makeDefault()   // SHOW-001
        EngineInstanceLedger.coordinators += 1   // UIX-008-D9: this init creates the one CaptureManager
        sceneRepair = SceneRepairCoordinator(registry: try? SceneArchiveService.appRegistry())   // SCN-012
        #if DEBUG
        Self.seedMediaFixtures(media)   // MED-001, MED-002, MED-006, MED-009, MED-010, MOD-010
        #endif
        let initialScreen: Screen = defaults.bool(forKey: Self.noticeKey) ? .chooser : .notice
        screen = initialScreen
        // UIX-001-R1: a pending tutorial is offered again (not over PERF-010's offer).
        if initialScreen == .chooser { guide.presentAtLaunchIfDue(recoveryPending: recovery.offer == .pending) }
        let microphone: MicrophoneSource = MicrophoneSource(backend: AVMicrophoneBackend())
        self.microphone = microphone
        let inAppPlayback: InAppPlaybackSource = InAppPlaybackSource(backend: AVInAppPlaybackBackend())
        self.inAppPlayback = inAppPlayback
        Self.connect(playbackBalance, to: inAppPlayback)   // AUD-010
        audioLibrary = AudioLibraryCoordinator.makeDefault()
        #if DEBUG
        let made: (manager: CaptureManager, fakes: [UITestFakeSource]) = Self.makeManager(microphone: microphone, inAppPlayback: inAppPlayback)
        let manager: CaptureManager = made.manager
        #else
        let manager: CaptureManager = Self.makeManager(microphone: microphone, inAppPlayback: inAppPlayback)
        #endif
        self.manager = manager
        transport = PlaybackTransport(manager: manager, source: inAppPlayback)
        let lifecycle: LifecycleObserver = LifecycleObserver()
        self.lifecycle = lifecycle
        let tempo: TempoCoordinator = Self.makeTempo(defaults: defaults)
        self.tempo = tempo
        let midiClock: MIDIClockCoordinator = MIDIClockCoordinator(input: midiStack.input, tempo: tempo, defaults: defaults)   // MIDI-010
        self.midiClock = midiClock
        midiStack.discovery.clock = midiClock
        #if DEBUG
        Self.applyTempoScript(to: tempo, defaults: defaults)   // ANL-006 D7
        #endif
        // Feature 002: the library (12,941 presets) loads off the main thread (SC-101).
        let presetStack: PresetStack = Self.makePresetStack(defaults: defaults, settings: settings, loader: presetLoader)
        presets = presetStack.presets
        userPresets = presetStack.userPresets
        entitlements = Self.makeEntitlements()
        #if DEBUG
        fakeSource = made.fakes.first
        #endif
        connectLifecycle(lifecycle)
        _ = powerProfile   // PERF-008-R6: the stored profile is active before any visual starts
        connectAfterInit(defaults: defaults)
    }

    // AppCoordinator.init is split into typed steps (2026-11-14, again 2026-11-15) to keep each body
    // under the type-check budget that Xcode 26 on CI enforces: the factories below run at the same
    // points and in the same order as the code they replaced; the wiring that needs every stored
    // property set runs in connectLifecycle(_:) and connectAfterInit(defaults:).

    /// `-uitestResetNotice`, then FILE-005-R6, R7: a pending restore (or an interrupted one) finishes
    /// before any store reads the library; FILE-008-R7, R8: media folders are reconciled after it.
    private static func prepareStoredState(defaults: UserDefaults) {
        if ProcessInfo.processInfo.arguments.contains("-uitestResetNotice") { resetForUITests(defaults) }
        LibraryBackupCoordinator.finishPendingRestore(defaults: defaults)
        reconcileMediaFolders(defaults: defaults)
    }

    /// The compositor effects' settings (FX-003 to FX-020), created in the order `init` always used.
    private struct EffectSettings {
        let colorGrade: ColorGradeSetting
        let motionFeedback: MotionFeedbackSetting
        let chain: EffectChainSetting
        let chromaticSplit: ChromaticSplitSetting
        let directionalBlur: DirectionalBlurSetting
        let radialBlur: RadialBlurSetting
        let echo: EchoSetting
        let mosaic: MosaicSetting
        let edgeOutline: EdgeOutlineSetting
        let lensDistortion: LensDistortionSetting
        let vignette: VignetteSetting
        let pixelSort: PixelSortSetting
        let scanlines: ScanlinesSetting
        let filmGrain: FilmGrainSetting

        @MainActor
        init(defaults: UserDefaults) {
            colorGrade = ColorGradeSetting(defaults: defaults)   // FX-003
            motionFeedback = MotionFeedbackSetting(defaults: defaults)   // FX-009
            chain = EffectChainSetting(defaults: defaults)   // FX-020
            chromaticSplit = ChromaticSplitSetting(defaults: defaults)   // FX-006
            directionalBlur = DirectionalBlurSetting(defaults: defaults)   // FX-007
            radialBlur = RadialBlurSetting(defaults: defaults)   // FX-008
            echo = EchoSetting(defaults: defaults)   // FX-010
            mosaic = MosaicSetting(defaults: defaults)   // FX-012
            edgeOutline = EdgeOutlineSetting(defaults: defaults)   // FX-014
            lensDistortion = LensDistortionSetting(defaults: defaults)   // FX-016
            vignette = VignetteSetting(defaults: defaults)   // FX-015
            pixelSort = PixelSortSetting(defaults: defaults)   // FX-011
            scanlines = ScanlinesSetting(defaults: defaults)   // FX-018
            filmGrain = FilmGrainSetting(defaults: defaults)   // FX-017
        }

        /// FX-020, FX-006 to FX-008, FX-010, FX-012, FX-014, FX-016, FX-015, FX-011, FX-018, FX-017.
        @MainActor
        func apply(_ values: [SceneEffectEntry]?) {
            SceneAutosaveCapture.applyEffects(values, chain: chain, grade: colorGrade, trails: motionFeedback,
                                              chromatic: chromaticSplit, directionalBlur: directionalBlur,
                                              radialBlur: radialBlur, echo: echo,
                                              mosaic: mosaic, edgeOutline: edgeOutline,
                                              lensDistortion: lensDistortion, vignette: vignette,
                                              pixelSort: pixelSort, scanlines: scanlines, filmGrain: filmGrain)
        }
    }

    /// The OSC receiver (OSC-001) with its OSC-003 routes, made before anything can open a listener.
    private static func makeOSC(settings: AppSettings, defaults: UserDefaults) -> OSCReceiverCoordinator {
        let oscRoutable: [ParameterDescriptor] = OSCRoutesCoordinator.routable()   // OSC-003: the allowlist's targets
        let oscReceiver: OSCReceiver = .system(store: OSCRoutesCoordinator.makeStore(routable: oscRoutable),
                                               routes: OSCRoutesCoordinator.initialRoutes(routable: oscRoutable, defaults: defaults))
        #if DEBUG
        let fakeOSC: OSCReceiver? = UITestFakeOSC.receiverIfRequested(store: oscReceiver.store, routable: oscRoutable, defaults: defaults)   // OSC-004
        let receiver: OSCReceiver = UITestOSCFailure.receiverIfRequested() ?? fakeOSC ?? oscReceiver
        let osc: OSCReceiverCoordinator = OSCReceiverCoordinator(settings: settings, receiver: receiver)
        #else
        let osc: OSCReceiverCoordinator = OSCReceiverCoordinator(settings: settings, receiver: oscReceiver)
        #endif
        osc.routes = OSCRoutesCoordinator(routable: oscRoutable, defaults: defaults) { [weak osc] (routes: [OSCRoute]) -> Void in
            osc?.setRoutes(routes)
        }
        return osc
    }

    /// UIX-015-R2: OSC already on means iOS has already asked for local network access, and so does a
    /// listener seen listening or denied.
    private static func makeExplainers(settings: AppSettings, osc: OSCReceiverCoordinator,
                                       defaults: UserDefaults) -> PermissionExplainerCoordinator {
        let explainers: PermissionExplainerCoordinator = PermissionExplainerCoordinator(defaults: defaults)
        if settings.oscEnabled { explainers.markExplained(.localNetwork) }
        osc.onLocalNetworkDecided = { [weak explainers] () -> Void in explainers?.markExplained(.localNetwork) }
        return explainers
    }

    /// MIDI-001 discovery, MIDI-002 input and monitor, MIDI-003 mappings, linked to each other.
    private struct MIDIStack {
        let discovery: MIDIDiscoveryCoordinator
        let input: MIDIInputCoordinator
        let monitor: MIDIMonitorCoordinator
        let mappings: MIDIMappingCoordinator
    }

    private static func makeMIDI(settings: AppSettings, defaults: UserDefaults, announcer: AccessibilityAnnouncer) -> MIDIStack {
        let midiAnnouncer: AccessibilityAnnouncer = announcer   // MIDI-001-R11: the shared path
        let announceMIDI: @MainActor (String) -> Void = { (text: String) -> Void in midiAnnouncer.announce(text, kind: .midi) }
        #if DEBUG
        let midi: MIDIDiscoveryCoordinator = MIDIDiscoveryCoordinator(
            settings: settings, discovery: UITestFakeMIDI.discoveryIfRequested() ?? .system(), announce: announceMIDI)
        let input: MIDIInputCoordinator = MIDIInputCoordinator(service: UITestFakeMIDI.inputServiceIfRequested() ?? .system(), discovery: midi)
        #else
        let midi: MIDIDiscoveryCoordinator = MIDIDiscoveryCoordinator(settings: settings, announce: announceMIDI)
        let input: MIDIInputCoordinator = MIDIInputCoordinator(service: .system(), discovery: midi)
        #endif
        let monitor: MIDIMonitorCoordinator = MIDIMonitorCoordinator(input: input, discovery: midi)
        midi.monitor = monitor   // MIDI-002-R15
        let mappings: MIDIMappingCoordinator = MIDIMappingCoordinator(
            registry: MIDIMappingCoordinator.visualRegistry(), applied: MIDIMappingCoordinator.appliedIDs, input: input,
            discovery: midi, defaults: defaults, announce: announceMIDI)
        midi.mappings = mappings   // MIDI-003-R10
        return MIDIStack(discovery: midi, input: input, monitor: monitor, mappings: mappings)
    }

    /// The imported media and overlay stores, created in the order `init` always used.
    private struct MediaStores {
        let photos: PhotoCoordinator
        let slideshow: SlideshowCoordinator
        let kenBurns: KenBurnsCoordinator
        let logo: LogoCoordinator
        let clock: ClockOverlayCoordinator
        let countdown: CountdownOverlayCoordinator
        let palettes: PaletteCoordinator
        let macros: MacroCoordinator
        let videos: VideoCoordinator
        let texts: TextOverlayCoordinator

        @MainActor
        init(defaults: UserDefaults, settings: AppSettings) {
            photos = PhotoCoordinator.makeDefault(defaults: defaults)
            slideshow = SlideshowCoordinator.makeDefault(defaults: defaults)   // MED-006
            kenBurns = KenBurnsCoordinator.makeDefault(defaults: defaults)   // MED-007
            logo = LogoCoordinator.makeDefault(defaults: defaults)   // MED-010
            clock = ClockOverlayCoordinator.makeForApp(defaults: defaults)   // MED-011
            countdown = CountdownOverlayCoordinator.makeForApp(defaults: defaults)   // MED-012
            palettes = PaletteCoordinator.makeDefault()   // UIX-011 (after FILE-005's pending restore and FILE-011's erase)
            macros = MacroCoordinator.makeDefault(settings: settings)   // MOD-010
            videos = VideoCoordinator.makeDefault(defaults: defaults)
            texts = TextOverlayCoordinator.makeDefault(defaults: defaults)
        }
    }

    /// SCN-002: holds the committed scene for PERF-010's offer, or restores it over the settings
    /// (in init: no method call on self yet).
    private static func restoreScene(from sceneAutosave: SceneAutosaveCoordinator?, holdsScene: Bool,
                                     recovery: SessionRecoveryCoordinator, settings: AppSettings,
                                     effects: EffectSettings, media: MediaStores, layers: LayerInspectorCoordinator) {
        let stored: StoredMediaAvailability = StoredMediaAvailability(photos: media.photos.knownIDs, videos: media.videos.knownIDs)   // FILE-008-R5
        if holdsScene {
            recovery.hold(recovery.decision.isCrashLoop ? nil : sceneAutosave?.holdCommittedScene(assets: stored))
            return
        }
        guard let values = sceneAutosave?.restore(assets: stored) else { return }
        SceneAutosaveCapture.apply(values, to: settings)
        effects.apply(values.effects)
        layers.restore(values.layerComposites)   // CMP-015-R5
        if let text = values.text { media.texts.spec = text }
        media.videos.restoreLoop(storeID: values.videoStoreID, loop: values.videoLoop)   // MED-003-R8
        media.videos.restoreSpeed(storeID: values.videoStoreID, speedPercent: values.videoSpeedPercent)   // MED-004-R7
        if let restore = values.slideshow {   // MED-006-R12, MED-007-R10
            media.slideshow.restore(restore.value)
            media.kenBurns.restore(restore.kenBurns)
        }
        if let scene = values.logo { media.logo.restore(storeID: scene.storeID, placement: scene.placement) }   // MED-010-R10
        media.macros.restore(values.macros)   // MOD-010: restored, not applied
        media.palettes.restore(values.paletteID)   // UIX-011
    }

    #if DEBUG
    /// The media pickers cannot be automated: UI tests seed the stores instead.
    private static func seedMediaFixtures(_ media: MediaStores) {
        UITestPhotoFixture.seedIfRequested(media.photos, slideshow: media.slideshow)   // MED-001, MED-006
        UITestVideoFixture.seedIfRequested(media.videos)   // MED-002: VideoLayerUITests
        UITestTextFixture.seedIfRequested(media.texts)     // MED-009: TextOverlayUITests
        UITestLogoFixture.seedIfRequested(media.logo)      // MED-010: LogoOverlayUITests
        UITestMacroFixture.seedIfRequested(media.macros)   // MOD-010: ParameterMacroUITests
        UITestPhotoLibrarySeed.shared.startIfRequested()   // QA-011: Photos picker fixtures (add-only)
        UITestDiskBallast.shared.startAtLaunch()   // QA-011 REC-015-T17: deletes an old ballast; fills when asked
    }
    #endif

    /// The capture manager over the three sources. Latency stages (T062, T114); the analysis tap
    /// feeds the native visual's bands (VIS-001-R14); AUD-015-R3 background configuration.
    #if DEBUG
    private static func makeManager(microphone: MicrophoneSource,
                                    inAppPlayback: InAppPlaybackSource) -> (manager: CaptureManager, fakes: [UITestFakeSource]) {
        var sources: [any AudioSource] = [ScreenCaptureSource.makeDefault(), microphone, inAppPlayback]
        // StatusUITests (T093): a scriptable fake replaces one mode's real source.
        let fakes: [UITestFakeSource] = UITestFakeSource.fromLaunchArguments()   // AUD-012: one or more modes
        for fake in fakes {
            sources.removeAll { (source: any AudioSource) -> Bool in source.mode == fake.mode }
            sources.append(fake)
        }
        return (manager: makeManager(sources: sources), fakes: fakes)
    }
    #else
    private static func makeManager(microphone: MicrophoneSource, inAppPlayback: InAppPlaybackSource) -> CaptureManager {
        makeManager(sources: [ScreenCaptureSource.makeDefault(), microphone, inAppPlayback])
    }
    #endif

    private static func makeManager(sources: [any AudioSource]) -> CaptureManager {
        let manager: CaptureManager = CaptureManager(sources: sources, signposts: DiagnosticsLog.pipeline,
                                                     analysisTapCapacityFrames: NormalizedPCMRing.analysisTapDefaultCapacityFrames)
        manager.backgroundConfiguration = backgroundConfiguration(infoDictionary: Bundle.main.infoDictionary)   // AUD-015-R3
        return manager
    }

    /// SHOW-011: tap tempo on the monotonic clock.
    private static func makeTempo(defaults: UserDefaults) -> TempoCoordinator {
        var tempoClock: () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() }
        #if DEBUG
        // TapTempoUITests: `-uitestTapInterval <ms>` spaces every tap exactly (SHOW-011 research D6).
        if let step = defaults.string(forKey: "uitestTapInterval").flatMap(Double.init) {
            tempoClock = TempoCoordinator.syntheticClock(stepMilliseconds: step)
        }
        #endif
        return TempoCoordinator(clock: tempoClock)
    }

    #if DEBUG
    /// TempoConfidenceUITests: `-uitestTempoEstimate <bpm>:<confidence>[:<polls>:<confidence2>]` (ANL-006 D7).
    private static func applyTempoScript(to tempo: TempoCoordinator, defaults: UserDefaults) {
        if let script = defaults.string(forKey: "uitestTempoEstimate").flatMap(TempoCoordinator.estimateScript) {
            tempo.estimateScript = script
        }
    }
    #endif

    /// Feature 002's preset coordinator with PRE-006 recents, PRE-012 user presets, PRE-016 overrides
    /// and PRE-018 integrity, connected in the order `init` always used.
    private struct PresetStack {
        let presets: PresetCoordinator
        let userPresets: UserPresetsCoordinator
    }

    private static func makePresetStack(defaults: UserDefaults, settings: AppSettings, loader: RendererPresetLoader) -> PresetStack {
        let presets: PresetCoordinator = makePresets(defaults: defaults, settings: settings, loader: loader)
        presets.recent = makeRecentPresets(defaults: defaults)   // PRE-006
        let userPresets: UserPresetsCoordinator = makeUserPresets(presets: presets, loader: loader)
        return PresetStack(presets: presets, userPresets: userPresets)
    }

    /// PRE-012 user presets, then PRE-016 overrides on the coordinator, then PRE-018 integrity.
    private static func makeUserPresets(presets: PresetCoordinator, loader: RendererPresetLoader) -> UserPresetsCoordinator {
        let userPresets: UserPresetsCoordinator = UserPresetsCoordinator.makeDefault()
        userPresets.connect(presets: presets, loader: loader)   // PRE-012
        let overrides: PresetOverridesCoordinator = makeOverrides(presets: presets, loader: loader)
        presets.overrides = overrides   // PRE-016
        let integrity: LibraryIntegrityCoordinator = LibraryIntegrityCoordinator(presets: presets, userPresets: userPresets)
        userPresets.integrity = integrity   // PRE-018
        return userPresets
    }

    /// The full-library purchase (feature 002 US2): StoreKit, or a fixed fake in tests and device runs.
    private static func makeEntitlements() -> any EntitlementProviding {
        #if DEBUG || PROJECTM_AUTOMATION
        return AutomationRunner.entitlementsOverride() ?? FakeEntitlements.fromLaunchArguments() ?? LibraryStore()
        #else
        return LibraryStore()
        #endif
    }

    /// Background/foreground/lock/unlock go through LifecycleCoordinator (T099): it suspends the
    /// visualization and forwards to CaptureManager's per-adapter matrix (first step after every
    /// stored property is set).
    private func connectLifecycle(_ lifecycle: LifecycleObserver) {
        presentation.register(tempo)   // SHOW-011: the tempo analysis stops with the presentation
        presentation.onTransition = { (report: PresentationTransitionReport) -> Void in
            DiagnosticsLog.presentationTransition(canPresent: report.canPresent, registered: report.registered,
                                                  activeBefore: report.activeBefore, activeAfter: report.activeAfter)
        }
        let lifecycleCoordinator: LifecycleCoordinator = LifecycleCoordinator(manager: manager, visualization: self,
                                                                              presentation: presentation)
        self.lifecycleCoordinator = lifecycleCoordinator
        lifecycleForwarding = Task { @MainActor in
            for await event in lifecycle.events { await lifecycleCoordinator.handle(event) }
        }
    }

    /// The preset coordinator with its stores in `Application Support/PresetCollections` (split from `init` for the
    /// type-check budget).
    private static func makePresets(defaults: UserDefaults, settings: AppSettings, loader: any PresetLoading) -> PresetCoordinator {
        PresetCoordinator(store: FavoritesStore(defaults: defaults), settings: settings, loader: loader,
                          collections: PresetCollectionStore(directory: PresetCollectionStore.defaultDirectory()),
                          tags: PresetTagStore(directory: PresetTagStore.defaultDirectory()),   // PRE-003
                          smart: PresetSmartCollectionStore(directory: PresetSmartCollectionStore.defaultDirectory()),   // PRE-008
                          notes: PresetNoteStore(directory: PresetNoteStore.defaultDirectory()))   // PRE-011
    }

    /// PRE-016: the overrides store (beside the tags, so `-uitestResetNotice` removes it), handed to the
    /// loader (applied on load) and to the coordinator (the Adjust Parameters sheet).
    private static func makeOverrides(presets: PresetCoordinator, loader: RendererPresetLoader) -> PresetOverridesCoordinator {
        let store = PresetOverrideStore(directory: PresetOverrideStore.defaultDirectory())
        loader.overrides = store
        return PresetOverridesCoordinator(store: store, presets: presets) { [weak loader] (preset: IndexedPreset) async throws -> Data in
            guard let loader else { throw CocoaError(.featureUnsupported) }
            return try await loader.originalData(for: preset)
        }
    }

    /// `-uitestResetNotice`: UI tests start from a clean library and settings.
    /// OSC-003-R5: one live-value path for MIDI and OSC into the native host (then MOD-002 and ACC-012's clamp).
    func pushLiveValues(_ source: ExternalLiveValues.Source, _ values: [ParameterID: Double]) {
        externalLiveValues.update(source, values)
        nativeVisual?.externalValues = hostExternalValues
    }

    /// (Split into steps for the type-check budget; the keys and files are removed in the same order.)
    private static func resetForUITests(_ defaults: UserDefaults) {
        resetAppKeysForUITests(defaults)
        resetEffectKeysForUITests(defaults)
        resetControlKeysForUITests(defaults)
        resetFilesForUITests(defaults)
    }

    /// The notice, presets, settings and audio analysis keys.
    private static func resetAppKeysForUITests(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: Self.noticeKey)
        defaults.removeObject(forKey: FavoritesStore.favoritesKey)
        defaults.removeObject(forKey: FavoritesStore.lastPresetKey)
        RecentPresetsStore.allKeys.forEach(defaults.removeObject(forKey:))   // PRE-006: no history, switch off (the default)
        AppSettings.allKeys.forEach(defaults.removeObject(forKey:))
        defaults.removeObject(forKey: InputTrimSetting.decibelsKey)   // AUD-008: 0 dB
        defaults.removeObject(forKey: ChannelSelectionSetting.modeKey)   // AUD-009: Mix
        defaults.removeObject(forKey: PlaybackBalanceSetting.positionKey)   // AUD-010: centred
        defaults.removeObject(forKey: NoiseGateSetting.enabledKey)   // AUD-011: off
        defaults.removeObject(forKey: NoiseGateSetting.thresholdKey)   // AUD-011: −50 dBFS
        defaults.removeObject(forKey: RecordingAudioSetting.includeMicrophoneKey)   // REC-004: off
        defaults.removeObject(forKey: ParameterShelf.pinsKey)   // UIX-004: no pins
        LatencyOffsetSetting.allKeys.forEach(defaults.removeObject(forKey:))   // AUD-013: 0 ms
    }

    /// FX-003 to FX-020, the camera trackers and the noise editor.
    private static func resetEffectKeysForUITests(_ defaults: UserDefaults) {
        ColorGradeSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-003: neutral
        MotionFeedbackSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-009: Trails off
        FaceTrackingCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // CAM-009: off, no consent
        HandTrackingCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // CAM-010: off, no consent
        NoiseEditorStore.allKeys.forEach(defaults.removeObject(forKey:))   // SHD-006: noise defaults
        EffectChainSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-020: standard order, no presets
        ChromaticSplitSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-006: off
        DirectionalBlurSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-007: off
        RadialBlurSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-008: off
        EchoSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-010: off
        MosaicSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-012: off
        EdgeOutlineSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-014: off
        LensDistortionSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-016: off
        VignetteSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-015: off
        PixelSortSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-011: off
        ScanlinesSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-018: off
        FilmGrainSetting.allKeys.forEach(defaults.removeObject(forKey:))   // FX-017: off
    }

    /// MIDI and OSC.
    private static func resetControlKeysForUITests(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: MIDIMappingCoordinator.mappingsKey)   // MIDI-003: no mappings
        MIDIClockCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // MIDI-010: not following
        OSCRoutesCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // OSC-003: every route on, no aliases
        OSCPeersCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // OSC-008: allowlist off, nobody approved
        OSCSendCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // OSC-005: Send OSC off, no destination
        OSCDiscoveryCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // OSC-011: discovery off
        OSCCueSyncCoordinator.allKeys.forEach(defaults.removeObject(forKey:))   // OSC-012: cue sync off
    }

    /// The stored folders (presets, media, scenes, shows, palettes) and the first-launch states.
    private static func resetFilesForUITests(_ defaults: UserDefaults) {
        if let profiles = try? MIDIProfilesCoordinator.defaultDirectory() { try? FileManager.default.removeItem(at: profiles) }   // MIDI-012: no profiles
        try? FileManager.default.removeItem(at: PresetCollectionStore.defaultDirectory())   // PRE-007: UI tests start without collections
        try? FileManager.default.removeItem(at: UserPresetStore.defaultDirectory())         // PRE-012: and without imported presets
        #if DEBUG
        // LibraryCheckUITests (PRE-018): the broken files are written right after the reset, in `init`, before anything
        // can open the user preset store (the renderer's pending-trial run may open it before the library task).
        UITestBrokenLibraryFixture.seedFilesIfRequested()
        UITestPresetVersionsFixture.seedIfRequested()   // PRE-017: a preset with one earlier version
        #endif
        if let photos = try? PhotoStore.defaultDirectory() { try? FileManager.default.removeItem(at: photos) }   // MED-001: no photo
        if let videos = try? VideoStore.defaultDirectory() { try? FileManager.default.removeItem(at: videos) }   // MED-002: no video
        if let scenes = try? SceneAutosaveStore.defaultDirectory() { try? FileManager.default.removeItem(at: scenes) }   // SCN-002: no scene
        SessionRecoveryCoordinator.reset(defaults)   // PERF-010: no previous session
        GuidedFirstSceneCoordinator.reset(defaults)  // UIX-001: never offered
        PermissionExplainerCoordinator.reset(defaults)   // UIX-015: nothing explained
        if let shows = try? ShowStore.defaultDirectory() { try? FileManager.default.removeItem(at: shows) }   // SHOW-001: no show
        if let palettes = try? PaletteStore.defaultDirectory() { try? FileManager.default.removeItem(at: palettes) }   // UIX-011: no palettes
    }

    /// The end of init, after every stored property is set: callbacks, observers and the first loads.
    private func connectAfterInit(defaults: UserDefaults) {
        midiMappings.profiles = MIDIProfilesCoordinator.makeDefault(mappings: midiMappings)   // MIDI-012
        _ = hapticBeat   // ACC-007-R7: a stored "on" installs the tempo observer before any visual starts
        osc.peers = OSCPeersCoordinator(allowlist: osc.peerAllowlist, defaults: defaults)   // OSC-008 (outside init: type-check budget)
        osc.sender = OSCSendCoordinator(osc: osc, defaults: defaults) { [weak self] () -> (anchor: UInt64, period: UInt64)? in   // OSC-005
            guard let snapshot = self?.tempo.snapshot, let anchor = snapshot.anchorNanoseconds, let period = snapshot.periodNanoseconds else { return nil }
            return (anchor: anchor, period: period)
        }
        osc.discovery = OSCDiscoveryCoordinator(osc: osc, defaults: defaults)   // OSC-011: Nearby Devices
        if let routes = osc.routes {   // OSC-004: learn on OSC Routes, announced on the .osc lane
            let announcer: AccessibilityAnnouncer = statusEvents.announcer
            osc.learn = OSCLearnCoordinator(osc: osc, routes: routes) { (text: String) -> Void in announcer.announce(text, kind: .osc) }
        }
        photos.onPhotoChange = { [weak self] (_: StoredPhoto?) in self?.refreshPhotoContent() }   // MED-006: the slideshow wins when on
        connectSlideshow()   // MED-006
        connectLogo()   // MED-010
        connectPalettes()   // UIX-011
        videos.onVideoChange = { [weak self] (stored: StoredVideo?) in
            guard let self, let host = videoVisual else { return }
            host.content = .none   // MED-003: the new video's region applies from its first picture
            host.loopRegion = videos.loopRegion
            host.playbackSpeed = videos.speed   // MED-004
            host.reverse = videos.reverse   // MED-005
            host.content = Self.videoContent(stored)
        }
        videos.onLoopRegionChange = { [weak self] (region: VideoLoopRegion?) in self?.videoVisual?.loopRegion = region }   // MED-003
        videos.onSpeedChange = { [weak self] (speed: VideoPlaybackSpeed) in self?.videoVisual?.playbackSpeed = speed }   // MED-004
        videos.onReverseChange = { [weak self] (on: Bool) in self?.videoVisual?.reverse = on }   // MED-005
        texts.onSpecChange = { [weak self] (spec: TextOverlaySpec) in self?.textVisual?.spec = spec }   // MED-009
        colorGrade.onChange = { [weak self] (_: ColorGrade) in self?.applyColorGrade() }   // FX-003
        connectMotionFeedback()   // FX-009
        connectEffectChain()   // FX-020
        connectChromaticSplit()   // FX-006
        connectDirectionalBlur()   // FX-007
        connectRadialBlur()   // FX-008
        connectEcho()   // FX-010
        connectMosaic()   // FX-012
        connectEdgeOutline()   // FX-014
        connectLensDistortion()   // FX-016
        connectVignette()   // FX-015
        connectPixelSort()   // FX-011
        connectScanlines()   // FX-018
        connectFilmGrain()   // FX-017
        routes.context = { [weak self] in self?.routeContext }   // AUD-007
        // AUD-012-R12: the noise gate's microphone flag changes when a session (or a switch) begins.
        manager.onSessionMode = { [weak self] (mode: AudioSourceMode) in
            self?.noiseGate.control.isMicrophoneSource = mode == .microphone
            self?.latencyOffset.activeMode = mode   // AUD-013-R8: the new session's delay
        }
        routes.isActive = { [weak self] in self?.appIsActive ?? true }
        self.memoryPressure.register(presetLoader)   // PERF-006-R11: the archive's decompressed chunk
        presets.thumbnails = Self.makeThumbnails(loader: presetLoader, renderer: { [weak self] in self?.renderer })   // PRE-001
        presets.comparison = makeComparison(loader: presetLoader)   // PRE-009
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
        presetLoader.prewarmScheduler = mediaPrewarm.scheduler   // PERF-005-R8: preset picks pass through unchanged
        connectMediaPrewarm()   // PERF-005
        connectScenePacks(defaults: defaults)   // SCN-014
        connectMissingMedia(defaults: defaults)   // MED-013 (and its DEBUG seed)
        connectLayerInspector()   // CMP-015
        #if DEBUG
        UITestLayerInspectorFixture.seedIfRequested(self)   // CMP-015: LayerInspectorUITests (before the history starts)
        #endif
        connectModulationMatrix()   // MOD-012 (and its DEBUG seed; before the history starts)
        connectSceneHistory()   // SCN-010: starts from the restored (or fresh) scene
        connectSceneSnapshots()   // SCN-008
        connectSceneLock()   // SCN-015
        connectSceneCompare()   // SCN-009 (after the snapshots, the history and the lock)
        connectSnapshotBatch()   // REC-002 (after the snapshots and Compare)
        connectOfflineExport()   // REC-013
        connectParameterQuantizer()   // MOD-017
        midiMappings.applyValues = { [weak self] (values: [ParameterID: Double]) -> Void in self?.pushLiveValues(.midi, values) }   // MIDI-003-R8
        connectMIDIFeedback()   // MIDI-009
        osc.applyLiveValues = { [weak self] (values: [ParameterID: Double]) -> Void in self?.pushLiveValues(.osc, values) }   // OSC-003-R5
        osc.cueSync = OSCCueSyncCoordinator(osc: osc, show: show, defaults: defaults)   // OSC-012 (after connectShow: chains cueStarted)
        #if DEBUG
        UITestShowFixture.seedIfRequested(self)   // SHOW-001: ShowCueUITests
        #endif
        connectStatusEvents()   // ACC-011
        connectExternalDisplay()   // OUT-002
        libraryBackup.announce = { [weak self] (text: String) in self?.announcer.announce(text, kind: .library) }   // FILE-005-R12
        countdown.announce = { [weak self] (text: String) in self?.announcer.announce(text, kind: .countdown) }   // MED-012-R4
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
            // QA-011: with `-uitestPlayImported YES` the import hook plays the first imported track from the chooser.
            if !defaults.bool(forKey: "uitestPlayImported") {
                Task { @MainActor in
                    if mode == .inAppPlayback { self.prepareReferenceTrack() }
                    self.start(mode)
                }
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
            // QA-011 device acceptance: a path without a leading "/" is relative to Documents (a fixture copied
            // there with devicectl), and `-uitestPlayImported YES` then plays the first imported track.
            await UITestAudioProbes.prepare()   // QA-011 audio device tests: fixtures and probes before the import
            if let paths = defaults.string(forKey: "uitestImportAudio") {
                for path in paths.split(separator: "|") {
                    let raw = String(path)
                    let url: URL = raw.hasPrefix("/") ? URL(fileURLWithPath: raw)
                        : URL.documentsDirectory.appendingPathComponent(raw)
                    let started = Date()
                    await audioLibrary.importPicked(.success([url]))
                    UITestAudioProbes.noteImport(raw, milliseconds: Date().timeIntervalSince(started) * 1000)   // AUD-001-S1
                }
            }
            // The track this launch imported first (by its file name): the library persists between launches, so its
            // first track can be an earlier fixture (D1 played the left-only fixture for the inverted-phase test).
            if defaults.bool(forKey: "uitestPlayImported") {
                let wanted: String? = defaults.string(forKey: "uitestImportAudio")?.split(separator: "|").first
                    .map { (path: Substring) -> String in URL(fileURLWithPath: String(path)).lastPathComponent }
                if let track = audioLibrary.tracks.first(where: { $0.originalFileName == wanted }) ?? audioLibrary.tracks.first {
                    play(track)
                }
            }
            runVisualCycleIfRequested()
            runAutoRecordIfRequested()
            UITestEncoderProbe.shared.startIfRequested()
            #endif
        }
    }

    #if DEBUG
    /// QA-011 PERF-004-T14/T15: `-uitestCycleVisuals <n>` switches Camera → Photo → Circular Spectrum n times (0.4 s
    /// apart) and records `MTLDevice.currentAllocatedSize` after every full cycle in `visualCycleProbe`
    /// ("switches=<n> mb=<first>,<…>,<last> done=<0|1>"), so a device test reads whether GPU memory plateaus.
    private(set) var visualCycleProbe = "idle"

    /// QA-011 REC-003-T23 diagnosis: `-uitestAutoRecordSeconds <n>` starts a recording 4 s after launch and stops it
    /// n s later, so Instruments can trace a recording it launched (`xctrace --launch`; no taps needed).
    private func runAutoRecordIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-uitestAutoRecordSeconds"), i + 1 < arguments.count,
              let seconds = Double(arguments[i + 1]), seconds > 0 else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.videoRecording.toggle()
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            self?.videoRecording.toggle()
        }
    }

    private func runVisualCycleIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-uitestCycleVisuals"), i + 1 < arguments.count,
              let count = Int(arguments[i + 1]), count > 0 else { return }
        let sequence: [VisualChoice] = [.camera, .photo, .circularSpectrum]
        let device = MTLCreateSystemDefaultDevice()
        Task { @MainActor in
            var megabytes: [Int] = []
            for n in 0..<count {
                settings.visual = sequence[n % sequence.count]
                try? await Task.sleep(for: .milliseconds(400))
                if n % sequence.count == sequence.count - 1 {
                    megabytes.append(Int((device?.currentAllocatedSize ?? 0) / 1_048_576))
                }
                visualCycleProbe = "switches=\(n + 1) mb=\(megabytes.map(String.init).joined(separator: ",")) done=0"
            }
            visualCycleProbe = "switches=\(count) mb=\(megabytes.map(String.init).joined(separator: ",")) done=1"
        }
    }
    #endif

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
        osc.sender?.post(.status(.started))   // OSC-005-R6
        Task { await manager.select(mode) }
    }

    /// AUD-012-R1: the modes "Switch Source" offers: available on this device, not the current one.
    /// AUD-010: what is heard only; the stored balance applies from the first session on. A static
    /// helper keeps the initializer's type-check time down.
    private static func connect(_ balance: PlaybackBalanceSetting, to source: InAppPlaybackSource) {
        source.monitorBalance = balance.position
        balance.onChange = { (value: Double) -> Void in source.monitorBalance = value }
    }

    /// AUD-010-R6: the balance is enabled only while In-App Playback is the source.
    var playbackBalanceAvailable: Bool { PlaybackBalanceSetting.isAvailable(for: manager.activeMode) }

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
                                   switching: manager.switchingTo != nil, phaseWarning: stereoPhase.isRaised)   // ANL-013
    }

    /// Stop (FR-007): stops the source and returns to the chooser.
    func stop() {
        videoRecording.cancelCountdown(.leftVisualizer)   // REC-007-R5
        noiseGate.control.isMicrophoneSource = false   // AUD-011-R3
        latencyOffset.activeMode = nil   // AUD-013-R8
        hideTask?.cancel()
        pauseActiveVisual()
        screen = .chooser
        lifecycleCoordinator.visualizationEnded()
        updateIdleTimer()
        osc.sender?.post(.status(.stopped))   // OSC-005-R6
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
        EngineInstanceLedger.renderers += 1   // UIX-008-D9
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
                await UITestAudioProbes.seedBeforePresetImport()   // QA-011 PRE-015-T26: the seed exists before the import
                // QA-011 B07: `fixture:strobe` (written in the app) or a path relative to Documents on a device.
                await userPresets.importPicked(.success(UITestVisualProbes.presetImportURL(path)))
            }
            // PresetArchiveImportUITests (FILE-003): previews a fixture archive after the trials ran.
            if defaults.bool(forKey: "uitestPresetArchiveFixture") { await userPresets.previewFixtureArchive() }
            // PresetArchiveConflictUITests (FILE-004): the same with one name conflict.
            if defaults.bool(forKey: "uitestPresetArchiveConflictFixture") { await userPresets.previewFixtureArchive(conflict: true) }
            // BulkPresetImportUITests (PRE-013): `-uitestBulkImportFolder <path>` imports that folder as if picked.
            if let path = defaults.string(forKey: "uitestBulkImportFolder") { await userPresets.bulk.start(.folder(URL(fileURLWithPath: path))) }
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
                #if DEBUG || PROJECTM_AUTOMATION
                AutomationRunner.prepareWarmStart(warmStart)   // PERF-009 perf009: a cold launch clears the cache first
                #endif
                warmStart.openPipelineArchive()   // PERF-009: off the main actor
                async let loaded = warmStart.loadLibrary()   // PERF-009: through the warm cache
                await entitlements.start()
                let library = try await loaded
                presetLoader.library = library
                // PRE-012: the imported presets are read first (a preset that ended the last launch
                // is quarantined there), so the library never lists one that must not play.
                await userPresets.load()
                await userPresets.prepare(library: library, bundle: .main)
                presets.attach(library)
                #if DEBUG
                UITestBrokenLibraryFixture.seedReferencesIfRequested(presets)
                UITestCollectionFixture.seedIfRequested(presets)   // PresetCollectionsUITests
                UITestPresetTagFixture.seedIfRequested(presets)    // PresetTagsUITests (PRE-003)
                #endif
                presets.onScopeChange { UIAccessibility.post(notification: .announcement, argument: $0) }   // FR-124
                presets.announceFavorite = { [weak self] (text: String) in self?.announcer.announce(text, kind: .favorite) }   // ACC-004
                userPresets.announceLibrary = { [weak self] (text: String) in self?.announcer.announce(text, kind: .library) }   // FILE-003-R13
                presets.announceLibrary = { [weak self] (text: String) in self?.announcer.announce(text, kind: .library) }   // PRE-003-R12
                userPresets.integrity?.announce = { [weak self] (text: String) in self?.announcer.announce(text, kind: .library) }   // PRE-018-R12
                presets.recent?.announce = { [weak self] (text: String) in self?.announcer.announce(text, kind: .library) }   // PRE-006-R6
                presets.announceSearch = { [weak self] (text: String) in self?.announcer.announce(text, kind: .search) }
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
    /// ACC-012-R4, R5, R7: and the sensory safety clamp: the effective Reduce flashing (the setting, or a
    /// profile stricter than Standard) and the profile's envelope reach every renderer; native glow is
    /// capped where it is resolved. Standard leaves every renderer on today's path (ADR-0049).
    func applyReduceFlashing() {
        let clamp: SafetyClamp = settings.safetyClamp
        let reduce: Bool = clamp.reducesFlashing
        let compositors: [Compositor] = [cameraVisual?.compositor, photoVisual?.compositor, videoVisual?.compositor,
                                         textVisual?.compositor].compactMap { (c: Compositor?) -> Compositor? in c }
        Self.applySafety(clamp, renderer: renderer, native: nativeVisual, compositors: compositors)
        cameraVisual?.reduceFlashing = reduce   // CAM-001: the composite flash guard
        photoVisual?.reduceFlashing = reduce    // MED-001
        externalDisplay.reduceFlashing = reduce // OUT-010-R6: the restore fade's length
        videoVisual?.reduceFlashing = reduce    // MED-002
        textVisual?.reduceFlashing = reduce     // MED-009
        applyColorGrade()                       // FX-003: the profile's gain cap
        applyMotionFeedback()                   // FX-009: the profile's and Reduce flashing's length caps
        applyEcho()                             // FX-010: the profile's and Reduce flashing's weight caps
        applyEdgeOutline()                      // FX-014: the profile's colour scale
    }

    /// ACC-012-R4, R5: hands one clamp to every frame resolver (projectM's envelope pass, the native host's
    /// glow and frame context, the compositors' final flash guards). Tests call it with real renderers.
    static func applySafety(_ clamp: SafetyClamp, renderer: (any VisualizerRenderer)?, native: NativeSpectrumHost?,
                            compositors: [Compositor]) {
        let limits: FlashEnvelopeConfiguration? = clamp.flashLimitsOverride
        renderer?.reduceFlashing = clamp.reducesFlashing
        (renderer as? ANGLERenderer)?.flashLimits = limits   // projectM's envelope pass
        (renderer as? GLESRenderer)?.flashLimits = limits    // the fallback renderer's pass
        native?.reduceFlashing = clamp.reducesFlashing       // VIS-001-R10
        native?.safetyClamp = clamp                          // glow cap and the generators' envelope
        for compositor in compositors { compositor.flashLimits = limits }
    }

    /// FX-003-R1: the compositor-backed visuals show the colour grade (the native spectra and projectM are not graded),
    /// with ACC-012's intensity limit on gain (research FX-003-D10).
    func applyColorGrade() {
        let grade: ColorGrade = colorGrade.effectiveGrade(clamp: settings.safetyClamp)
        cameraVisual?.colorGrade = grade
        photoVisual?.colorGrade = grade
        videoVisual?.colorGrade = grade
        textVisual?.colorGrade = grade
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

    /// The native visual the settings ask for (VIS-002-R11, VIS-003-R10, VIS-004-R11; circular for any other choice).
    private var nativeSpectrumStyle: NativeSpectrumStyle {
        switch settings.visual {
        case .linearSpectrum: .linear(settings.linearSpectrumOrientation, spacing: settings.linearSpectrumSpacing)
        case .oscilloscope: .oscilloscope(line: settings.oscilloscopeLine, windowMilliseconds: settings.oscilloscopeWindowMilliseconds)
        case .lissajous: .lissajous(mode: settings.lissajousMode, persistence: settings.lissajousPersistence)   // VIS-004
        case .radialWaveform: .radialWaveform(ring: settings.radialWaveformRing, amplitude: settings.radialWaveformAmplitude)   // VIS-005
        case .beatRings: .beatRings(life: settings.beatRingsLife)   // VIS-006
        case .mandala: .mandala(symmetry: settings.mandalaSymmetry, mirror: settings.mandalaMirror, petal: settings.mandalaPetal)   // VIS-007
        case .particleFountain: .particleFountain(gravity: settings.particleGravity, emitter: settings.particleEmitter.effective)   // VIS-008, SHD-007
        case .particleOrbit: .particleOrbit(radius: settings.particleOrbitRadius)   // VIS-009
        case .noiseField: .noiseField(frequency: settings.noiseFieldFrequency, octaves: settings.noiseFieldOctaves, seed: settings.noiseFieldSeed)   // VIS-013
        case .kaleidoscope: .kaleidoscope(wedges: settings.kaleidoscopeWedges)   // VIS-014
        case .tunnel: .tunnel(pace: settings.tunnelPace)   // VIS-015
        case .spectrumWaterfall: .waterfall   // VIS-020
        case .fluidInk: .fluidInk   // VIS-011
        case .reactionDiffusion: .reactionDiffusion(settings.reactionDiffusion)   // VIS-012
        case .starfield: .starfield(speed: settings.starfieldSpeed, density: settings.starfieldDensity)   // VIS-016
        case .signedDistance: .signedDistance(quality: settings.signedDistanceQuality)   // VIS-017
        case .cymatic: .cymatic(bands: settings.cymaticBands)   // VIS-019
        case .tessellation: .tessellation(settings.tessellation)   // VIS-018
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
            host.reduceFlashing = settings.effectiveReduceFlashing   // ACC-012-R7
            host.safetyClamp = settings.safetyClamp   // ACC-012-R4
            host.smoothing = settings.spectrumSmoothing   // ANL-003
            host.palette = effectiveSpectrumPalette        // ACC-003-R13, UIX-011
            host.particleTrails = settings.particleTrails   // VIS-010
            host.reduceMotion = settings.systemReduceMotion   // VIS-007-R5, VIS-008-R9, VIS-009-R9: the mandala's turn, the fountain's bursts, the orbit (ACC-001)
            host.externalValues = hostExternalValues   // MIDI-003, OSC-003, SHOW-008: values held while no native visual was shown
            for binding in sceneAutosave?.bindings ?? [] { try? host.addLayer(binding) }   // SCN-002: restored bindings, MOD-011 layers in order
            connectThresholdTriggers(host)   // MOD-006
            connectLFOs(host)   // MOD-007
            connectMotion(host)   // CAM-011
            faceTracking.connect(native: host)   // CAM-009
            handTracking.connect(native: host)   // CAM-010
            connectStereoPhase(host)   // ANL-013
            #if DEBUG
            bindGlowToLevelIfRequested(host)   // MOD-002: AudioFeatureBindingUITests
            #endif
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            nativeVisual = host
            modulationMatrix.refresh()   // MOD-012: the host's list is now the live one
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
                                                 crop: settings.cameraCrop,   // CAM-007
                                                 lens: cameraLensInventory.resolve(settings.cameraLens), lenses: cameraLensInventory,   // CAM-003
                                                 personMask: settings.cameraPersonMask)   // CAM-008
            host.reduceFlashing = settings.effectiveReduceFlashing   // ACC-012-R7
            host.compositor.flashLimits = settings.safetyClamp.flashLimitsOverride   // ACC-012-R5
            host.colorGrade = colorGrade.effectiveGrade(clamp: settings.safetyClamp)   // FX-003, ACC-012 gain cap
            host.compositor.motionFeedback = effectiveMotionFeedback   // FX-009, ACC-012 length cap
            host.compositor.outputEffectOrder = effectChain.order   // FX-020
            host.compositor.chromaticSplit = chromaticSplit.split   // FX-006
            host.compositor.directionalBlur = directionalBlur.blur   // FX-007
            host.compositor.radialBlur = radialBlur.blur   // FX-008
            host.compositor.echoFeedback = effectiveEcho   // FX-010, ACC-012 weight cap
            host.compositor.mosaic = mosaic.mosaic   // FX-012
            host.compositor.edgeOutline = effectiveEdgeOutline   // FX-014, ACC-012 colour scale
            host.compositor.lensDistortion = lensDistortion.lens   // FX-016
            host.compositor.vignette = vignette.vignette   // FX-015
            host.compositor.pixelSort = pixelSort.sort   // FX-011
            host.compositor.scanlines = scanlines.scanlines   // FX-018
            host.compositor.filmGrain = effectiveFilmGrain   // FX-017 (static under Reduce Motion)
            host.onRenderHealthChange = observeRenderHealth(of: "camera")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onFeedStateChange = { [weak self] state in self?.cameraStateChanged(state) }
            host.onExposureChange = { [weak self] (state: CameraExposureState) -> Void in self?.cameraExposure = state }   // CAM-004
            cameraExposure = host.cameraExposure
            host.onFocusChange = { [weak self] (state: CameraFocusState) -> Void in self?.cameraFocus = state }   // CAM-005
            cameraFocus = host.cameraFocus
            host.onWhiteBalanceChange = { [weak self] (state: CameraWhiteBalanceState) -> Void in self?.cameraWhiteBalance = state }   // CAM-006
            cameraWhiteBalance = host.cameraWhiteBalance
            observePersonMask(of: host)   // CAM-008
            connectCameraAnalysis(host)   // CAM-009, CAM-010: the same pictures, only behind each consent gate; the ring's bindings
            host.onRecoveryChange = { [weak self, weak host] () -> Void in   // CAM-013
                self?.cameraRetryPending = host?.retryPending ?? false
            }
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            cameraVisual = host
            logo.attach(to: host.compositor)   // MED-010-R5: the logo is the top layer
            clock.attach(to: host.compositor)   // MED-011-R6: the clock above the logo
            countdown.attach(to: host.compositor)   // MED-012-R7: the countdown above the clock
            cameraNoticeDismissed = false   // UIX-015-R7: a new attempt
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
            host.reduceFlashing = settings.effectiveReduceFlashing   // ACC-012-R7
            host.compositor.flashLimits = settings.safetyClamp.flashLimitsOverride   // ACC-012-R5
            host.colorGrade = colorGrade.effectiveGrade(clamp: settings.safetyClamp)   // FX-003, ACC-012 gain cap
            host.compositor.motionFeedback = effectiveMotionFeedback   // FX-009, ACC-012 length cap
            host.compositor.outputEffectOrder = effectChain.order   // FX-020
            host.compositor.chromaticSplit = chromaticSplit.split   // FX-006
            host.compositor.directionalBlur = directionalBlur.blur   // FX-007
            host.compositor.radialBlur = radialBlur.blur   // FX-008
            host.compositor.echoFeedback = effectiveEcho   // FX-010, ACC-012 weight cap
            host.compositor.mosaic = mosaic.mosaic   // FX-012
            host.compositor.edgeOutline = effectiveEdgeOutline   // FX-014, ACC-012 colour scale
            host.compositor.lensDistortion = lensDistortion.lens   // FX-016
            host.compositor.vignette = vignette.vignette   // FX-015
            host.compositor.pixelSort = pixelSort.sort   // FX-011
            host.compositor.scanlines = scanlines.scanlines   // FX-018
            host.compositor.filmGrain = effectiveFilmGrain   // FX-017 (static under Reduce Motion)
            host.onRenderHealthChange = observeRenderHealth(of: "photo")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onImageStateChange = { [weak self] (state: ImageLayerState) in self?.photoStateChanged(state) }
            slideshow.restartPlayback()   // MED-006: from the first slide
            host.beforeFrame = { [weak self] () -> Void in self?.slideshowTick() }
            mediaPrewarm.attach(host.photo)   // PERF-005-R11: a prewarmed picture is adopted, not decoded again
            host.content = photoLayerContent
            if let next = slideshow.nextURL { host.preload(next) }
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            photoVisual = host
            applyKenBurns()   // MED-007
            applyLayerState(to: host.compositor)   // CMP-015
            logo.attach(to: host.compositor)   // MED-010-R5: the logo is the top layer
            clock.attach(to: host.compositor)   // MED-011-R6: the clock above the logo
            countdown.attach(to: host.compositor)   // MED-012-R7: the countdown above the clock
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
        case .failed: if !slideshow.isActive { photos.storedCopyFailed() }   // MED-001-R11, R14; MED-006-R3: no notice per slide
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
            host.reduceFlashing = settings.effectiveReduceFlashing   // ACC-012-R7
            host.compositor.flashLimits = settings.safetyClamp.flashLimitsOverride   // ACC-012-R5
            host.colorGrade = colorGrade.effectiveGrade(clamp: settings.safetyClamp)   // FX-003, ACC-012 gain cap
            host.compositor.motionFeedback = effectiveMotionFeedback   // FX-009, ACC-012 length cap
            host.compositor.outputEffectOrder = effectChain.order   // FX-020
            host.compositor.chromaticSplit = chromaticSplit.split   // FX-006
            host.compositor.directionalBlur = directionalBlur.blur   // FX-007
            host.compositor.radialBlur = radialBlur.blur   // FX-008
            host.compositor.echoFeedback = effectiveEcho   // FX-010, ACC-012 weight cap
            host.compositor.mosaic = mosaic.mosaic   // FX-012
            host.compositor.edgeOutline = effectiveEdgeOutline   // FX-014, ACC-012 colour scale
            host.compositor.lensDistortion = lensDistortion.lens   // FX-016
            host.compositor.vignette = vignette.vignette   // FX-015
            host.compositor.pixelSort = pixelSort.sort   // FX-011
            host.compositor.scanlines = scanlines.scanlines   // FX-018
            host.compositor.filmGrain = effectiveFilmGrain   // FX-017 (static under Reduce Motion)
            host.onRenderHealthChange = observeRenderHealth(of: "video")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onVideoStateChange = { [weak self] (state: VideoLayerState) in self?.videoStateChanged(state) }
            host.loopRegion = videos.loopRegion   // MED-003: before the first start
            host.playbackSpeed = videos.speed     // MED-004
            host.reverse = videos.reverse         // MED-005
            host.onReverseStateChange = { [weak self] (state: VideoReverseState) in self?.videos.reverseStateChanged(state) }
            host.content = Self.videoContent(videos.video)
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            videoVisual = host
            applyLayerState(to: host.compositor)   // CMP-015
            logo.attach(to: host.compositor)   // MED-010-R5: the logo is the top layer
            clock.attach(to: host.compositor)   // MED-011-R6: the clock above the logo
            countdown.attach(to: host.compositor)   // MED-012-R7: the countdown above the clock
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
        case .playing(let width, let height):
            videos.playingSize = (width, height)
            videos.durationNanoseconds = videoVisual?.video.mediaDurationNanoseconds   // MED-003
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
            host.reduceFlashing = settings.effectiveReduceFlashing   // ACC-012-R7
            host.compositor.flashLimits = settings.safetyClamp.flashLimitsOverride   // ACC-012-R5
            host.colorGrade = colorGrade.effectiveGrade(clamp: settings.safetyClamp)   // FX-003, ACC-012 gain cap
            host.compositor.motionFeedback = effectiveMotionFeedback   // FX-009, ACC-012 length cap
            host.compositor.outputEffectOrder = effectChain.order   // FX-020
            host.compositor.chromaticSplit = chromaticSplit.split   // FX-006
            host.compositor.directionalBlur = directionalBlur.blur   // FX-007
            host.compositor.radialBlur = radialBlur.blur   // FX-008
            host.compositor.echoFeedback = effectiveEcho   // FX-010, ACC-012 weight cap
            host.compositor.mosaic = mosaic.mosaic   // FX-012
            host.compositor.edgeOutline = effectiveEdgeOutline   // FX-014, ACC-012 colour scale
            host.compositor.lensDistortion = lensDistortion.lens   // FX-016
            host.compositor.vignette = vignette.vignette   // FX-015
            host.compositor.pixelSort = pixelSort.sort   // FX-011
            host.compositor.scanlines = scanlines.scanlines   // FX-018
            host.compositor.filmGrain = effectiveFilmGrain   // FX-017 (static under Reduce Motion)
            host.onRenderHealthChange = observeRenderHealth(of: "text")   // PERF-014
            #if DEBUG
            host.compositor.faultInjection = armedRenderFaults
            #endif
            host.onTextStateChange = { [weak self] (state: TextLayerState) in self?.textState = state }
            host.spec = texts.spec
            presentation.register(host)   // PERF-011: starts suspended while the app cannot present
            textVisual = host
            applyLayerState(to: host.compositor)   // CMP-015
            logo.attach(to: host.compositor)   // MED-010-R5: the logo is the top layer
            clock.attach(to: host.compositor)   // MED-011-R6: the clock above the logo
            countdown.attach(to: host.compositor)   // MED-012-R7: the countdown above the clock
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
        cameraExposure = .notRunning(canLock: false)   // CAM-004-R7: the host's stop released the camera
        cameraFocus = .notRunning(canFocus: false)   // CAM-005-R8: the host's stop reset the focus
        cameraWhiteBalance = .notRunning(canLock: false)   // CAM-006-R9: the host's stop released it
        cameraPersonMaskAvailability = .available   // CAM-008: known again with the next host
        cameraStopReason = nil   // CAM-013
        cameraRetryPending = false
        cameraNoticeDismissed = false   // UIX-015-R7
    }

    /// UIX-015-R7: Dismiss on the camera's denied or restricted notice (this attempt only).
    func dismissCameraNotice() {
        cameraNoticeDismissed = true
    }

    /// UIX-015-R1: the camera's status for the explainer (the chosen camera).
    var cameraPermissionStatus: PermissionState? {
        PermissionStatusSource.camera(position: settings.cameraPosition)
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
        reconcileCameraLensChoice()   // CAM-003-R6
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
        host.personMask = settings.cameraPersonMask   // CAM-008-R1: from the next frame
        mirrorCameraAnalysis(host.mirrored)   // CAM-009, CAM-010: x follows the shown picture
        host.cameraLens = cameraLensInventory.resolve(settings.cameraLens)   // CAM-003-R5, R6
    }

    /// PRE-009-R10: the shown visual pauses while the Compare sheet's previews run.
    func pauseVisualsForComparison() {
        renderer?.pause()
        nativeVisual?.pause()
        cameraVisual?.pause()
        photoVisual?.pause()
        videoVisual?.pause()
        textVisual?.pause()
    }

    /// PRE-009-R10: the normal visual switch restores whichever visual is shown.
    func resumeVisualsAfterComparison() { resumeActiveVisual() }

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
    /// REC-003/REC-004: what the recording coordinator reads (visual, output, pause; source mode, consent, tap).
    /// REC-010-R9: the library's results are announced on the `library` lane.
    private func makeRecordingLibrary() -> RecordingLibraryModel {
        let library = RecordingLibraryModel()
        library.announce = { [weak self] (text: String) in self?.announcer.announce(text, kind: .library) }
        library.photos = photosSave   // REC-011: Save to Photos on a row
        return library
    }

    /// REC-003's coordinator; REC-010-R9: Keep announces on the `library` lane.
    private func makeVideoRecording() -> VideoRecordingCoordinator {
        let recording = VideoRecordingCoordinator { [weak self] () -> VideoRecordingCoordinator.Context in
            guard let self else { return VideoRecordingCoordinator.Context(source: nil, visualShown: false, outputLive: false, paused: false) }
            return self.videoRecordingContext
        }
        recording.onKept = { [weak self] (text: String) in self?.announcer.announce(text, kind: .library) }
        return recording
    }

    var videoRecordingContext: VideoRecordingCoordinator.Context {
        let manager = manager
        var context = VideoRecordingCoordinator.Context(source: activeVideoRecordingSource, visualShown: screen == .visualizer,
                                                 outputLive: externalDisplay.blackoutPhase == .live, paused: userPaused,
                                                 audioMode: manager.activeMode,
                                                 microphoneGranted: microphonePermissionProbe.permission == .granted,
                                                 includeMicrophone: recordingAudio.includeMicrophone,
                                                 audioTap: manager.recordingTap,
                                                 setAudioTapArmed: { (armed: Bool) -> Void in manager.setRecordingTapArmed(armed) },
                                                 qualityProfile: recordingQuality.profile,   // REC-005
                                                 qualityCapabilities: RecordingQualitySetting.deviceCapabilities(),
                                                 frameRateChoice: recordingQuality.frameRate)   // REC-006
        context.countdown = recordingCountdown.length   // REC-007
        context.timedStop = recordingTimedStop.length   // REC-008
        context.aspect = recordingQuality.aspect   // REC-014
        return context
    }

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
        layers.visualShown(settings.visual)   // CMP-015-R8: another scene clears solo and mute
        if !settings.visual.usesCamera { releaseCameraVisual() }   // CAM-001-R7: leaving Camera stops it
        if !settings.visual.usesPhoto { releasePhotoVisual() }     // MED-001
        if !settings.visual.usesVideo { releaseVideoVisual() }     // MED-002: leaving Video stops its decoder
        if !settings.visual.usesText { releaseTextVisual() }       // MED-009
        nativeVisual?.barCount = circularSpectrumBarCount
        nativeVisual?.smoothing = settings.spectrumSmoothing   // ANL-003: from the next frame, no snap
        nativeVisual?.particleTrails = settings.particleTrails   // VIS-010: from the next frame, no rebuild
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
        StoredMediaAvailability(photos: photos.knownIDs, videos: videos.knownIDs)   // FILE-008-R5
    }

    private func finishReopen(_ replacement: SceneAutosaveHeldScene?) {
        let visual = recovery.heldVisual
        guard let marked = recovery.markReopened() else { return }
        let held = replacement ?? marked
        if let values = sceneAutosave?.reopen(held) {
            SceneAutosaveCapture.apply(values, to: settings)
            SceneAutosaveCapture.applyEffects(values.effects, chain: effectChain, grade: colorGrade, trails: motionFeedback,
                                              chromatic: chromaticSplit, directionalBlur: directionalBlur,
                                              radialBlur: radialBlur, echo: echoFeedback,
                                              mosaic: mosaic, edgeOutline: edgeOutline,
                                              lensDistortion: lensDistortion, vignette: vignette,
                                              pixelSort: pixelSort, scanlines: scanlines, filmGrain: filmGrain)   // FX-020, FX-006 to FX-008, FX-010, FX-012, FX-014, FX-016, FX-015, FX-011, FX-018, FX-017
            layers.restore(values.layerComposites)   // CMP-015-R5
            if let text = values.text { texts.spec = text }
            videos.restoreLoop(storeID: values.videoStoreID, loop: values.videoLoop)   // MED-003-R8
            videos.restoreSpeed(storeID: values.videoStoreID, speedPercent: values.videoSpeedPercent)   // MED-004-R7
            if let restore = values.slideshow { restorePhotoMotion(restore) }   // MED-006-R12, MED-007-R10
            if let scene = values.logo { logo.restore(storeID: scene.storeID, placement: scene.placement) }   // MED-010-R10
            macros.restore(values.macros)   // MOD-010: restored, not applied
            palettes.restore(values.paletteID)   // UIX-011
        }
        if let visual { settings.visual = visual }
        resetTrailsHistory()   // FX-009-R5: a reopened scene starts without trails
        modulationMatrix.refresh()   // MOD-012
        sceneHistory.restart()   // SCN-010-R9: Reopen is not an edit
        statusEvents.post(StatusEventCatalog.lastSceneReopened())   // ACC-011 X25
    }

    /// Start fresh: keeps the fresh scene and commits it, replacing the held one.
    func startFresh() {
        guard recovery.offer == .pending else { return }
        recovery.markStartedFresh()
        sceneAutosave?.commitFreshScene()
        modulationMatrix.refresh()   // MOD-012
    }

    // MARK: - Scene autosave (SCN-002)

    /// What the current scene captures (research SCN-002-D1). Camera is session only: the visual
    /// chosen before it is recorded (CAM-001-R11).
    var sceneInputs: SceneInputs {
        SceneInputs(visual: SceneAutosaveCapture.recordedVisual(settings.visual, beforeCamera: settings.visualBeforeCamera),
                    bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                    spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                    glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                    text: texts.spec, photoID: photos.photo?.id, videoID: videos.video?.id,
                    videoLoop: SceneVideoLoopBridge.scene(videos.loopRegion),   // MED-003
                    videoSpeedPercent: videos.sceneSpeedPercent,   // MED-004
                    slideshow: slideshow.sceneValue,   // MED-006
                    kenBurns: kenBurns.sceneValue,   // MED-007
                    layerComposites: layers.composites,   // CMP-015
                    logo: logo.sceneLogo,   // MED-010
                    effects: liveEffectSettings,   // FX-020
                    macros: macros.entries,   // MOD-010
                    bindings: modulationMatrix.routes,   // MOD-012
                    palette: ScenePaletteChoice(id: palettes.sceneLink))   // UIX-011
    }

    /// ACC-003-R13: the colour-blind-safe palette setting changed; the native spectrum redraws with it.
    func spectrumPaletteChanged() {
        nativeVisual?.palette = effectiveSpectrumPalette
    }

    /// UIX-011-R8: the scene's palette, unless ACC-003's colour-blind-safe switch is on.
    /// SHOW-008-R7: a Visual Colour track paints the visual in one colour (the colour-blind-safe palette still wins).
    var effectiveSpectrumPalette: VisualPalette {
        if let track = Self.trackPalette(showKeyframes.output.color, colorBlindSafe: settings.colorBlindSafePalette) { return track }
        return palettes.visualPalette(colorBlindSafe: settings.colorBlindSafePalette)
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
        UITestVisualProbes.bindGlowToSectionChangeIfRequested(host)   // QA-011 B07 ANL-015-T12
        guard ProcessInfo.processInfo.arguments.contains(Self.bindGlowToLevelArgument) else { return }
        try? host.bind(AudioFeatureBinding(source: .bandMean, target: VisualParameterIDs.bloomIntensity,
                                           outputStart: 0, outputEnd: 1))
    }

    /// "bound, manual 0.50, effective 0.73", or a note when no native visual exists.
    var glowModulationReadout: String { nativeVisual?.glowModulationReadout ?? "no native visual" }

    func unbindGlowTest() {
        nativeVisual?.unbind(VisualParameterIDs.bloomIntensity)
        modulationMatrix.refresh()   // MOD-012
    }
    #endif

    /// The system Reduce Motion setting changed.
    func systemReduceMotionChanged(_ enabled: Bool) {
        settings.systemReduceMotion = enabled
        nativeVisual?.reduceMotion = enabled   // VIS-007-R5
        photoVisual?.photo.reduceMotion = enabled   // MED-007-R7
        applyFilmGrain()   // FX-017-R4: static grain under Reduce Motion
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
    #if DEBUG
    /// QA-011 device acceptance: `-uitestDefaults <json object>` writes typed values (numbers, Bools, strings) to
    /// UserDefaults before any setting is read. Launch arguments alone arrive as strings, which the settings that
    /// read `NSNumber` ignore. The keys the previous launch wrote are removed first, so one test's settings never
    /// leak into the next (their list is kept under `uitest.defaults.keys`).
    ///
    /// A launch with neither `-uitestDefaults` nor `-uitestResetNotice` is a test's relaunch "as after a real relaunch"
    /// (QA-011 B07): it keeps what is stored, typed keys included. Removing them there turned the relaunched visual back
    /// to projectM (MED-007, MED-009 on D3, 2026-11-19: the Ken Burns note and the text visual were gone after
    /// relaunch). Every test launch passes one of the two flags, so tests stay isolated.
    static func applyUITestDefaults(_ defaults: UserDefaults, arguments: [String] = ProcessInfo.processInfo.arguments) {
        let listKey = "uitest.defaults.keys"
        guard arguments.contains("-uitestDefaults") || arguments.contains("-uitestResetNotice") else { return }
        for key in defaults.stringArray(forKey: listKey) ?? [] { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: listKey)
        guard let i = arguments.firstIndex(of: "-uitestDefaults"), i + 1 < arguments.count,
              let data = arguments[i + 1].data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        for (key, value) in values {
            // `{"$json": <value>}` is stored as JSON data: settings kept as Codable JSON (MED-011's clock, QA-011 B13).
            if let wrapped = value as? [String: Any], let inner = wrapped["$json"],
               let encoded = try? JSONSerialization.data(withJSONObject: inner, options: [.sortedKeys]) {
                defaults.set(encoded, forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(Array(values.keys), forKey: listKey)
    }
    #endif

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

    /// MIDI-008 (research MIDI-008-D5): Pause or resume as the controls' Pause/Resume does, without revealing the
    /// controls, and only while the visualizer is shown and the app is active; no change, no announcement.
    func setPausedQuietly(_ paused: Bool) {
        guard screen == .visualizer, appIsActive, userPaused != paused else { return }
        userPaused = paused
        paused ? pauseActiveVisual() : resumeActiveVisual()
        updateIdleTimer()
        announcer.announce(AccessibilityAnnouncer.pausedText(paused), kind: .playback)
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
        midi.sceneBecame(active: active)   // MIDI-001-R7: no discovery outside the foreground
        warmStart.sceneBecame(active: active)   // PERF-009-R6: write the pipeline archive back
        motionModulation.setAppActive(active)   // CAM-011-R8: no motion sensor outside the foreground
        if active { faceTracking.refreshPermission() }   // CAM-009-R5: access changed in iOS Settings
        if active { handTracking.refreshPermission() }   // CAM-010-R5
        if active { countdown.appBecameActive() }   // MED-012-R4: a countdown that ended in the background finishes once
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
    /// PERF-005-R8: the app's prewarm scheduler; preset picks are forwarded through it at once (nil: direct).
    var prewarmScheduler: PrewarmScheduler?
    /// PRE-016: the user's parameter overrides, applied to the bytes of a preset loaded for display.
    var overrides: PresetOverrideStore?
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
        // PRE-016-R5: overrides apply to a copy of the bytes; the file itself is never written.
        let adjustments: [String: Double] = overrides?.overrides(for: preset.id) ?? [:]
        if !adjustments.isEmpty {
            let original: Data = try playable.data ?? Data(contentsOf: fileURL)
            playable.data = PresetTextOverlay.apply(adjustments, to: original)
        }
        try await renderer.setPreset(playable)
    }

    /// PRE-016: a preset's own bytes (user copy, bundle file or archive), read-only.
    func originalData(for preset: IndexedPreset) async throws -> Data {
        if preset.source == PresetLibrary.userSource {
            guard let data = await userPresetData?(preset.id) else { throw CocoaError(.fileNoSuchFile) }
            return data
        }
        return try bundledData(for: preset)
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
        // PERF-008-R2: Battery saver (or Follow Low Power Mode under Low Power) skips the background warm-up.
        guard Self.allowsWarmUp(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) else { return }
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
        if let prewarmScheduler {
            prewarmScheduler.forwardPresets(playable.map(\.id)) { renderer.prewarm(playable) }
        } else {
            renderer.prewarm(playable)
        }
    }

    /// PERF-008-R2: the active power budget allows the SC-104 background warm-up.
    static func allowsWarmUp(lowPower: Bool) -> Bool {
        PowerProfileState.budget(lowPower: lowPower).allowsBackgroundWarmUp
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
