// PresetCoordinator+Notes.swift — roadmap PRE-011 private preset notes in the app (specs/242-pre-011-preset-notes;
// R1-R5, R8; contract C3).
//
// * Notes live in PresetNoteStore (`Application Support/PresetCollections/notes.json`); every change is saved
//   before it is shown, and a refusal or a failed save changes nothing and sets `notesMessage`.
// * Edits announce on the shared announcer's library lane, naming the preset, never the note text.
// * Search matches note text in memory (R5). Nothing here logs, and no diagnostics path reads these
//   notes (R6; `scripts/check_compliance.py` refuses the store's name in diagnostics sources).
import Foundation
import PresetLibrary

extension PresetCoordinator {
    nonisolated static let hasNoteLabel = ", has note"

    nonisolated static func notesNoticeText(_ notice: PresetNoteStore.LoadNotice) -> String? {
        switch notice {
        case .none: nil
        case .unreadableSetAside: PresetNoteStore.unreadableText
        case .repaired: PresetNoteStore.repairedText
        }
    }

    nonisolated static func noteSavedText(_ name: String) -> String { "Note saved for \(name)." }
    nonisolated static func noteRemovedText(_ name: String) -> String { "Note removed from \(name)." }

    /// "120 of 2,000" (contract C3).
    nonisolated static func noteCountText(_ count: Int) -> String {
        PresetNoteMap.grouped(count) + " of " + PresetNoteMap.grouped(PresetNoteMap.maximumCharacters)
    }

    // MARK: - Reading

    func note(of preset: IndexedPreset) -> String? {
        _ = notesVersion
        return noteStore.note(for: preset.id)
    }

    func hasNote(_ preset: IndexedPreset) -> Bool { note(of: preset) != nil }

    /// R4: ", has note" for a row's VoiceOver label; empty without a note (the text itself is never read here).
    func noteLabelSuffix(_ preset: IndexedPreset) -> String { hasNote(preset) ? Self.hasNoteLabel : "" }

    /// R5: presets whose note contains the text (folded).
    func notePresetIDs(containing query: String) -> Set<String> {
        _ = notesVersion
        return noteStore.map.presetIDs(containing: query)
    }

    /// Non-nil when the saved notes come from a newer app version.
    var notesUnavailableText: String? {
        noteStore.availability == .available ? nil : PresetNoteError.newerFormat.message
    }

    // MARK: - Editing

    /// Saves the trimmed text as the preset's note (empty removes it). True when saved; false sets `notesMessage`.
    @discardableResult
    func saveNote(_ text: String, for preset: IndexedPreset) -> Bool {
        let had: Bool = noteStore.note(for: preset.id) != nil
        do {
            let stored: String? = try noteStore.set(text, for: preset.id)
            notesChanged()
            if stored != nil {
                announceLibrary(Self.noteSavedText(preset.name))
            } else if had {
                announceLibrary(Self.noteRemovedText(preset.name))
            }
            return true
        } catch {
            refuseNoteChange(error)
            return false
        }
    }

    @discardableResult
    func deleteNote(of preset: IndexedPreset) -> Bool { saveNote("", for: preset) }

    /// R8: the preset was removed, or its reference dangles; its note goes with it (silently).
    func pruneNote(_ presetID: String) {
        do {
            if try noteStore.prune(presetID) { notesChanged() }
        } catch {
            refuseNoteChange(error)
        }
    }

    func dismissNotesMessage() { notesMessage = nil }
    func dismissNotesNotice() { notesNotice = nil }

    private func notesChanged() {
        notesVersion += 1
        notesMessage = nil
    }

    private func refuseNoteChange(_ error: any Error) {
        let message: String = (error as? PresetNoteError)?.message ?? PresetNoteError.saveFailed.message
        notesMessage = message
        notesVersion += 1
        announceLibrary(message)
    }
}
