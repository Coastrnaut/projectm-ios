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
                 text: texts.spec, photoID: photos.photo?.id, videoID: videos.video?.id)
    }

    /// Wires the show to this coordinator (called once at the end of init).
    func connectShow() {
        show.applyScene = { [weak self] (document: SceneDocument, warnings: [SceneIssue]) -> [String] in
            self?.applyShowScene(document, warnings: warnings, refresh: true) ?? []
        }
        show.availability = { [weak self] () -> StoredMediaAvailability in
            self?.storedMediaAvailability ?? StoredMediaAvailability(photos: [], videos: [])
        }
        // SCN-012: a cue's scene that needs review shows the repair report first.
        show.requestRepair = { [weak self] (request: SceneRepairRequest) in self?.sceneRepair.present(request) }
        // ACC-004-R7: cue announcements share the rate-limited path (a clicker can step quickly).
        show.announce = { [weak self] (message: String) in self?.announcer.announce(message, kind: .cue) }
        sceneRepair.availability = { [weak self] () -> StoredMediaAvailability in
            self?.storedMediaAvailability ?? StoredMediaAvailability(photos: [], videos: [])
        }
    }

    /// Sets a validated scene's look; returns the notes for the step's notice.
    @discardableResult
    func applyShowScene(_ document: SceneDocument, warnings: [SceneIssue], refresh: Bool) -> [String] {
        guard let registry = try? SceneArchiveService.appRegistry() else { return [] }
        let apply = ShowSceneSnapshot.apply(of: document, warnings: warnings, registry: registry)
        Self.set(apply, settings: settings, texts: texts)
        sceneHistory.restart()   // SCN-010-R9: a cue is not an edit
        if refresh {
            visualSettingsChanged()
            glowSettingsChanged()
        }
        var notes: [String] = []
        if !apply.omittedKinds.isEmpty { notes.append("\(Self.showOmittedLayersNote) (\(apply.omittedKinds.joined(separator: ", "))).") }
        if apply.missingMedia { notes.append(Self.showMissingMediaNote) }
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
        return show.addScene(document, label: look.visual.title)
    }

    // MARK: Controls and keys

    func showNextCue() { showControls(); show.next() }
    func showPreviousCue() { showControls(); show.previous() }
    func keyNextCue() { show.next() }
    func keyPreviousCue() { show.previous() }
}
