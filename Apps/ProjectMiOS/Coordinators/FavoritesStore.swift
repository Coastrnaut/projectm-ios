// FavoritesStore.swift — favorites and the last-selected preset (task T089; FR-044, FR-065).
//
// Persists exactly two UserDefaults keys: `favorites` (preset ids) and `lastPresetID`. Nothing else
// about presets or listening is stored (FR-065).
import Foundation

final class FavoritesStore {
    static let favoritesKey = "favorites"
    static let lastPresetKey = "lastPresetID"

    private let defaults: UserDefaults
    private var ids: Set<String>

    init(defaults: UserDefaults) {
        self.defaults = defaults
        ids = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
    }

    /// Favorite preset ids, sorted.
    var favorites: [String] { ids.sorted() }

    func isFavorite(_ id: String) -> Bool { ids.contains(id) }

    /// Marks or unmarks a favorite and saves at once.
    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        defaults.set(favorites, forKey: Self.favoritesKey)
    }

    var lastPresetID: String? {
        get { defaults.string(forKey: Self.lastPresetKey) }
        set { defaults.set(newValue, forKey: Self.lastPresetKey) }
    }
}
