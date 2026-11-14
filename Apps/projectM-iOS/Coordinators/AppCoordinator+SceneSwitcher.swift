// AppCoordinator+SceneSwitcher.swift — UIX-002: opening, searching and choosing in the quick scene
// switcher (spec UIX-002-R1, R5 to R9, R11; contract C3).
//
// * Opens only while the show has cues and Settings is closed (spec Edge Cases).
// * A choice closes the switcher, starts the latency probe and goes to the cue through SHOW-001's
//   `go(to:)`, so validation, SCN-012's repair report, notices, the undo restart and the saved
//   position are exactly a cue step's. `connectShow()` ends the measurement at the applied state or
//   at the repair request; a step that reached neither is recorded as failed.
// * Announcements go through the shared rate-limited announcer: the result count (kind `search`)
//   and "Scene: <label>" after an applied choice (kind `cue`).
import Foundation
import ShowControl

extension AppCoordinator {
    /// The show's cues as switcher rows (UIX-002-R2).
    var sceneSwitcherEntries: [SceneSwitcherEntry] {
        SceneSwitcherEntry.entries(list: show.list, sceneNames: show.sceneNames, unreadable: show.unreadableScenes)
    }

    /// Whether the switcher can open now (cues exist, Settings is closed).
    var canOpenSceneSwitcher: Bool { show.hasCues && !showSettings }

    func openSceneSwitcher() {
        guard canOpenSceneSwitcher else { return }
        sceneSwitcher.open(entries: sceneSwitcherEntries)
    }

    /// Closes without a choice: the abandoned query is kept and the controls are shown so focus can
    /// return to the Scenes button (UIX-002-R6, R11).
    func closeSceneSwitcher() {
        guard sceneSwitcher.isOpen else { return }
        sceneSwitcher.close(chose: false)
        showControls()
    }

    /// ⌘K.
    func toggleSceneSwitcher() {
        sceneSwitcher.isOpen ? closeSceneSwitcher() : openSceneSwitcher()
    }

    /// The field's text changed: keep or move the highlight and announce the count (UIX-002-R5, R9).
    func switcherQueryChanged() {
        let entries: [SceneSwitcherEntry] = sceneSwitcherEntries
        sceneSwitcher.queryChanged(entries: entries)
        let count: Int = sceneSwitcher.results(entries).count
        announcer.announce(AccessibilityAnnouncer.sceneSwitcherCountText(count), kind: .search)
    }

    func moveSwitcherHighlight(by offset: Int) {
        sceneSwitcher.moveHighlight(by: offset, entries: sceneSwitcherEntries)
    }

    /// Return in the field: the highlighted entry, or nothing when none matches.
    func chooseHighlightedSwitcherScene() {
        guard let entry = sceneSwitcher.highlighted(in: sceneSwitcherEntries) else { return }
        chooseSwitcherScene(entry.cueID)
    }

    /// Recalls the cue's scene through the cue path and measures the latency (contract C3).
    func chooseSwitcherScene(_ cueID: UUID) {
        let start: Double = sceneSwitcher.now()
        guard let cue = show.list.cues.first(where: { (c: ShowCue) -> Bool in c.id == cueID }) else { return }
        sceneSwitcher.close(chose: true)
        sceneSwitcher.probe.begin(sceneID: cue.sceneID, cueID: cueID, now: start)
        show.go(to: cueID)
        if sceneSwitcher.probe.isPending {
            sceneSwitcher.probe.finish(.failed, now: sceneSwitcher.now())
            return
        }
        if sceneSwitcher.probe.last?.outcome == .applied {
            announcer.announce(AccessibilityAnnouncer.sceneChosenText(cue.label), kind: .cue)
        }
    }

    /// Called from `connectShow()`: a cue's scene reached the live settings, or its repair report was
    /// requested. No-op unless a switcher choice is being measured.
    func sceneSwitchReached(_ outcome: SceneSwitchMeasurement.Outcome) {
        guard sceneSwitcher.probe.isPending else { return }
        sceneSwitcher.probe.finish(outcome, now: sceneSwitcher.now())
    }
}
