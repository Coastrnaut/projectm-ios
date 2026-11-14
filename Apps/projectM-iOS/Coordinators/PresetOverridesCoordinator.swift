// PresetOverridesCoordinator.swift — PRE-016 preset parameter overrides in the app (spec PRE-016-R1,
// R4, R12 to R16; research PRE-016-D6; contract C4).
//
// * Overrides live in PresetOverrideStore (`Application Support/PresetCollections/overrides.json`);
//   every change is saved before it is shown, and a refusal or failed save changes nothing and sets
//   `message`.
// * Original values are read from the preset's own bytes (bundle file, pack archive or stored user
//   copy, through RendererPresetLoader); those bytes are never written.
// * A finished change (a drag's end, a VoiceOver step) and a reset are announced on the shared
//   announcer's library lane (through `PresetCoordinator.announceLibrary`), and the preset on screen
//   is loaded again once, so it looks adjusted. The loader applies the overlay (R5).
import Foundation
import Observation
import PresetLibrary

@MainActor
@Observable
final class PresetOverridesCoordinator {
    /// Bumped on every change so views refresh.
    private(set) var version = 0
    /// Why the last change was refused or not saved; shown in the sheet.
    var message: String?

    @ObservationIgnored let store: PresetOverrideStore
    @ObservationIgnored private let originalData: @MainActor (IndexedPreset) async throws -> Data
    @ObservationIgnored weak var presets: PresetCoordinator?

    init(store: PresetOverrideStore, presets: PresetCoordinator?, originalData: @escaping @MainActor (IndexedPreset) async throws -> Data) {
        self.store = store
        self.presets = presets
        self.originalData = originalData
    }

    static let note = "Adjustments set starting values. The preset's own code may still change them."

    /// Non-nil when the saved adjustments come from a newer app version.
    var unavailableText: String? {
        store.availability == .available ? nil : PresetOverrideError.newerFormat.message
    }

    // MARK: - Reading

    func overrides(for preset: IndexedPreset) -> [String: Double] {
        _ = version
        return store.overrides(for: preset.id)
    }

    func hasOverrides(_ preset: IndexedPreset) -> Bool { !overrides(for: preset).isEmpty }

    /// The values the preset's own text starts from (engine defaults where it sets none); nil when
    /// its bytes cannot be read.
    func originals(for preset: IndexedPreset) async -> [PresetOverrideParameter: Double]? {
        guard let data = try? await originalData(preset) else { return nil }
        return PresetTextOverlay.originalValues(data)
    }

    // MARK: - Changes

    /// Stores one adjustment; returns the value stored, or nil when refused.
    @discardableResult
    func set(_ value: Double, for parameter: PresetOverrideParameter, preset: IndexedPreset) async -> Double? {
        let stored: Double
        do {
            stored = try store.set(value, for: parameter.key, preset: preset.id)
        } catch {
            refuse(error)
            return nil
        }
        changed()
        announce(parameter.label + " set to " + PresetTextOverlay.valueText(stored) + " for " + preset.name + ".")
        await reloadIfShowing(preset)
        return stored
    }

    /// Removes one adjustment (the row's reset).
    func reset(_ parameter: PresetOverrideParameter, preset: IndexedPreset) async {
        do {
            guard try store.remove(parameter.key, preset: preset.id) else { return }
        } catch {
            refuse(error)
            return
        }
        changed()
        announce(parameter.label + " restored for " + preset.name + ".")
        await reloadIfShowing(preset)
    }

    /// R15: Reset to Original.
    func resetAll(_ preset: IndexedPreset) async {
        do {
            guard try store.reset(preset.id) else { return }
        } catch {
            refuse(error)
            return
        }
        changed()
        announce(preset.name + " restored to its original values.")
        await reloadIfShowing(preset)
    }

    /// R16: a user preset was removed; its adjustments go with it (silently).
    func prune(_ presetID: String) {
        do {
            if try store.prune(presetID) { changed() }
        } catch {
            refuse(error)
        }
    }

    func dismissMessage() { message = nil }

    // MARK: - Private

    private func changed() {
        version += 1
        message = nil
    }

    private func refuse(_ error: any Error) {
        let text: String = (error as? PresetOverrideError)?.message ?? PresetOverrideError.saveFailed.message
        message = text
        version += 1
        announce(text)
    }

    private func announce(_ text: String) { presets?.announceLibrary(text) }

    /// R14: the preset on screen loads again with the change (through the guarded path).
    private func reloadIfShowing(_ preset: IndexedPreset) async {
        guard let presets, let current = presets.current, current.id == preset.id else { return }
        await presets.select(current)
    }
}
