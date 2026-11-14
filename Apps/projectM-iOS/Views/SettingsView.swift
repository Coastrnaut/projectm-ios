// SettingsView.swift — Settings (task T103): the visual (VIS-001-R11, VIS-002-R11), its options and
// glow (FX-001-R11),
// the Camera visual (CAM-001-R1), the performance overlay (FR-048), Reduce flashing (FR-072), the OSC
// receiver (OSC-001-R16) and the Licenses screen (FR-067).
// MED-001: with Photo chosen, a Photo section offers Choose from Photos… (the out-of-process Photos
// picker: no library permission), Choose from Files… (images only), Remove Photo, the stored
// photo's size and the import notice.
// MED-002: with Video chosen, a Video section offers the same for one video (Photos picker with the
// videos filter, Files with movie types), Remove Video, the playing size and the import notice;
// MED-003 adds the loop region's In and Out sliders and Reset Loop (VideoLoopControls); MED-004 the
// Speed picker above them (VideoSpeedControls).
// MED-009: with Text chosen, a Text section edits the message (multi-line field), font, weight, size,
// color, alignment, vertical position, outline, background box and Reset Text; every change is saved
// and drawn at once. It is a standard List section, so Dynamic Type and VoiceOver apply.
// FILE-009: a Storage row (StorageUsageView: the space the app's data takes, read-only).
// SHOW-001: a Show row opens the cue list editor (ShowEditorView).
// UIX-001: a "Guided first scene" row closes Settings and opens the tutorial (UIX-001-R8).
// UIX-003: "Inspect" (context menu, VoiceOver action) on the seven registry rows opens the parameter inspector.
import ParameterGraph
import PhotosUI
import CameraLayer
import SwiftUI
import TextLayer
import VisualEffects
import VisualGenerators
import VisualParameters

struct SettingsView: View {
    @Bindable var settings: AppSettings
    /// OSC-001: the OSC receiver's toggle, port, status and test value.
    var osc: OSCReceiverCoordinator
    /// False when the active renderer cannot limit flashing (FR-072, T116). Both current renderers
    /// can (T119); this keeps Settings honest for any renderer that cannot.
    var reduceFlashingAvailable = true
    /// VIS-001-R16: the circular spectrum could not be created on this device.
    var nativeVisualUnavailable = false
    /// FX-001-R13: the glow could not be built on this device.
    var glowUnavailable = false
    /// MED-001: the imported photo (nil hides the Photo section, e.g. in previews).
    var photos: PhotoCoordinator?
    /// MED-006: the image slideshow (nil hides its section).
    var slideshow: SlideshowCoordinator?
    /// MED-010: the logo overlay (nil hides its section).
    var logo: LogoCoordinator?
    /// MED-002: the imported video (nil hides the Video section).
    var videos: VideoCoordinator?
    /// MED-009: the Text visual's message and style (nil hides the Text section).
    var texts: TextOverlayCoordinator?
    /// SHOW-001: the show (nil hides the Show row) and Add Current Scene.
    var show: ShowCoordinator?
    var addCurrentScene: () -> Void = {}
    /// FILE-005: back up and restore in Settings › Storage (nil hides it, e.g. in previews).
    var libraryBackup: LibraryBackupCoordinator?
    /// FILE-010: the files Clear Caches must keep (absolute paths).
    var cacheFilesInUse: @MainActor () -> Set<String> = { () -> Set<String> in [] }
    /// MED-013: Settings › Storage › Missing Media (nil hides the row).
    var missingMedia: MissingMediaCoordinator? = nil
    /// UIX-001: opens the guided first scene (nil hides the row, e.g. in previews).
    var openGuide: (() -> Void)?
    /// SCN-010: Undo and Redo in the navigation bar (nil hides them, e.g. in previews).
    var history: SceneHistoryCoordinator?
    /// CMP-015: Settings › Layers (nil hides the row, e.g. in previews).
    var layerInspector: AppCoordinator?
    /// AUD-008: the analysis-only input trim (nil hides its section, e.g. in previews).
    var inputTrim: InputTrimSetting?
    /// AUD-009: the analysis-only channel selection (nil hides its section, e.g. in previews).
    var channelSelection: ChannelSelectionSetting?
    /// AUD-010: the In-App Playback monitoring balance (nil hides its section, e.g. in previews).
    var playbackBalance: PlaybackBalanceSetting?
    /// AUD-010-R6: whether In-App Playback is the active source (the balance is enabled only then).
    var playbackBalanceAvailable = false
    /// AUD-011: the analysis-only noise gate (nil hides its section, e.g. in previews).
    var noiseGate: NoiseGateSetting?
    /// AUD-013: the per-source visual delay (nil hides its section, e.g. in previews).
    var latencyOffset: LatencyOffsetSetting?
    /// FX-003: the colour grade (nil hides its section, e.g. in previews).
    var colorGrade: ColorGradeSetting?
    /// FX-009: Trails (nil hides its section, e.g. in previews).
    var motionFeedback: MotionFeedbackSetting?
    /// MIDI-001: MIDI endpoint discovery (nil hides its section, e.g. in previews).
    var midi: MIDIDiscoveryCoordinator?
    /// REC-004: "Include microphone audio" and the next recording's audio status (nil hides the section).
    var recordingAudio: RecordingAudioSetting?
    var recordingAudioStatus: (() -> String)?
    /// REC-005: the record quality profile (nil hides the section, e.g. in previews).
    var recordingQuality: RecordingQualitySetting?
    /// UIX-015: the explainer before the camera and local network prompts (nil: none, e.g. in previews).
    var explainers: PermissionExplainerCoordinator?
    /// UIX-015-R1: the camera's permission status when Camera is picked.
    var cameraStatus: @MainActor () -> PermissionState? = { () -> PermissionState? in nil }
    /// PRE-006: Recently Played (nil hides its section, e.g. in previews).
    var recentPresets: RecentPresetsCoordinator?
    /// ACC-005-R7: announces a VoiceOver swipe at a slider's end (nil: none, e.g. in previews).
    var announcer: AccessibilityAnnouncer?
    @Environment(\.dismiss) private var dismiss
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showPhotoFileImporter = false
    @State private var pickedVideo: PhotosPickerItem?
    @State private var showVideoFileImporter = false
    /// The port being typed; applied on submit or when the field loses focus (OSC-001-R2).
    @State private var portText = ""
    @FocusState private var portFieldFocused: Bool
    /// UIX-003: the parameter shown in the inspector sheet.
    @State private var inspectedParameter: InspectedParameter?

    /// "50%", or "2.0%" with one decimal.
    static func percent(_ value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", value * 100)
    }

    /// A labeled percentage slider; VoiceOver reads the label and "50 percent", and swipes move it by
    /// one step of `spec` (FR-070; ACC-005). Each swipe is one undo step, as a drag is (SCN-010-R4).
    private func glowSlider(_ spec: AccessibleParameterSpec, target: ParameterTarget, text: String,
                            inspect: ParameterID? = nil) -> some View {
        let title: String = spec.label
        let value = Binding<Double>(get: { () -> Double in target.get() },
                                    set: { (newValue: Double) -> Void in target.set(newValue) })
        return VStack(alignment: .leading, spacing: 2) {
            // ACC-006-R1: title and value side by side, or stacked when they do not fit (clipped at AX5).
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(text).monospacedDigit().foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(text).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)
            Slider(value: value, in: spec.range) { (editing: Bool) in
                if !editing { history?.endCoalescing() }   // SCN-010-R4: a drag is one step
            }
                .accessibleParameter(spec, target: target, didStep: { [history] () -> Void in history?.endCoalescing() })
                .parameterInspectorEntry(inspect, menu: false, open: inspectParameter)   // UIX-003-R1
        }
        .parameterInspectorEntry(inspect, action: false, open: inspectParameter)
    }

    /// UIX-003: opens the parameter inspector over Settings.
    private func inspectParameter(_ id: ParameterID) { inspectedParameter = InspectedParameter(id: id) }

    /// ACC-005: the glow's real settings (AppSettings: saved, applied to the glow at once).
    static func glowTarget(_ settings: AppSettings, _ path: ReferenceWritableKeyPath<AppSettings, Double>) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in settings[keyPath: path] },
                        set: { (value: Double) -> Void in settings[keyPath: path] = value })
    }

    /// ACC-005: a text style value (TextOverlayCoordinator: saved and drawn at once).
    static func textTarget(_ texts: TextOverlayCoordinator, _ path: WritableKeyPath<TextOverlaySpec, Double>) -> ParameterTarget {
        ParameterTarget(get: { () -> Double in texts.spec[keyPath: path] },
                        set: { (value: Double) -> Void in texts.spec[keyPath: path] = value })
    }

    /// CAM-002-R1, R3, R11: Back or Front and the chosen camera's Mirror. Changing either never restarts
    /// the audio source; a switch shows the new camera as soon as it delivers a picture.
    private var cameraSection: some View {
        Section {
            Picker("Camera", selection: $settings.cameraPosition) {
                ForEach(CameraPosition.allCases, id: \.self) { (position: CameraPosition) in
                    Text(position.title).tag(position)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Camera")
            .accessibilityValue(settings.cameraPosition.title)
            .accessibilityIdentifier("cameraPositionPicker")
            Toggle("Mirror", isOn: $settings.cameraMirrored)
                .accessibilityIdentifier("cameraMirrorToggle")
            cameraCropRows
        } header: {
            Text("Camera")
        } footer: {
            Text("Mirror flips the camera picture left to right, like a mirror; saved frames and recordings show it the same way. Each camera keeps its own setting: on for Front, off for Back unless you change it. Fill covers the screen and crops the rest; Fit shows the whole picture with bars. Anchor keeps that part of the picture in place, and Zoom enlarges it; both cameras use the same framing, also after you turn the device.")
        }
    }

    /// CAM-007-R7: Crop (Fill/Fit), Anchor (Center/Top/Bottom) and Zoom (1× to 3×; spoken "1.5 times").
    @ViewBuilder private var cameraCropRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Crop").accessibilityHidden(true)   // shown; the picker carries the label
            Picker("Crop", selection: $settings.cameraCropMode) {
                ForEach(CameraCropMode.allCases, id: \.self) { (mode: CameraCropMode) in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Crop")
            .accessibilityValue(settings.cameraCropMode.title)
            .accessibilityIdentifier("cameraCropModePicker")
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Anchor").accessibilityHidden(true)   // shown; the picker carries the label
            Picker("Anchor", selection: $settings.cameraCropAnchor) {
                ForEach(CameraCropAnchor.allCases, id: \.self) { (anchor: CameraCropAnchor) in
                    Text(anchor.title).tag(anchor)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Anchor")
            .accessibilityValue(settings.cameraCropAnchor.title)
            .accessibilityIdentifier("cameraCropAnchorPicker")
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Zoom").accessibilityHidden(true)   // shown; the picker carries the label
            Picker("Zoom", selection: $settings.cameraZoom) {
                ForEach(CameraCrop.zoomChoices, id: \.self) { (zoom: Float) in
                    let title: String = CameraCrop.zoomTitle(zoom)
                    let spoken: String = CameraCrop.zoomSpokenValue(zoom)
                    Text(title).accessibilityLabel(spoken).tag(Double(zoom))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Zoom")
            .accessibilityValue(CameraCrop.zoomSpokenValue(Float(settings.cameraZoom)))
            .accessibilityIdentifier("cameraZoomPicker")
        }
    }

    // Split into separately type-checked sections (2026-11-14): as one List the body took
    // 406-438 ms to type-check on Xcode 27 (-warn-long-function-bodies), CI's Xcode 26 limit risk.
    var body: some View {
        NavigationStack {
            List {
                visualChoiceSection
                visualOptionsSection
                smoothingSection
                mediaSections
                performanceSection
                audioSections
                tailSections
            }
            .uitestSettingsSection()   // DEBUG: `-uitestSettingsSection <id>` (UI tests, owner rule 7)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let history { ToolbarItem(placement: .topBarLeading) { SceneUndoRedoButtons(history: history) } }   // SCN-010
            }
        }
        .accessibilityIdentifier("settings")
        .environment(\.parameterAnnouncer, announcer)   // ACC-005-R7
        .permissionExplainerSheet(explainers)   // UIX-015: over Settings, right before iOS's prompt
        .parameterInspectorSheet($inspectedParameter, settings: settings, history: history, announcer: announcer,
                                 reading: inspectorReading)   // UIX-003
    }

    /// UIX-003-R7: the live modulation reading (nil in previews).
    private var inspectorReading: (@MainActor (ParameterID) -> ParameterModulationReading?)? {
        guard let coordinator = layerInspector else { return nil }
        return { [weak coordinator] (id: ParameterID) -> ParameterModulationReading? in coordinator?.parameterModulationReading(for: id) }
    }

    @ViewBuilder private var visualChoiceSection: some View {
        Section("Visual") {
            ForEach(VisualChoice.allCases, id: \.self) { choice in
                Button {
                    choose(choice)   // UIX-015-R1: Camera may explain first
                } label: {
                    HStack {
                        Text(choice.title).foregroundStyle(Color.primary)   // ACC-004: label colour; `.primary` in a button resolves to the tint (blue failed the contrast audit)
                        Spacer(minLength: 8)
                        if settings.visual == choice {
                            Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(settings.visual == choice ? .isSelected : [])
                .accessibilityIdentifier("visual.\(choice.rawValue)")
            }
        }
    }

    @ViewBuilder private var visualOptionsSection: some View {
        Section {
            if settings.visual.isNative {
                if settings.visual.usesBars {   // VIS-003, VIS-004: no bars on a waveform or a phase plot
                    Picker("Bars", selection: $settings.circularSpectrumBars) {
                        ForEach(AppSettings.circularSpectrumBarChoices, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .segmentedUnlessAccessibilitySize()   // ACC-006-R1
                    .accessibilityLabel("Bars")
                    .accessibilityIdentifier("barsPicker")
                    .parameterInspectorEntry(VisualParameterIDs.circularSpectrumBarCount, open: inspectParameter)   // UIX-003
                }
                if settings.visual == .oscilloscope {   // VIS-003-R10
                    Picker("Line", selection: $settings.oscilloscopeLine) {
                        ForEach(OscilloscopeLine.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .segmentedUnlessAccessibilitySize()   // ACC-006-R1
                    .accessibilityLabel("Line")
                    .accessibilityIdentifier("oscilloscopeLinePicker")
                    Picker("Window", selection: $settings.oscilloscopeWindowMilliseconds) {
                        ForEach(AppSettings.oscilloscopeWindowChoices, id: \.self) { Text("\($0) ms").tag($0) }
                    }
                    .segmentedUnlessAccessibilitySize()   // ACC-006-R1
                    .accessibilityLabel("Window")
                    .accessibilityIdentifier("oscilloscopeWindowPicker")
                }
                if settings.visual == .lissajous { lissajousOptions }   // VIS-004-R11
                if settings.visual == .linearSpectrum {
                    Picker("Orientation", selection: $settings.linearSpectrumOrientation) {
                        ForEach(LinearSpectrumOrientation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .segmentedUnlessAccessibilitySize()   // ACC-006-R1
                    .accessibilityLabel("Orientation")
                    .accessibilityIdentifier("orientationPicker")
                    .parameterInspectorEntry(VisualParameterIDs.linearSpectrumOrientation, open: inspectParameter)   // UIX-003
                    Picker("Spacing", selection: $settings.linearSpectrumSpacing) {
                        ForEach(AppSettings.linearSpectrumSpacingChoices, id: \.value) { Text($0.title).tag($0.value) }
                    }
                    .segmentedUnlessAccessibilitySize()   // ACC-006-R1
                    .accessibilityLabel("Spacing")
                    .accessibilityIdentifier("spacingPicker")
                    .parameterInspectorEntry(VisualParameterIDs.linearSpectrumSpacing, open: inspectParameter)   // UIX-003
                }
                Toggle("Glow", isOn: $settings.glowEnabled)
                    .accessibilityIdentifier("glowToggle")
                    .parameterInspectorEntry(VisualParameterIDs.bloomEnabled, open: inspectParameter)   // UIX-003
                if settings.glowEnabled {
                    glowSlider(AccessibleParameterCatalog.glowIntensity, target: Self.glowTarget(settings, \.glowIntensity),
                               text: Self.percent(settings.glowIntensity), inspect: VisualParameterIDs.bloomIntensity)
                    glowSlider(AccessibleParameterCatalog.glowRadius, target: Self.glowTarget(settings, \.glowRadius),
                               text: Self.percent(settings.glowRadius, decimals: 1), inspect: VisualParameterIDs.bloomRadius)
                    glowSlider(AccessibleParameterCatalog.glowThreshold, target: Self.glowTarget(settings, \.glowThreshold),
                               text: Self.percent(settings.glowThreshold), inspect: VisualParameterIDs.bloomThreshold)
                }
            }
        } header: {
            Text("Visual")
        } footer: {
            if nativeVisualUnavailable && settings.visual.replacesProjectM {
                Text("\(settings.visual.title) isn't available on this device, so projectM is shown.")
                    .accessibilityIdentifier("nativeVisualUnavailableFooter")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("projectM plays presets. Circular Spectrum draws one bar per frequency band, low to high, clockwise from the top. Linear Spectrum draws them side by side, low to high, with caps that mark recent peaks. Oscilloscope draws the sound's waveform, held still when the sound repeats. Lissajous plots the left channel against the right: mono sound is a straight line, wide stereo fills the space; Mid/Side turns it so mono is vertical. Camera shows your rear or front camera behind a circular spectrum, only while it is on screen; the picture is never sent. Photo shows a picture you choose behind a circular spectrum. Video plays a video you choose, without its sound, behind a circular spectrum. Text shows your own words over a circular spectrum.")
                    if settings.visual.isNative {
                        if glowUnavailable {
                            Text(AppCoordinator.glowUnavailableMessage)
                                .accessibilityIdentifier("glowUnavailableFooter")
                        } else {
                            Text("Glow adds a soft halo around the bright parts; dark areas stay dark.")
                        }
                    }
                }
            }
        }
    }

    /// VIS-004-R11: the Lissajous's plot and persistence.
    @ViewBuilder private var lissajousOptions: some View {
        Picker("Plot", selection: $settings.lissajousMode) {
            ForEach(LissajousMode.allCases, id: \.self) { (mode: LissajousMode) in Text(mode.title).tag(mode) }
        }
        .segmentedUnlessAccessibilitySize()   // ACC-006-R1
        .accessibilityLabel("Plot")
        .accessibilityIdentifier("lissajousModePicker")
        Toggle("Persistence", isOn: $settings.lissajousPersistence)
            .accessibilityIdentifier("lissajousPersistenceToggle")
    }

    @ViewBuilder private var smoothingSection: some View {
        // ANL-003-R6: attack and release of the spectra's bars (Instant = today's look). A section
        // of its own, so the Visual section and its footer keep their place.
        if settings.visual == .circularSpectrum || settings.visual == .linearSpectrum {
            Section {
                Picker("Attack", selection: $settings.spectrumAttackMilliseconds) {
                    ForEach(AppSettings.spectrumAttackChoices, id: \.self) { Text(AppSettings.smoothingTitle(milliseconds: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Attack")
                .accessibilityIdentifier("smoothingAttackPicker")
                Picker("Release", selection: $settings.spectrumReleaseMilliseconds) {
                    ForEach(AppSettings.spectrumReleaseChoices, id: \.self) { Text(AppSettings.smoothingTitle(milliseconds: $0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Release")
                .accessibilityIdentifier("smoothingReleasePicker")
            } header: {
                Text("Smoothing")
            } footer: {
                Text("Attack sets how quickly bars rise to a louder sound, Release how slowly they fall. Instant shows each analysis as it comes.")
            }
        }
    }

    @ViewBuilder private var mediaSections: some View {
        if let layerInspector { layersSection(layerInspector) }   // CMP-015
        if let shelf = layerInspector?.parameterShelf { ParameterShelfSection(shelf: shelf) }   // UIX-004-R6
        if let coordinator = layerInspector, !coordinator.macros.isEmpty { macrosSection(coordinator) }   // MOD-010-R10
        if settings.visual.usesCamera {   // CAM-002-R1: which camera, and its mirror
            cameraSection
        }
        if settings.visual.usesPhoto, let photos {
            photoSection(photos)
            if let slideshow {   // MED-006
                SlideshowSection(slideshow: slideshow, endCoalescing: { [history] () -> Void in history?.endCoalescing() })
            }
        }
        if settings.visual.usesVideo, let videos {
            videoSection(videos)
        }
        if let logo { LogoSection(logo: logo) }   // MED-010: every visual (the help names those that show it)
        if settings.visual.usesText, let texts {
            textSection(texts)
        }
        if settings.visual.isNative { SpectrumColorsSection(settings: settings) }   // ACC-003-R13
        if let colorGrade { ColorGradeSection(setting: colorGrade).id("color") }   // FX-003-R9 (IDs: UITestSettingsSection)
        if let motionFeedback { TrailsSection(setting: motionFeedback, clamp: settings.safetyClamp) }   // FX-009-R9
        if let layerInspector { EffectChainSection(coordinator: layerInspector) }   // FX-020-R9 (the app coordinator)
        SensorySafetySection(settings: settings, announcer: announcer)   // ACC-012-R10
        ReduceFlashingSection(settings: settings, available: reduceFlashingAvailable).id("reduceFlashing")   // FR-072 (own view: ACC-012 body budget)
    }

    @ViewBuilder private var performanceSection: some View {
        Section {
            Toggle("Performance overlay", isOn: $settings.showsPerformanceOverlay)
                .accessibilityIdentifier("performanceOverlayToggle")
        } footer: {
            Text("Shows the frame rate and the audio state over the visualization.")
        }
    }

    @ViewBuilder private var audioSections: some View {
        if let inputTrim { InputTrimSection(inputTrim: inputTrim) }   // AUD-008-R8
        if let channelSelection { ChannelSelectionSection(selection: channelSelection) }   // AUD-009-R7
        if let noiseGate { NoiseGateSection(noiseGate: noiseGate) }   // AUD-011-R7
        if let playbackBalance { PlaybackBalanceSection(balance: playbackBalance, available: playbackBalanceAvailable) }   // AUD-010-R6
        if let latencyOffset { LatencyOffsetSection(setting: latencyOffset) }   // AUD-013-R10
        oscSection.id("osc")
        if let midi { MIDISettingsSection(midi: midi).id("midi") }   // MIDI-001-R8
        if let recordingQuality { RecordingQualitySection(setting: recordingQuality) }   // REC-005-R9
        if let recordingAudio { RecordingAudioSection(setting: recordingAudio, status: recordingAudioStatus) }   // REC-004-R13
    }

    @ViewBuilder private var tailSections: some View {
        if let show {   // SHOW-001-R14
            Section {
                NavigationLink {
                    ShowEditorView(show: show, addCurrentScene: addCurrentScene, midiMappings: midi?.mappings)   // MIDI-007-R8
                } label: {
                    LabeledContent("Show", value: show.hasCues ? "\(show.list.cues.count) \(show.list.cues.count == 1 ? "cue" : "cues")" : "No cues")
                }
                .accessibilityIdentifier("showEditorLink")
            }
            .id("show")
        }
        if let openGuide {   // UIX-001-R8
            Section {
                Button("Guided first scene", action: openGuide)
                    .accessibilityIdentifier("guidedFirstSceneButton")
            } footer: {
                Text("A short guide to making a scene. Everything stays on this device.")
            }
        }
        if let recentPresets { RecentHistorySection(recent: recentPresets).id("recentPresets") }   // PRE-006-R3, R4
        Section {
            NavigationLink("Storage") {   // FILE-009, FILE-010, FILE-005, MED-013
                StorageUsageView(filesInUse: cacheFilesInUse, libraryBackup: libraryBackup, missingMedia: missingMedia)
            }
                .accessibilityIdentifier("storageLink")
            NavigationLink("Licenses") { LicensesView() }
                .accessibilityIdentifier("licensesLink")
            LabeledContent("Version",
                           value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        }
        .id("storage")
        #if DEBUG
        // PERF-010-T15 ({device}): a real crash for the recovery check on D1. Debug builds only.
        Section {
            Button("Crash now (DEBUG)", role: .destructive) { fatalError("PERF-010 DEBUG crash button") }
                .accessibilityIdentifier("debugCrashButton")
        } footer: {
            Text("Debug builds only: ends the app abnormally to test session recovery.")
        }
        #endif
    }

    // MARK: UIX-015 explainer gates

    /// A visual row's tap: Camera goes through the explainer while iOS has never asked (UIX-015-R1).
    private func choose(_ choice: VisualChoice) {
        guard choice.usesCamera, settings.visual != choice, let explainers else {
            settings.visual = choice
            return
        }
        let status: PermissionState? = cameraStatus()
        let settings: AppSettings = self.settings
        explainers.request(.camera, status: status) { () -> Void in settings.visual = choice }
    }

    /// The OSC toggle: turning it on goes through the explainer first (UIX-015-R2); off is immediate.
    private func setOSCEnabled(_ on: Bool) {
        guard on, let explainers else {
            osc.setEnabled(on)
            return
        }
        let osc: OSCReceiverCoordinator = self.osc
        let status: PermissionState = PermissionStatusSource.localNetwork(state: osc.state)
        explainers.request(.localNetwork, status: status) { () -> Void in osc.setEnabled(true) }
    }

    // MARK: Photo (MED-001-R2, R7, R11, R15)

    /// CMP-015-R1: the layer inspector.
    private func macrosSection(_ coordinator: AppCoordinator) -> some View {
        MacrosSection(macros: coordinator.macros, settings: settings,
                      endCoalescing: { [history] () -> Void in history?.endCoalescing() })
            .id("macros")   // MOD-010 (UITestSettingsSection)
    }

    private func layersSection(_ coordinator: AppCoordinator) -> some View {
        let count: Int = coordinator.layerInspectorRows.count
        return Section {
            NavigationLink {
                LayerInspectorView(layers: coordinator.layers, history: coordinator.sceneHistory,
                                   rows: { () -> [LayerInspectorRow] in coordinator.layerInspectorRows },
                                   groups: { () -> [LayerInspectorGroupRow] in coordinator.layerInspectorGroups })
            } label: {
                LabeledContent("Layers", value: count == 1 ? "1 layer" : "\(count) layers")
            }
            .accessibilityIdentifier("layersLink")
        }
    }

    private func photoSection(_ photos: PhotoCoordinator) -> some View {
        Section {
            LabeledContent("Photo", value: photos.summary)
                .accessibilityIdentifier("photoSummary")
            PhotosPicker(selection: $pickedPhoto, matching: .images, preferredItemEncoding: .automatic) {
                Text("Choose from Photos…")
            }
            .disabled(photos.isImporting)
            .accessibilityIdentifier("choosePhotoFromPhotos")
            Button("Choose from Files…") { showPhotoFileImporter = true }
                .disabled(photos.isImporting)
                .accessibilityIdentifier("choosePhotoFromFiles")
            if photos.photo != nil {
                Button("Remove Photo", role: .destructive) { photos.remove() }
                    .disabled(photos.isImporting)
                    .accessibilityIdentifier("removePhoto")
            }
            if let notice = photos.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("photoNotice")
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("The picture you choose is copied into the app on this device without its location or camera details, and is never uploaded. Remove Photo deletes the copy.")
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await photos.photoPicked(item) }
        }
        .fileImporter(isPresented: $showPhotoFileImporter, allowedContentTypes: [.image]) { (result: Result<URL, any Error>) in
            Task { await photos.filePicked(result) }
        }
    }

    // MARK: Video (MED-002-R2, R7, R14, R19)

    private func videoSection(_ videos: VideoCoordinator) -> some View {
        Section {
            LabeledContent("Video", value: videos.summary)
                .accessibilityIdentifier("videoSummary")
            PhotosPicker(selection: $pickedVideo, matching: .videos, preferredItemEncoding: .automatic) {
                Text("Choose from Photos…")
            }
            .disabled(videos.isImporting)
            .accessibilityIdentifier("chooseVideoFromPhotos")
            Button("Choose from Files…") { showVideoFileImporter = true }
                .disabled(videos.isImporting)
                .accessibilityIdentifier("chooseVideoFromFiles")
            VideoSpeedControls(videos: videos)   // MED-004
            VideoLoopControls(videos: videos, endCoalescing: { [history] () -> Void in history?.endCoalescing() })   // MED-003
            if videos.video != nil {
                Button("Remove Video", role: .destructive) { videos.remove() }
                    .disabled(videos.isImporting)
                    .accessibilityIdentifier("removeVideo")
            }
            if let notice = videos.notice {
                Text(notice)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("videoNotice")
            }
        } header: {
            Text("Video")
        } footer: {
            Text("H.264 or HEVC, up to 4K, 60 frames per second and 500 MB. The video is copied into the app on this device without its sound, location or other details, and is never uploaded. It plays without sound; the music comes from your chosen source. Speed changes only the video, never the music. Loop in and Loop out repeat only that part. Remove Video deletes the copy.")
        }
        .onChange(of: pickedVideo) { _, item in
            guard let item else { return }
            pickedVideo = nil
            Task { await videos.videoPicked(item) }
        }
        .fileImporter(isPresented: $showVideoFileImporter, allowedContentTypes: [.movie]) { (result: Result<URL, any Error>) in
            Task { await videos.filePicked(result) }
        }
    }

    // MARK: Text (MED-009-R2, R12, R13)

    /// A binding to one field of the spec; each change is saved and drawn at once.
    private func field<Value>(_ texts: TextOverlayCoordinator, _ path: WritableKeyPath<TextOverlaySpec, Value>) -> Binding<Value> {
        Binding(get: { texts.spec[keyPath: path] }, set: { (value: Value) in texts.spec[keyPath: path] = value })
    }

    /// A SwiftUI color for a stored sRGB color, and back (extended values are clamped).
    private func color(_ texts: TextOverlayCoordinator, _ path: WritableKeyPath<TextOverlaySpec, TextColor>) -> Binding<Color> {
        Binding(get: {
            let c = texts.spec[keyPath: path]
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }, set: { (value: Color) in
            let r = value.resolve(in: EnvironmentValues())
            texts.spec[keyPath: path] = TextColor(red: Double(r.red), green: Double(r.green), blue: Double(r.blue), alpha: Double(r.opacity))
        })
    }

    private func textSection(_ texts: TextOverlayCoordinator) -> some View {
        Section {
            TextField("Message", text: Binding(get: { texts.spec.message }, set: { (value: String) in texts.setMessage(value) }),
                      axis: .vertical)
                .lineLimit(1...4)
                .accessibilityLabel("Message")
                .accessibilityIdentifier("textMessageField")
            if texts.messageWasCut {
                Text(TextOverlayCoordinator.cutNote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("textCutNote")
            }
            Picker("Font", selection: field(texts, \.font)) {
                ForEach(TextFontFamily.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("textFontPicker")
            Picker("Weight", selection: field(texts, \.weight)) {
                ForEach(TextFontWeight.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("textWeightPicker")
            glowSlider(AccessibleParameterCatalog.textSize, target: Self.textTarget(texts, \.size), text: Self.percent(texts.spec.size))
            ColorPicker("Color", selection: color(texts, \.color), supportsOpacity: true)
                .accessibilityIdentifier("textColorPicker")
            Picker("Alignment", selection: field(texts, \.alignment)) {
                ForEach(TextAlignmentChoice.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .segmentedUnlessAccessibilitySize()   // ACC-006-R1
            .accessibilityLabel("Alignment")
            .accessibilityIdentifier("textAlignmentPicker")
            Picker("Position", selection: field(texts, \.verticalPosition)) {
                ForEach(TextVerticalPosition.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .segmentedUnlessAccessibilitySize()   // ACC-006-R1
            .accessibilityLabel("Position")
            .accessibilityIdentifier("textPositionPicker")
            glowSlider(AccessibleParameterCatalog.textOutline, target: Self.textTarget(texts, \.outlineWidth),
                       text: Self.percent(texts.spec.outlineWidth))
            ColorPicker("Outline color", selection: color(texts, \.outlineColor), supportsOpacity: true)
                .accessibilityIdentifier("textOutlineColorPicker")
            Toggle("Background box", isOn: field(texts, \.showsBox))
                .accessibilityIdentifier("textBoxToggle")
            if texts.spec.showsBox {
                ColorPicker("Box color", selection: color(texts, \.boxColor), supportsOpacity: true)
                    .accessibilityIdentifier("textBoxColorPicker")
            }
            Button("Reset Text", role: .destructive) { texts.reset() }
                .accessibilityIdentifier("resetText")
        } header: {
            Text("Text")
        } footer: {
            Text("Size is a share of the picture's height, so the text looks the same on any screen. Leading and trailing follow the text's own direction (right to left for Arabic and Hebrew). The text is saved on this device only.")
        }
    }

    // MARK: OSC receiver (OSC-001-R16)

    private var oscSection: some View {
        Section {
            Toggle("OSC receiver", isOn: Binding(get: { osc.isEnabled }, set: { setOSCEnabled($0) }))
                .accessibilityIdentifier("oscReceiverToggle")
            HStack {
                Text("Port")
                Spacer()
                TextField("9000", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 120)
                    .focused($portFieldFocused)
                    .onSubmit(submitPort)
                    .accessibilityLabel("Port")
                    .accessibilityIdentifier("oscPortField")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { portFieldFocused = false }
                        .accessibilityIdentifier("oscPortDone")
                }
            }
            if let error = osc.portError {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("oscPortError")
            }
            if let notice = osc.permissionNotice {
                // FILE-013-R3, R4: Local Network denied — the catalog's notice with Open Settings.
                PermissionNoticeView(notice: notice, symbol: "network.slash", identifierPrefix: "localNetwork")
            } else {
                Text(osc.statusText)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("OSC status")
                    .accessibilityValue(osc.statusText)
                    .accessibilityIdentifier("oscStatus")
            }
            if osc.isEnabled {
                LabeledContent("Test value", value: OSCReceiverCoordinator.testValueText(osc.testValue))
                    .accessibilityIdentifier("oscTestValue")
                // OSC-009-R12: what the rate limiter dropped or held since launch.
                LabeledContent("Rate-limited", value: OSCReceiverCoordinator.rateLimitedText(osc.rateLimitedCount))
                    .accessibilityIdentifier("oscRateLimited")
            }
        } header: {
            Text("OSC")
        } footer: {
            Text("Lets an OSC controller on your local network send /projectm/test with a number from 0 to 1 to check the connection. projectM only listens while this is on and the app is open, never connects to the internet, and keeps nothing it receives.")
        }
        .onAppear { portText = String(osc.port) }
        .onChange(of: portFieldFocused) { _, focused in
            if !focused { submitPort() }
        }
    }

    private func submitPort() {
        osc.submitPort(portText)
        portText = String(osc.port)   // a refused entry returns to the stored port
    }
}
