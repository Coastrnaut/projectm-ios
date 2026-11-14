// PresetCoordinator+Audition.swift — roadmap PRE-010 quick audition (specs/168-pre-010-quick-audition;
// contract A1; research PRE-010-D1 to D6).
//
// * `preview(_:from:)` loads a preset on screen without selecting it: `current`, `lastPresetID`, the
//   scope and its stored value, PRE-006's history, the warm-up, favorites, tags, collections and every
//   scene input stay as they were (R2). The first preview remembers the original (Cancel's target).
// * `cancelAudition()` (Cancel, Escape, closing the browser) loads the original again through the
//   loader only, so nothing is written (R4, R6). `keepAudition()` commits the shown preview as a
//   normal selection from the list it was previewed in, without loading it again (R5).
// * A failed preview leaves on screen what was there, says so in the bar and excludes the preset for
//   the session like any failed preset (R7). A successful `select` ends a preview (R8).
// * Imported presets pass through PRE-012's guard while previewed (D4). Announcements go to the
//   shared announcer's library lane (`announceLibrary`, R9). No networking; nothing is stored.
import Foundation
import PresetLibrary

/// PRE-010: the preview in progress (data-model). In memory only.
struct PresetAudition: Equatable {
    /// The committed preset when the first preview started; Cancel's target.
    let original: IndexedPreset?
    /// The previewed preset on screen; nil until a preview load succeeded.
    var showing: IndexedPreset?
    /// A preview whose load is in flight (Keep waits for it).
    var loading: IndexedPreset?
    /// The list the shown preview came from: Keep's scope (FR-116).
    var scope: PresetScope
    /// "<name> could not be previewed." after a failed preview.
    var notice: String?
}

extension PresetCoordinator {
    nonisolated static let previewingLabel = ", previewing"
    nonisolated static func previewingText(_ name: String) -> String { "Previewing \(name)." }
    nonisolated static func keptText(_ name: String) -> String { "Kept \(name)." }
    nonisolated static func cancelledText(_ name: String) -> String { "Preview cancelled. \(name) is back." }
    nonisolated static func previewFailedText(_ name: String) -> String { "\(name) could not be previewed." }

    /// The preset on screen: the preview, else the committed one.
    var onScreen: IndexedPreset? { audition?.showing ?? current }

    var isPreviewing: Bool { audition?.showing != nil }

    /// R1: playable, not flagged while Reduce flashing is on (ACC-002's warning is never bypassed), and
    /// not already on screen.
    func canPreview(_ preset: IndexedPreset) -> Bool {
        isPlayable(preset) && !isFlagged(preset) && preset != onScreen
    }

    /// Loads `preset` on screen as a preview from the list `listScope` (R2, R6, R7).
    func preview(_ preset: IndexedPreset, from listScope: PresetScope) async {
        guard canPreview(preset) else { return }
        if audition == nil { audition = PresetAudition(original: current, scope: listScope) }
        auditionGeneration += 1
        let generation = auditionGeneration
        audition?.loading = preset
        let isUserPreset = preset.source == PresetLibrary.userSource
        if let shown = onScreen, shown.source == PresetLibrary.userSource { await userGuard?.stoppedShowing(shown) }
        if isUserPreset { await userGuard?.willShow(preset) }   // PRE-012-R18 (D4)
        do {
            try await loader.load(preset)
            guard generation == auditionGeneration, audition != nil else { return }   // D3: cancelled or committed meanwhile
            audition?.loading = nil
            audition?.showing = preset
            audition?.scope = listScope
            audition?.notice = nil
            announceLibrary(Self.previewingText(preset.name))
        } catch {
            excludedThisSession.insert(preset.id)   // FR-118, in memory
            if isUserPreset { await userGuard?.failedOnScreen(preset, message: (error as NSError).localizedDescription) }
            guard generation == auditionGeneration, audition != nil else { return }
            audition?.loading = nil
            audition?.notice = Self.previewFailedText(preset.name)
            announceLibrary(Self.previewFailedText(preset.name))
        }
    }

    /// Keep (R5): the shown preview becomes the selection from its list, with no second load. Returns
    /// whether it committed (the browser then closes).
    @discardableResult
    func keepAudition() async -> Bool {
        guard let audition, let shown = audition.showing, audition.loading == nil else { return false }
        endAudition()
        setScope(audition.scope)
        didSelect(shown)
        announceLibrary(Self.keptText(shown.name))
        return true
    }

    /// Cancel, Escape and closing the browser (R4): the original comes back; nothing is stored.
    func cancelAudition() async {
        guard let audition else { return }
        endAudition()
        guard audition.showing != nil || audition.loading != nil else { return }   // only a notice: nothing replaced the original
        if let shown = audition.showing, shown.source == PresetLibrary.userSource { await userGuard?.stoppedShowing(shown) }
        guard let original = audition.original else { return }
        let isUserPreset = original.source == PresetLibrary.userSource
        if isUserPreset { await userGuard?.willShow(original) }
        do {
            try await loader.load(original)
            if isUserPreset && current == original { userGuard?.didShow(original) }
        } catch {
            failureMessage = Self.failureText
        }
        announceLibrary(Self.cancelledText(original.name))
    }

    /// Clears the bar's failure notice when nothing is being previewed (its OK button).
    func dismissAuditionNotice() {
        guard let audition, audition.showing == nil, audition.loading == nil else {
            self.audition?.notice = nil
            return
        }
        endAudition()
    }

    /// Ends any preview without a restore (Keep, Cancel, a committed selection; D3).
    func endAudition() {
        auditionGeneration += 1
        audition = nil
    }
}
