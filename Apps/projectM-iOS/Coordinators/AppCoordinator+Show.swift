// AppCoordinator+Show.swift — the show's link to the live output (SHOW-001-R7, R8, R10; contract S4;
// research SHOW-001-D5, D6).
//
// * Applying a cue's scene sets exactly what Settings sets — the visual, the spectra's options, the
//   glow and the Text visual's spec — then runs the same `visualSettingsChanged()` and
//   `glowSettingsChanged()`. That path never touches the audio source (VIS-001-R12), and a scene never
//   selects Camera, so a cue never starts the camera (it stops it when it leaves Camera).
// * Blackout (OUT-010, SHOW-014): the output slot's black cover is above any visual, so a step while
//   blacked out stays black; Restore fades in the active cue's look.
// * The buttons in the controls restart the controls' hide delay; the keyboard shortcuts do not show
//   the controls.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import VisualGenerators
import VisualParameters

extension AppCoordinator {
    static let showOmittedLayersNote = "Some layers aren't shown"
    static let showMissingMediaNote = "the scene's photo or video is no longer stored; the current one is shown."

    /// The look a new cue captures (Camera records the visual chosen before it).
    var showLook: ShowLook {
        ShowLook(visual: ShowSceneSnapshot.recordedVisual(settings.visual, beforeCamera: settings.visualBeforeCamera),
                 bars: settings.circularSpectrumBars, orientation: settings.linearSpectrumOrientation,
                 spacing: settings.linearSpectrumSpacing, glowEnabled: settings.glowEnabled,
                 glowIntensity: settings.glowIntensity, glowRadius: settings.glowRadius, glowThreshold: settings.glowThreshold,
                 text: texts.spec, photoID: photos.photo?.id, videoID: videos.video?.id,
                 videoLoop: SceneVideoLoopBridge.scene(videos.loopRegion),   // MED-003
                 videoSpeedPercent: videos.sceneSpeedPercent,   // MED-004
                 slideshow: slideshow.sceneValue,   // MED-006
                 logo: logo.sceneLogo)   // MED-010
    }

    /// Wires the show to this coordinator (called once at the end of init).
    func connectShow() {
        show.applyScene = { [weak self] (document: SceneDocument, warnings: [SceneIssue]) -> [String] in
            guard let self else { return [] }
            let notes = self.applyShowScene(document, warnings: warnings, refresh: true)
            self.cueTransitions.sceneApplied()   // XFADE-R1: the frozen frame blends out on the visual shown now
            self.sceneSwitchReached(.applied)   // UIX-002-R8: the switcher's latency ends at the applied state
            self.scenePreviews.sceneApplied(document.id)   // SCN-006: a picture after the settle, when it has none
            return notes
        }
        connectCueTransitions()   // SCN-007
        show.availability = { [weak self] () -> StoredMediaAvailability in
            self?.storedMediaAvailability ?? StoredMediaAvailability(photos: [], videos: [])
        }
        // SCN-012: a cue's scene that needs review shows the repair report first.
        show.requestRepair = { [weak self] (request: SceneRepairRequest) in
            self?.sceneSwitchReached(.repairShown)   // UIX-002-R8: or at the repair report's request
            self?.sceneRepair.present(request)
        }
        // ACC-004-R7: cue announcements share the rate-limited path (a clicker can step quickly).
        show.announce = { [weak self] (message: String) in self?.announcer.announce(message, kind: .cue) }
        show.announceLibrary = { [weak self] (message: String) in self?.announcer.announce(message, kind: .library) }   // SCN-004
        sceneRepair.availability = { [weak self] () -> StoredMediaAvailability in
            self?.storedMediaAvailability ?? StoredMediaAvailability(photos: [], videos: [])
        }
        // MIDI-006: note triggers step the show and use OUT-010's blackout (kept out of init's type-check budget).
        // MIDI-008: Play/Pause, Play and Pause drive the visualizer's Pause.
        let performer = MIDINoteActionPerformer(
            show: show, external: externalDisplay,
            isPaused: { [weak self] () -> Bool in self?.userPaused ?? false },
            setPaused: { [weak self] (paused: Bool) -> Void in self?.setPausedQuietly(paused) })
        midiMappings.connectNoteActions(performer)
        connectScenePreviews()   // SCN-006
        // MIDI-007: program changes and notes select scenes through Go to Cue; "not found" on the `.midi` lane.
        midiMappings.connectSceneActions(MIDISceneActionPerformer(show: show, announce: midiMappings.announce))
        midiMappings.sceneDisplayName = { [weak show] (id: String) -> String? in
            guard let show, show.firstCue(ofScene: id) != nil else { return nil }
            return show.displayName(ofScene: id)
        }
    }

    /// SCN-007: a cue's transition goes to the stage with the safety settings of the moment; XFADE: the stage freezes
    /// and blends the shown compositor visual (Camera, Photo, Video, Text), and a native visual or projectM is a cut.
    private func connectCueTransitions() {
        show.transitionDriver = cueTransitions
        cueTransitions.shownHost = { [weak self] () -> (any CompositorVisualHost)? in self?.shownCompositorHost }
        show.transitionSafety = { [weak self] () -> (reduceMotion: Bool, reduceFlashing: Bool) in
            guard let self else { return (reduceMotion: false, reduceFlashing: false) }
            return (reduceMotion: self.settings.systemReduceMotion, reduceFlashing: self.settings.reduceFlashing)
        }
    }

    /// XFADE: the compositor-backed visual on screen now (nil for a native visual, projectM or another screen).
    var shownCompositorHost: (any CompositorVisualHost)? {
        if showsCameraVisual { return cameraVisual }
        if showsPhotoVisual { return photoVisual }
        if showsVideoVisual { return videoVisual }
        if showsTextVisual { return textVisual }
        return nil
    }

    /// Sets a validated scene's look; returns the notes for the step's notice.
    @discardableResult
    func applyShowScene(_ document: SceneDocument, warnings: [SceneIssue], refresh: Bool) -> [String] {
        guard let registry = try? SceneArchiveService.appRegistry() else { return [] }
        let apply = ShowSceneSnapshot.apply(of: document, warnings: warnings, registry: registry)
        Self.set(apply, settings: settings, texts: texts)
        videos.restoreLoop(storeID: apply.videoStoreID, loop: apply.videoLoop)   // MED-003-R8
        videos.restoreSpeed(storeID: apply.videoStoreID, speedPercent: apply.videoSpeedPercent)   // MED-004-R7
        if let restore = apply.slideshow { slideshow.restore(restore.value) }   // MED-006-R12
        if let scene = apply.logo { logo.restore(storeID: scene.storeID, placement: scene.placement) }   // MED-010-R10
        sceneHistory.restart()   // SCN-010-R9: a cue is not an edit
        resetTrailsHistory()   // FX-009-R5: a cue's scene (and UIX-002's switcher) starts without trails
        if refresh {
            visualSettingsChanged()
            glowSettingsChanged()
        }
        var notes: [String] = []
        if !apply.omittedKinds.isEmpty { notes.append("\(Self.showOmittedLayersNote) (\(apply.omittedKinds.joined(separator: ", "))).") }
        if apply.missingMedia { notes.append(Self.showMissingMediaNote) }
        noteAppliedSceneMedia(document, missingMedia: apply.missingMedia)   // MED-013-R2: the placeholder tile
        return notes
    }

    /// Sets what Settings would set for `apply` (each setter keeps its own range rules).
    static func set(_ apply: ShowSceneApply, settings: AppSettings, texts: TextOverlayCoordinator) {
        typealias IDs = VisualParameterIDs
        let values = apply.parameters
        if let bars = values[IDs.circularSpectrumBarCount]?.enumCaseID.flatMap({ (s: String) -> Int? in Int(s) }) {
            settings.circularSpectrumBars = bars
        }
        if let raw = values[IDs.linearSpectrumOrientation]?.enumCaseID, let orientation = LinearSpectrumOrientation(rawValue: raw) {
            settings.linearSpectrumOrientation = orientation
        }
        if let spacing = values[IDs.linearSpectrumSpacing]?.doubleValue { settings.linearSpectrumSpacing = spacing }
        if let enabled = values[IDs.bloomEnabled]?.boolValue { settings.glowEnabled = enabled }
        if let v = values[IDs.bloomIntensity]?.doubleValue { settings.glowIntensity = v }
        if let v = values[IDs.bloomRadius]?.doubleValue { settings.glowRadius = v }
        if let v = values[IDs.bloomThreshold]?.doubleValue { settings.glowThreshold = v }
        if let text = apply.text { texts.spec = text }
        if settings.visual != apply.visual { settings.visual = apply.visual }
    }

    /// Settings → Show → Add Current Scene: a snapshot with a new scene ID, labelled after the visual.
    @discardableResult
    func addCurrentSceneToShow() -> Bool {
        let look = showLook
        let document = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: look.visual.title)
        guard show.addScene(document, label: look.visual.title) else { return false }
        scenePreviews.sceneSaved(document.id)   // SCN-006: the output already shows the new scene
        return true
    }

    // MARK: Controls and keys

    func showNextCue() { showControls(); show.next() }
    func showPreviousCue() { showControls(); show.previous() }
    func keyNextCue() { show.next() }
    func keyPreviousCue() { show.previous() }
}
