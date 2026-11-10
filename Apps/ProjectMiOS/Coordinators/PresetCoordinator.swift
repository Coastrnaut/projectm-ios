// PresetCoordinator.swift — preset browsing and switching (tasks T090, T091; FR-043, FR-044,
// FR-045, FR-088).
//
// * The list is alphabetical by display name (localized, numeric-aware: "Beta 2" before "Beta 10").
// * Next and Previous wrap around; Random never picks the current preset.
// * A preset that fails to load leaves the running one on screen and shows "Preset could not be
//   loaded" until the next successful load (FR-045).
// * The favorites filter shows only favorites, with FR-088's empty-state text when there are none.
// * The renderer blends to a new preset (soft cut, at most 2 s; set in the renderers).
import Foundation
import Observation
import Rendering

/// Loads a preset into the renderer (VisualizerRenderer.setPreset in the app; a fake in tests).
@MainActor
protocol PresetLoading: AnyObject {
    func load(_ preset: Preset) async throws
}

@MainActor
@Observable
final class PresetCoordinator {
    static let failureText = "Preset could not be loaded"
    static let emptyFavoritesText = "No favorites yet — tap the star on a preset to add one."

    /// All presets, alphabetical by display name.
    let presets: [Preset]
    private(set) var current: Preset?
    var favoritesOnly = false
    private(set) var failureMessage: String?
    /// Bumped on every favorite change so views refresh.
    private(set) var favoritesVersion = 0

    @ObservationIgnored private let store: FavoritesStore
    @ObservationIgnored private let loader: any PresetLoading

    init(presets: [Preset], store: FavoritesStore, loader: any PresetLoading) {
        self.presets = presets.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        self.store = store
        self.loader = loader
    }

    /// The preset to start with: the last selected one if it still exists, else the first.
    var initialPreset: Preset? {
        presets.first { $0.id == store.lastPresetID } ?? presets.first
    }

    var browserItems: [Preset] {
        _ = favoritesVersion
        return favoritesOnly ? presets.filter { store.isFavorite($0.id) } : presets
    }

    var emptyStateText: String? {
        favoritesOnly && browserItems.isEmpty ? Self.emptyFavoritesText : nil
    }

    func isFavorite(_ preset: Preset) -> Bool {
        _ = favoritesVersion
        return store.isFavorite(preset.id)
    }

    func toggleFavorite(_ preset: Preset) {
        store.toggle(preset.id)
        favoritesVersion += 1
    }

    // MARK: - Switching

    /// Loads `preset`; on failure keeps the current one and reports it (FR-045).
    func select(_ preset: Preset) async {
        do {
            try await loader.load(preset)
            current = preset
            failureMessage = nil
            store.lastPresetID = preset.id
        } catch {
            failureMessage = Self.failureText
        }
    }

    func next() async { await step(1) }
    func previous() async { await step(-1) }

    func random() async {
        let others = presets.filter { $0 != current }
        guard let pick = others.randomElement() else { return }
        await select(pick)
    }

    private func step(_ delta: Int) async {
        guard !presets.isEmpty else { return }
        let index = current.flatMap { presets.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        await select(presets[(index + delta + presets.count) % presets.count])
    }
}
