// SceneStoreRemapping.swift — the one change an import makes to a scene (FILE-001-R11; research
// FILE-001-D6): each named photo/video asset gets the store ID its media received on this device.
// Asset keys, layers, parameters, bindings, unknown content and the assets' own extra fields stay.
import SceneFormat

extension SceneDocument {
    /// The document with the store IDs of the photo/video assets in `storeIDs` (asset key → new
    /// canonical UUID) replaced. Keys not in the document, or naming another asset type, are ignored.
    public func remappingStoreIDs(_ storeIDs: [String: String]) -> SceneDocument {
        var copy = self
        for (key, newID) in storeIDs {
            guard let asset = copy.assets[key] else { continue }
            switch asset.kind {
            case .photo: copy.assets[key] = SceneAsset(.photo(storeID: newID), extra: asset.extra)
            case .video: copy.assets[key] = SceneAsset(.video(storeID: newID), extra: asset.extra)
            default: continue
            }
        }
        return copy
    }

    /// The photo/video assets as (key, type, store ID), sorted by key.
    public var mediaAssets: [(key: String, type: SceneArchiveAssetType, storeID: String)] {
        assets.keys.sorted().compactMap { (key: String) -> (key: String, type: SceneArchiveAssetType, storeID: String)? in
            switch assets[key]?.kind {
            case let .photo(id)?: (key, .photo, id)
            case let .video(id)?: (key, .video, id)
            default: nil
            }
        }
    }
}
