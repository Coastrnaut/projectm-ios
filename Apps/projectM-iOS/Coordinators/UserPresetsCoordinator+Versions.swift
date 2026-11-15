// UserPresetsCoordinator+Versions.swift — roadmap PRE-017 (specs/250-pre-017-preset-restore-points; R5, R8):
// the Versions sheet's data and its Revert. Revert goes through the library's edit path (static checks, the
// off-screen engine trial, `edit.json`); a saved revert reloads the preset on screen and is announced on the
// library lane.
import Foundation
import PresetLibrary

extension UserPresetsCoordinator {
    /// The earlier versions of an editable preset, newest first.
    func versions(of preset: UserPreset) async -> UserPresetVersionList {
        await library.versions(of: preset.id)
    }

    /// An earlier text for the read-only Preview; nil when it cannot be read.
    func versionText(of preset: UserPreset, version: UserPresetVersion) async -> PresetEditorText? {
        await library.versionText(of: preset.id, sha256: version.sha256)
    }

    /// Puts `version` back in place of `preset`'s current text.
    func revert(_ preset: UserPreset, to version: UserPresetVersion) async -> PresetEditOutcome {
        let outcome = await library.revert(preset.id, to: version.sha256, expectedSHA256: preset.sha256)
        await refresh()
        if case .saved = outcome { await presets?.reloadIfCurrent(preset.id) }
        speak(Self.revertMessage(outcome, name: preset.name))
        return outcome
    }

    nonisolated static func revertMessage(_ outcome: PresetEditOutcome, name: String) -> String {
        switch outcome {
        case .saved(let saved): return "Reverted “\(saved.name)”."
        case .unchanged: return "“\(name)” already has this text."
        case .refused(let refusal): return "Not reverted. " + refusal.message
        }
    }

    /// "14 Nov 2026 at 19:40 · 12 KB", and the name then when it differs.
    nonisolated static func versionLabel(_ version: UserPresetVersion, currentName: String) -> String {
        let date: String = version.replacedAt.formatted(date: .abbreviated, time: .shortened)
        let size: String = ByteCountFormatter.string(fromByteCount: Int64(version.byteCount), countStyle: .file)
        var label: String = date + " · " + size
        if version.name != currentName { label += " · was “" + version.name + "”" }
        return label
    }
}
